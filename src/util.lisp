(in-package :autoload)

;;; Since ASDF/SESSION is an implementation package, we cannot be sure
;;; that *ASDF-SESSION* will remain there. Assuming that the
;;; SYMBOL-NAME remains the same, we search for the first ASDF package
;;; that has a symbol named *ASDF-SESSION*.
(defvar *asdf-session-symbol*
  (flet ((asdf-package-name-p (name)
           (or (string= name (string '#:asdf))
               (eql (search (string '#:asdf/) name) 0))))
    (let ((asdf-packages (remove-if-not #'asdf-package-name-p
                                        (list-all-packages)
                                        :key #'package-name)))
      (loop for package in asdf-packages
              thereis (uiop:find-symbol* '#:*asdf-session* package
                                         nil)))))

;;; KLUDGE: Hide any enclosing ASDF session. This allows a nested
;;; ASDF:OPERATE with :FORCE T to execute.
(defmacro without-asdf-session (&body body)
  ;; Bind ASDF/SESSION:*ASDF-SESSION* to NIL.
  `(let (,@(when *asdf-session-symbol*
             `((,*asdf-session-symbol* nil))))
     ,@body))

;;; Detect some common constant forms that are print-read consistent
;;; given only the existence of the standard packages :CL and
;;; :KEYWORD and PACKAGE-NAMES.
(defun simple-constant-form-p (form packages)
  (let* ((cl-package (find-package :cl))
         (packages (cons cl-package packages)))
    (labels
        ((simple-self-evaluating-form-p (form)
           (or (stringp form) (numberp form) (characterp form) (keywordp form)
               (and (symbolp form)
                    ;; In other packages, constants can become non-constant.
                    (eq (symbol-package form) cl-package)
                    (constantp form))))
         (recurse (form depth)
           (cond ((atom form)
                  (or (simple-self-evaluating-form-p form)
                      (and (symbolp form)
                           (member (symbol-package form) packages))))
                 ;; Circularities and deep nesting bail out here.
                 ((= depth 100)
                  (return-from simple-constant-form-p nil))
                 ((and (recurse (car form) (1+ depth))
                       (recurse (cdr form) (1+ depth)))))))
      (or (simple-self-evaluating-form-p form)
          (and (consp form)
               (eq (car form) 'quote)
               (consp (cdr form))
               (null (cddr form))
               (recurse (second form) 0))))))

(defun find-package-or-error (designator)
  (or (find-package designator)
      (error "~@<~S does not denote a package.~:@>" designator)))

(defmacro with-file-superseded ((stream pathname) &body body)
  `(with-open-file (,stream ,pathname :direction :output
                            :if-does-not-exist :create
                            :if-exists :supersede)
     ,@body))

(defun find-docstring-in-body (body)
  (or
   ;; DEFUN syntax
   (loop for rest on body
         for form = (car rest)
         if (and (stringp form) (cdr rest))
           return form
         unless (and (consp form) (eq (car form) 'declare))
           return nil)
   ;; DEFGENERIC and DEFCLASS syntax
   (loop for form in body
           thereis (and (consp form)
                        (eq (car form) :documentation)
                        (consp (cdr form))
                        (second form)))))


;;;; Cargo-culted from DREF::FDEFINITION*

(defun fdefinition* (name)
  (ignore-errors
   #+abcl
   (or (system::untraced-function name)
       (fdefinition name))
   #+clisp
   (if (listp name)
       (eval `(function ,name))
       (or (system::get-traced-definition name)
           (fdefinition name)))
   #-(or abcl clisp)
   (unencapsulated-function (fdefinition name))))

(defun unencapsulated-function (function)
  (or #+ccl (ccl::find-unencapsulated-definition function)
      #+cmucl (loop for fn = function then (fwrappers:fwrapper-next fn)
                    while (typep fn 'fwrappers:fwrapper)
                    finally (return fn))
      #+ecl (when (and (consp function)
                       (eq (car function) 'si:macro))
              function)
      #+ecl (find-type-in-sexp (function-lambda-expression function) 'function)
      #+ecl (find function si::*trace-list* :key #'second)
      #+sbcl (maybe-find-encapsulated-function function)
      function))

#+ecl
(defun find-type-in-sexp (form type)
  (cond ((typep form type) form)
        ((consp form)
         (or (find-type-in-sexp (car form) type)
             (find-type-in-sexp (cdr form) type)))
        (t nil)))

#+sbcl
;;; Tracing typically encapsulates a function in a closure. The
;;; function we need is at the end of the encapsulation chain.
(defun maybe-find-encapsulated-function (function)
  (declare (type function function))
  (if (eq (sb-impl::%fun-name function) 'sb-impl::encapsulation)
      (maybe-find-encapsulated-function
       (sb-impl::encapsulation-info-definition
        (sb-impl::encapsulation-info function)))
      function))


;;;; Global bindings of specials
;;;;
;;;; On Lisps that don't support access to global bindings, we fall
;;;; back to the current binding.

(defun symbol-globally-boundp (symbol)
  #-ecl (null (nth-value 1 (symbol-global-value symbol)))
  #+ecl (ffi:c-inline (symbol) (:object) :object
                      "(#0->symbol.value == OBJNULL) ? ECL_NIL : ECL_T"
                      :one-liner t))

(defun symbol-global-value (symbol)
  (check-type symbol symbol)
  #+allegro
  (multiple-value-bind (value bound) (sys:global-symbol-value symbol)
    (values value (eq bound :unbound)))
  #+ccl
  (let ((value (ccl::%sym-global-value symbol)))
    (values value (eq value (ccl::%unbound-marker))))
  #+ecl
  (if (symbol-globally-boundp symbol)
      (values (ffi:c-inline (symbol) (:object) :object
                            "#0->symbol.value" :one-liner t)
              nil)
      (values nil t))
  #+sbcl
  (ignore-errors (sb-ext:symbol-global-value symbol))
  #-(or allegro ccl ecl sbcl)
  (ignore-errors (symbol-value symbol)))

(defun set-symbol-global-value (symbol value)
  #+allegro
  (setf (sys:global-symbol-value symbol) value)
  #+ccl
  (ccl::%set-sym-global-value symbol value)
  #+ecl
  (progn (ffi:c-inline (symbol value) (:object :object) :void
                       "#0->symbol.value = #1"
                       :one-liner t)
         value)
  #+sbcl
  (setf (sb-ext:symbol-global-value symbol) value)
  #-(or allegro ccl ecl sbcl)
  (setf (symbol-value symbol) value))

(defsetf symbol-global-value set-symbol-global-value)
