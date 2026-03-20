(in-package :autoload)

;;; The AUTOLOAD-SYSTEM being in which the current file is being
;;; compiled or loaded
(defvar *autoload-system* nil)

(defmacro autoload (name asdf-system-name &key (lambda-list nil lambda-list-p)
                    (docstring nil docstringp))
  "Define a stub function with NAME to [load][asdf:load-system]
  ASDF-SYSTEM-NAME and return NAME. The arguments are not evaluated.
  If NAME has a [function definition][fdefinition pax:clhs] and it is
  not FUNCTION-AUTOLOAD-P, then do nothing and return NIL.

  The stub is not defined at [compile time][pax:clhs], which matches
  the required semantics of DEFUN. NAME is DECLAIMed with FTYPE
  FUNCTION and NOTINLINE.

  - The stub is defined with DOCSTRING if specified, else with a
    generic docstring that says what system it autoloads.

  - For introspective purposes only, the stub's arglist is set to
    LAMBDA-LIST if specified and it's supported on the
    platform (currently only SBCL). The arglist is shown by e.g.
    @SLIME-AUTODOC and returned by DREF:ARGLIST.

  Consistency checks:

  - The autoloaded system is expected to redefine NAME. If it doesn't,
    then an error will be signalled. If NAME is redefined but not with
    DEFUN/AUTOLOADED, then a warning is signalled.

  - When the AUTOLOAD form is macroexpanded in the process of ASDF
    compilation or load of an AUTOLOAD-SYSTEM, a warning is emitted if
    ASDF-SYSTEM-NAME is not among the declared
    SYSTEM-AUTOLOADED-SYSTEMS of that system."
  (when *autoload-system*
    (let ((asdf-system-name (asdf:coerce-name asdf-system-name))
          (system-autoloaded-systems
            (system-autoloaded-systems *autoload-system*)))
      (unless (find asdf-system-name system-autoloaded-systems :test #'equal)
        (warn "~@<~S, the system to be autoloaded for function ~S, is ~
              not among ~S, the ~S of ~S.~:@>"
              asdf-system-name name system-autoloaded-systems
              'system-autoloaded-systems
              (asdf:component-name *autoload-system*)))))
  `(progn
     (declaim
      ;; This is mainly to prevent undefined function compilation
      ;; warnings about NAME. A normal DEFUN takes care of this at
      ;; compile time, but the DEFUN below is not a [top level
      ;; form][pax:clhs].
      ;;
      ;; Also, this works around a CMUCL bug that results in
      ;; "Function with declared result type NIL returned" errors
      ;; when the real function definition returns.
      (ftype function ,name)
      ;; And this is needed because we are actively redefining the
      ;; function.
      (notinline ,name))
     (when (or (null (fdefinition* ',name))
               (function-autoload-p ',name))
       (defun ,name (&rest args)
         ,(if docstringp
              docstring
              (format nil "[AUTOLOADed][pax:macro] function in the ~
                          ~A ASDF:SYSTEM."
                      (%escape-markdown asdf-system-name)))
         (load-system-and-check-redefinition ',asdf-system-name ',name)
         ;; Make sure that the function redefined by
         ;; ASDF:LOAD-SYSTEM is invoked and not this stub, which
         ;; could be the case without the FDEFINITION call.
         (apply (fdefinition ',name) args))
       #+sbcl
       ,@(when lambda-list-p
           `((setf (sb-c::%fun-lambda-list (fdefinition ',name))
                   ',lambda-list)))
       (setf (get ',name 'autoload-fn) (fdefinition ',name))
       ',name)))

;;; Even though ASDF:SYSTEM names rarely contain special Markdown
;;; characters, play nice with PAX and escape the names if
;;; MGL-PAX:ESCAPE-MARKDOWN is loaded.
(defun %escape-markdown (string)
  (let ((symbol (uiop:find-symbol* '#:escape-markdown '#:mgl-pax nil)))
    (if (and symbol (not (function-autoload-p symbol)))
        (funcall symbol string)
        string)))

(defun load-system-and-check-redefinition (asdf-system-name function-name)
  (unless (asdf:find-system asdf-system-name nil)
    (error "~@<Could not ~S ASDF:SYSTEM ~S for function ~S. ~
           It may not be installed.~:@>"
           'autoload asdf-system-name function-name))
  (let ((this-stub (fdefinition* function-name)))
    (asdf:load-system asdf-system-name)
    (check-redefinition this-stub function-name asdf-system-name)))

(defun check-redefinition (original-stub name asdf-system-name)
  (when (eq (fdefinition* name) original-stub)
    (error "~@<Autoloaded function ~S was not redefined ~
           by the ~S ASDF:SYSTEM.~:@>"
           name asdf-system-name))
  (cond ((function-autoload-p name)
         (warn "~@<Autoloaded function ~S was redefined with ~S ~
               in the ~S ASDF:SYSTEM.~:@>"
               name 'autoload asdf-system-name))
        ((functionp (get name 'autoload-fn))
         (warn "~@<Autoloaded function ~S was redefined but not by ~S ~
               in the ~S ASDF:SYSTEM.~:@>"
               name 'defun/autoloaded asdf-system-name))
        (t
         (assert (eq (get name 'autoload-fn) :resolved)))))

(defun function-autoload-p (name)
  "See if NAME's function definition is an autoloader function
  established by [AUTOLOAD][pax:macro]."
  ;; This detects redefinitions by DEFUN too.
  (eq (get name 'autoload-fn) (fdefinition* name)))

(defmacro defun/autoloaded (name lambda-list &body body)
  "Like DEFUN, but silence redefinition warnings. Also, warn if NAME
  does not denote a function or it was never FUNCTION-AUTOLOAD-P."
  ;; We could also remember autoloaded functions (e.g. in an
  ;; :AROUND-COMPILE in the ASDF system definition) and generate
  ;; autoload definitions.
  (maybe-record-autoload-info `(defun/autoloaded ,name ,lambda-list
                                 ,(when (and (stringp (first body))
                                             (< 1 (length body)))
                                    (first body))
                                 ,*autoload-system*))
  `(progn
     (check-defun/autoloaded ',name)
     (without-redefinition-warnings
       (defun ,name ,lambda-list
         ,@body))
     ;; Leave the property around so that CHECK-DEFUN/AUTOLOADED knows
     ;; not to warn when a DEFUN/AUTOLOADED is evaluated multiple
     ;; times (e.g. during interactive development).
     (setf (get ',name 'autoload-fn) :resolved)))

(defun check-defun/autoloaded (name)
  (cond ((null (fdefinition* name))
         (warn "~@<~S function ~S not defined.~:@>" 'defun/autoloaded name))
        ((not (or (function-autoload-p name)
                  (eq (get name 'autoload-fn) :resolved)))
         (warn "~@<~S function ~S not ~S.~:@>" 'defun/autoloaded name
               'function-autoload-p))))

(defmacro defvar/autoloaded (var &optional (val nil valp) (doc nil docp))
  "Like DEFVAR, but works with the global binding on Lisps that
  support it (currently Allegro, CCL, ECL, SBCL). This is to
  handle the case when a system that uses DEFVAR with a default value
  is autoloaded while that variable is locally bound:

  ```cl-transcript
  ;; Some base system only foreshadows *X*.
  (declaim (special *x*))
  (let ((*x* 1))
    ;; Imagine that the system that defines *X* is autoloaded here.
    (defvar/autoloaded *x* 2)
    *x*)
  => 1
  ```"
  ;; FIXME
  (assert (special-variable-name-p var))
  (maybe-record-autoload-info
   `(defvar/autoloaded ,var ,doc ,*autoload-system*))
  `(progn
     (defvar ,var)
     ,@(when valp
         `((unless (symbol-globally-boundp ',var)
             (setf (symbol-global-value ',var) ,val))))
     ,@(when docp
         `((setf (documentation ',var 'variable) ,doc)))))


(defclass autoload-cl-source-file (asdf:cl-source-file)
  ())

(defmethod asdf:perform :around ((op asdf:compile-op)
                                 (c autoload-cl-source-file))
  (let ((*autoload-system* (asdf:component-system c)))
    (call-next-method)))

(defmethod asdf:perform :around ((op asdf:load-op)
                                 (c autoload-cl-source-file))
  (let ((*autoload-system* (asdf:component-system c)))
    (call-next-method)))

(defmethod asdf:perform :around ((op asdf:load-source-op)
                                 (c autoload-cl-source-file))
  (let ((*autoload-system* (asdf:component-system c)))
    (call-next-method)))


(defclass autoload-system (asdf:system)
  ((system-autoloaded-systems
    :initarg :autoloaded-systems
    :initform nil
    :reader system-autoloaded-systems
    :documentation "Return the list of the names of systems autoloaded
    directly by this system. The names are canonicalized with
    ASDF:COERCE-NAME.")
   (record-autoloads
    :initform nil
    :initarg :record-autoloads
    :reader system-record-autoloads
    :documentation "This specifies where autoload definitions shall be
    written by RECORD-SYSTEM-AUTOLOADS.")
   ;; KLUDGE: (:DEFAULT-INITARGS :DEFAULT-COMPONENT-CLASS
   ;; 'AUTOLOAD-CL-SOURCE-FILE) doesn't work, so do it directly.
   (asdf::default-component-class :initform 'autoload-cl-source-file))
  (:documentation "Inheriting from this class in your ASDF:DEFSYSTEM
  form enables the following features.

  - [AUTOLOAD][pax:macro] checks the correctness of
    [:AUTOLOADED-SYSTEMS][ system-autoloaded-systems].

  - [:RECORD-AUTOLOADS][ system-record-autoloads] can be specified to
    tell RECORD-SYSTEM-AUTOLOADS where to write the generated autoload
    forms.

  ```
  (asdf:defsystem \"some-system\"
    :defsystem-depends-on (\"autoload\")
    :class \"autoload:autoload-system\"
    :autoloaded-systems (\"other-system\")
    :record-autoloads (\"src/autoloads.lisp\" :package #:my-pkg)
  ```"))

(defmethod shared-initialize :after ((system autoload-system) slot-names
                                     &key &allow-other-keys)
  (declare (ignore slot-names))
  (setf (slot-value system 'system-autoloaded-systems)
        (mapcar #'asdf:coerce-name
                (slot-value system 'system-autoloaded-systems))))

;;; ASDF:PERFORM is designed for side effects, and we can't just
;;; return stuff normally. LIST-AUTOLOADS-OP gathers systems here.
(defvar *listed-autoloaded-systems*)

(defclass list-autoloads-op (asdf:sideway-operation)
  ())

(defmethod asdf:operation-done-p ((op list-autoloads-op) (c asdf:component))
  nil)

(defmethod asdf:perform ((op list-autoloads-op) (system autoload-system))
  (dolist (s (system-autoloaded-systems system))
    (pushnew s *listed-autoloaded-systems* :test #'equal)))

(defmethod asdf:perform ((op list-autoloads-op) (system asdf:system))
  nil)

(defun autoloaded-systems (system &key (follow-autoloaded t) installer)
  "Return the list of the names of systems that may be autoloaded by
  SYSTEM or any of its normal dependencies (the transitive closure of
  its :DEPENDS-ON). This works even if SYSTEM is not an
  AUTOLOAD-SYSTEM.

  - If FOLLOW-AUTOLOADED, look further for autoloaded systems among
    the normal and autoloaded dependencies of any autoloaded systems
    found. If an autoloaded system is not installed (i.e.
    ASDF:FIND-SYSTEM fails), then that system is not followed.

  - If INSTALLER is non-NIL, it is called when a system encounteres a
    system that is not installed. This is an autoloaded system if
    normal ASDF dependencies are installed as is the case with e.g.
    @QUICKLISP. INSTALLER is passed a single argument, the name of the
    system to be installed, and it may or may not install the system.

      The following example, makes sure that all normal and autoloaded
      dependencies (direct or indirect) of `my-system` are installed:

          (autoloaded-systems \"my-system\" :installer #'ql:quickload)"
  (let ((*listed-autoloaded-systems* ()))
    (asdf:operate 'list-autoloads-op system :force t)
    (when follow-autoloaded
      (loop with processed = ()
            for pending = (set-difference *listed-autoloaded-systems* processed
                                          :test #'equal)
            while pending
            do (dolist (s pending)
                 (when (and (null (asdf:find-system s nil))
                            installer)
                   (funcall installer s))
                 (when (asdf:find-system s nil)
                   (asdf:operate 'list-autoloads-op s :force t)))
               (setq processed (append pending processed))))
    (reverse *listed-autoloaded-systems*)))


(defvar *recording-from-system* nil)
(defvar *recorded-autoload-infos*)

(defun maybe-record-autoload-info (info)
  ;; Do not record definitions from dependencies of autoloaded
  ;; systems.
  (when (and *recording-from-system*
             (eq *recording-from-system* *autoload-system*))
    (push info *recorded-autoload-infos*)))

(defun autoloads (system &key (lambda-lists t) (docstrings t))
  "Return a list forms that set up autoloading for definitions such as
  DEFUN/AUTOLOADED in [autoloaded direct dependencies][
  SYSTEM-AUTOLOADED-SYSTEMS] of SYSTEM. For DEFUN/AUTOLOADED, this is
  an [AUTOLOAD][pax:macro] form; for DEFVAR/AUTOLOADED, this is a
  DECLAIM SPECIAL.

  - If LAMBDA-LISTS, then the autoload forms will pass the LAMBDA-LIST
    argument of the corresponding DEFUN/AUTOLOADED to AUTOLOAD.

  - If DOCSTRINGS, then the docstrings extracted from DEFUN/AUTOLOADED
    or DEFVAR/AUTOLOADED will be associated with the definition.

  Note that this is an expensive operation, as it reloads the direct
  dependencies one by one with ASDF:LOAD-SYSTEM :FORCE and records the
  association with the system and the autoloaded definitions such as
  DEFUN/AUTOLOADED."
  (mapcan (lambda (info)
            (info-to-autoload-forms info
                                    :include-lambda-list lambda-lists
                                    :include-docstring docstrings))
          (mapcan #'extract-autoload-infos (system-autoloaded-systems
                                            (asdf:find-system system)))))

(defun write-autoloads (forms stream &key (package :cl-user))
  "Write the autoload FORMS to OUTPUT that can be LOADed. When
  PACKAGE, emit an IN-PACKAGE form with its name, and print the forms
  with *PACKAGE* bound to it.

  - OUTPUT can be a STREAM, NIL or T with the same semantics as the
    `DESTINATION` argument of FORMAT. If OUTPUT is a STRING or a
    PATHNAME, then it is OPENed as file (with :SUPERSEDE), and the
    forms are written to it."
  (let ((*package* (if package
                       (find-package package)
                       *package*))
        (*print-pretty* t)
        (*print-case* :downcase))
    (when package
      (let ((*package* (find-package :keyword)))
        (format stream "~S~%~%"
                `(in-package ,(package-name package)))))
    (format stream "~{~S~%~^~%~}" forms)))

(defun extract-autoload-infos (system)
  (let* ((system (asdf:find-system system))
         (*recording-from-system* system)
         (*recorded-autoload-infos* ()))
    (asdf:load-system system :force t)
    *recorded-autoload-infos*))

(defun info-to-autoload-forms (extract &key include-lambda-list
                                         include-docstring)
  (let ((definer (first extract)))
    (ecase definer
      ((defun/autoloaded)
       (destructuring-bind (name lambda-list docstring system)
           (rest extract)
         `((autoload ,name ,(asdf:component-name system)
                     ,@(when include-lambda-list
                         `((:lambda-list ',lambda-list)))
                     ,@(when include-docstring
                         `((:docstring ,docstring)))))))
      ((defvar/autoloaded)
       (destructuring-bind (name docstring system) (rest extract)
         (declare (ignore system))
         `((declaim (special ,name))
           ,@(when (and include-docstring docstring)
               `((setf (documentation ',name 'variable) ,docstring)))))))))

(defun record-autoloads (system output &key (lambda-lists t) (docstrings t)
                         (package :cl-user))
  (write-autoloads (autoloads system :lambda-lists lambda-lists
                              :docstrings docstrings)
                   output :package package))

(defun record-system-autoloads (system)
  "Write the AUTOLOADS of SYSTEM to the file in its
  [:RECORD-AUTOLOADS][ SYSTEM-RECORD-AUTOLOADS], which may be a
  [pathname designator][pax:clhs] or a list of the form

      (pathname &key (lambda-lists t) (docstrings t) (package :cl-user))

  See [AUTOLOADS][pax:macro] and WRITE-AUTOLOADS for the description
  of these arguments."
  (let ((system (asdf:find-system system)))
    (check-type system autoload-system)
    (multiple-value-bind (pathname args) (system-record-autoloads* system)
      (with-open-file (stream (asdf:system-relative-pathname system pathname)
                              :direction :output
                              :if-does-not-exist :create
                              :if-exists :supersede)
        (format stream ";;;; This file was generated by~
                        ;;;;~
                        ;;;;   ~S~%~%"
                `(record-system-autoloads ,(asdf:component-name system)))
        (apply #'record-autoloads system stream args)))))

(defun system-record-autoloads* (system)
  (let ((args (uiop:ensure-list (system-record-autoloads system))))
    (handler-case
        (destructuring-bind (pathname &key (lambda-lists t) (docstrings t)
                             (package :cl-user))
            args
          (declare (ignore lambda-lists docstrings package))
          (check-type pathname (or string pathname))
          (values pathname (rest args)))
      ((and error (not type-error)) ()
        (error "~@<~S, the ~S of ~S, is not of the form ~S.~:@>"
               args :record-autoloads (asdf:component-name system)
               '(pathname &key (lambda-lists t) (docstrings t)
                 (package :cl-user)))))))

#+nil
(write-autoload-forms (autoload-forms "mgl-pax") t)
#+nil
(system-autoloaded-systems (asdf:find-system "mgl-pax"))
#+nil
(record-system-autoloads "autoload")
