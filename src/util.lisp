(in-package :autoload)

(defun fdefinition* (name)
  (ignore-errors (fdefinition name)))

(defun external-symbol-p (symbol &optional (package (symbol-package symbol)))
  (and package
       (multiple-value-bind (symbol* status)
           (find-symbol (symbol-name symbol) package)
         (and (eq status :external)
              (eq symbol symbol*)))))

;;; KLUDGE: Hide any enclosing ASDF session. This allows a nested
;;; ASDF:OPERATE with :FORCE T operate to execute.
(defmacro without-asdf-session (&body body)
  ;; Bind ASDF/SESSION:*ASDF-SESSION* to NIL. Since ASDF/SESSION is an
  ;; implementation package, we cannot be sure that *ASDF-SESSION*
  ;; will remain there. Assuming that the SYMBOL-NAME remains the
  ;; same, we search for the first ASDF package that has a symbol
  ;; named *ASDF-SESSION*.
  (flet ((asdf-package-name-p (name)
           (or (string= name (string '#:asdf))
               (eql (search (string '#:asdf/) name) 0))))
    (let* ((asdf-packages (remove-if-not #'asdf-package-name-p
                                         (list-all-packages)
                                         :key #'package-name))
           (sym (loop for package in asdf-packages
                        thereis (uiop:find-symbol* '#:*asdf-session* package
                                                   nil))))
      `(let (,@(when sym `((,sym nil))))
         ,@body))))


(defun special-variable-name-p (obj)
  (and (symbolp obj)
       #+abcl (ext:special-variable-p obj)
       #+allegro (eq (sys:variable-information obj) :special)
       #+ccl (eq (ccl::variable-information obj) :special)
       #+clisp (and (ext:special-variable-p obj)
                    (not (constant-variable-name-p obj)))
       #+cmucl (eq (ext:info :variable :kind obj) :special)
       #+ecl (or (si:specialp obj)
                 (constant-variable-name-p obj))
       #+sbcl (member (sb-int:info :variable :kind obj) '(:special))))

(defun constant-variable-name-p (obj)
  (and (symbolp obj)
       (not (keywordp obj))
       ;; CONSTANTP may detect constant symbol macros, for example.
       (boundp obj)
       (constantp obj)))


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
