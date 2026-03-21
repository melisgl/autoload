(in-package :autoload)

;;;; Machinery for associating autoload stubs with function names,
;;;; including setf names, and for recording the state of variable
;;;; definitions.

(declaim (inline kind-to-indicator))

;;; Translate KIND to an package internal variable, which we use as an
;;; indicator on SYMBOL-PLISTs.
(defun kind-to-indicator (kind)
  (ecase kind
    ((:function) 'autoload-function)
    ((:variable) 'autoload-variable)))

(defun state (name kind)
  (multiple-value-bind (name setf*) (unpack-function-name name)
    (getf (get name (kind-to-indicator kind)) setf*)))

(defun unpack-function-name (name)
  (cond ((symbolp name)
         (values name nil))
        ;; (SETF NAME) => NAME SETF.
        ((and (consp name)
              (eq (car name) 'setf)
              (consp (cdr name))
              (symbolp (cadr name))
              (null (cddr name)))
         (values (second name) (first name)))
        (t
         (error "~@<Unsupported function name ~S.~:@>" name))))

(defun set-state (name kind fn)
  (multiple-value-bind (name setflike) (unpack-function-name name)
    (setf (getf (get name (kind-to-indicator kind)) setflike)
          fn)))

(defsetf state set-state)


;;;; @FUNCTIONS

(defmacro autoload (name asdf-system-name &key (arglist nil arglistp)
                    (docstring nil docstringp) (explicitp t))
  "Define a stub function with NAME to [load][asdf:load-system]
  ASDF-SYSTEM-NAME and return NAME. The arguments are not evaluated.
  If NAME has a [function definition][fdefinition pax:clhs] and it is
  not FUNCTION-AUTOLOAD-P, then do nothing and return NIL.

  The stub is not defined at [compile time][pax:clhs], which matches
  the required semantics of DEFUN. NAME is DECLAIMed with FTYPE
  FUNCTION and NOTINLINE.

  - ARGLIST will be installed as the stub's arglist if specified and
    it's supported on the platform (currently only SBCL). Arglists are
    for interactive purposes only. For example, they are shown by
    @SLIME-AUTODOC and returned by DREF:ARGLIST.

  - DOCSTRING, if specified, will be the stub's docstring. If not
    specified, a generic docstring that says what system it autoloads
    will be used.

  - EXPLICITP T indicates that ASDF-SYSTEM-NAME will redefine NAME by
    one of DEFUN/AUTOLOADED, DEFGENERIC/AUTOLOADED or
    DEFINE-AUTOLOADED-FUNCTION. EXPLICITP NIL indicates that the
    redefinition will use another mechanism (e.g. a DEFUN, as a
    DEFCLASS accessor, or even a `(`SETF FDEFINITION`)`).

  Thus, the system ASDF-SYSTEM-NAME is expected to redefine the
  function NAME. After loading it, the following checks are made.

  - It is an error if NAME is not redefined at all.

  - It is a warning if NAME is redefined with another
    [AUTOLOAD][pax:macro].

  - It is a warning if the promise of EXPLICITP is broken, as it
    indicates confusion whether @GENERATING-AUTOLOADS should be done
    automatically or not.

  Also, see SYSTEM-AUTOLOADED-SYSTEMS for further consistency
  checking."
  (declare (ignorable arglist))
  (check-function-autoload name asdf-system-name)
  `(progn
     (declaim
      ;; This is mainly to prevent undefined function compiler
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
         (load-system-and-check-redefinition ',asdf-system-name ',name
                                             ',explicitp)
         ;; Make sure that the function redefined by
         ;; ASDF:LOAD-SYSTEM is invoked and not this stub, which
         ;; could be the case without the FDEFINITION call.
         (apply (fdefinition ',name) args))
       #+sbcl
       ,@(when arglistp
           `((setf (sb-c::%fun-lambda-list (fdefinition* ',name))
                   ',arglist)))
       (setf (state ',name :function) (fdefinition* ',name))
       ',name)))

;;; Even though ASDF:SYSTEM names rarely contain special Markdown
;;; characters, play nice with PAX and escape the names if
;;; MGL-PAX:ESCAPE-MARKDOWN is loaded.
(defun %escape-markdown (string)
  (let ((symbol (uiop:find-symbol* '#:escape-markdown '#:mgl-pax nil)))
    (if (and symbol (not (function-autoload-p symbol)))
        (funcall symbol string)
        string)))

(defun load-system-and-check-redefinition (asdf-system-name function-name
                                           explicitp)
  (unless (asdf:find-system asdf-system-name nil)
    (error "~@<Could not ~S ASDF:SYSTEM ~S for function ~S. ~
           It may not be installed.~:@>"
           'autoload asdf-system-name function-name))
  (let ((this-stub (fdefinition* function-name)))
    (asdf:load-system asdf-system-name)
    (check-function-redefinition this-stub function-name asdf-system-name
                                 explicitp)))

(defun check-function-redefinition (original-stub name asdf-system-name
                                    explicitp)
  (when (eq (fdefinition* name) original-stub)
    (error "~@<Autoloaded function ~S was not redefined ~
           by the ~S ASDF:SYSTEM.~:@>"
           name asdf-system-name))
  (cond ((function-autoload-p name)
         (warn "~@<Autoloaded function ~S was redefined with ~S ~
               in the ~S ASDF:SYSTEM.~:@>"
               name 'autoload asdf-system-name))
        ((functionp (state name :function))
         (when explicitp
           (warn "~@<Autoloaded function ~S was redefined ~
                 in the ~S ASDF:SYSTEM but not by ~S, ~S or ~S.~:@>"
                 name asdf-system-name 'defun/autoloaded 'defgeneric/autoloaded
                 'define-autoloaded-function)))
        (t
         (assert (eq (state name :function) :resolved))
         (unless explicitp
           (warn "~@<Autoloaded function ~S was declared with ~S ~S but was ~
                 redefined in the ~S ASDF:SYSTEM explicitly by ~S, ~S ~
                 or ~S.~:@>"
                 name :explicitp nil asdf-system-name 'defun/autoloaded
                 'defgeneric/autoloaded 'define-autoloaded-function)))))

(defun function-autoload-p (name)
  "See if NAME's function definition is an autoloader function
   established by [AUTOLOAD][pax:macro]."
  ;; This detects redefinitions by DEFUN too.
  (eq (state name :function) (fdefinition* name)))

(defmacro defun/autoloaded (name lambda-list &body body)
  "Like DEFUN, but silence redefinition warnings. Also, warn if NAME
  has never been FUNCTION-AUTOLOAD-P."
  `(define-autoloaded-function defun ,name ,lambda-list ,@body))

(defmacro defgeneric/autoloaded (name lambda-list &body body)
  "Like DEFUN/AUTOLOADED, but define NAME with DEFGENERIC."
  `(define-autoloaded-function defgeneric ,name ,lambda-list ,@body))

(defmacro define-autoloaded-function (definer name lambda-list &body body)
  "Like DEFUN/AUTOLOADED, but establish a function binding for NAME
  with DEFINER. For example, the autoloaded counterpart to UIOP:DEFUN*
  can be defined as

      (defmacro defun*/autoloaded (name lambda-list &body body)
        `(define-autoloaded-function uiop:defun* ,name ,lambda-list ,@body))"
  (maybe-record-autoload-info `(defun/autoloaded ,name ,lambda-list
                                 ,(when (stringp (first body))
                                    (first body))))
  `(progn
     (before-autoloaded-function-definition ',name)
     (,definer ,name ,lambda-list ,@body)
     (after-autoloaded-function-definition ',name)
     ',name))

(defvar *suppress-has-not-been-declared-warnings* nil)

(defun before-autoloaded-function-definition (name)
  (unless (state name :function)
    (unless *suppress-has-not-been-declared-warnings*
      (warn "~@<Defining ~S as an autoloaded function, ~
            but it has not been declared with ~S.~:@>" name 'autoload)))
  ;; We don't want to FMAKUNBOUND a generic function and lose its
  ;; methods.
  (when (function-autoload-p name)
    ;; This prevents redefinition warnings and allows DEFINER to be a
    ;; DEFGENERIC without running into an error when trying to
    ;; redefine a DEFUN (the autoload stub).
    (fmakunbound name)))

(defun after-autoloaded-function-definition (name)
  ;; Leave the property around so that
  ;; BEFORE-AUTOLOADED-FUNCTION-DEFINITION knows not to warn when, for
  ;; example, a DEFUN/AUTOLOADED is evaluated multiple times (e.g.
  ;; during interactive development).
  (setf (state name :function) :resolved))


;;;; @VARIABLES

(defmacro defvar/autoload (var &key (initial-value nil initial-value-p)
                           docstring)
  "Like DEFVAR, but mark VAR as VARIABLE-AUTOLOAD-P. Unlike DEFVAR,
  this also allows for specifying a DOCSTRING even if INITIAL-VALUE is
  not provided.

  Note that on accessing VAR, nothing is autoloaded. DEFVAR/AUTOLOAD
  is solely to allow DEFVAR/AUTOLOADED to perform some checking."
  `(progn
     (defvar ,var
       ,@(when initial-value-p
           `(,initial-value)))
     ,@(when docstring
         `((setf (documentation ',var 'variable) ,docstring)))
     (setf (state ',var :variable) :declared)))

(defun variable-autoload-p (name)
  "See if NAME has been declared with DEFVAR/AUTOLOAD and not defined
  with DEFVAR/AUTOLOADED since."
  (eq (state name :variable) :declared))

(defmacro defvar/autoloaded (var &optional (val nil valp) doc)
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
  ```

  DEFVAR/AUTOLOADED warns if VAR has never been VARIABLE-AUTOLOAD-P."
  (maybe-record-autoload-info `(defvar/autoloaded ,var ,val ,valp ,doc))
  `(progn
     (before-autoloaded-variable-definition ',var)
     (defvar ,var)
     (after-autoloaded-variable-definition ',var ,val ,valp ,doc)
     ',var))

(defun before-autoloaded-variable-definition (name)
  (unless (state name :variable)
    (unless *suppress-has-not-been-declared-warnings*
      (warn "~@<Defining ~S with ~S, but it has not been declared with ~S.~:@>"
            name 'defvar/autoloaded 'defvar/autoload))))

(defun after-autoloaded-variable-definition (name val valp doc)
  (when valp
    (unless (symbol-globally-boundp name)
      (setf (symbol-global-value name) val)))
  (when doc
    (setf (documentation name 'function) doc))
  (setf (state name :variable) :resolved))


(defclass autoload-cl-source-file (asdf:cl-source-file)
  ())

;;; The AUTOLOAD-SYSTEM being in which the current file is being
;;; compiled or loaded
(defvar *autoload-system* nil)

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


;;;; @ASDF-INTEGRATION

(defclass autoload-system (asdf:system)
  ((system-autoloaded-systems
    :initarg :autoloaded-systems
    :initform nil
    :reader system-autoloaded-systems
    :documentation "Return the list of the names of systems declared
    to be autoloaded directly by this system. The names are
    canonicalized with ASDF:COERCE-NAME. In AUTOLOAD-SYSTEMs,
    [AUTOLOAD][pax:macro] signals an error if the ASDF:SYSTEM to be
    loaded is among those declared here.")
   (record-autoloads
    :initform nil
    :initarg :record-autoloads
    :reader system-record-autoloads
    :documentation "This specifies where the automatically extracted
    autoload forms shall be written by RECORD-SYSTEM-AUTOLOADS.")
   (test-autoloads
    :initform t
    :initarg :test-autoloads
    :reader system-test-autoloads
    :documentation "Specifies whether CHECK-SYSTEM-AUTOLOADS shall be
    invoked on ASDF:TEST-OP.")
   ;; KLUDGE: (:DEFAULT-INITARGS :DEFAULT-COMPONENT-CLASS
   ;; 'AUTOLOAD-CL-SOURCE-FILE) doesn't work, so do it directly.
   (asdf::default-component-class :initform 'autoload-cl-source-file))
  (:documentation "Inheriting from this class in your ASDF:DEFSYSTEM
  form enables the features documented in the reader methods. Consider
  the following example.

  ```
  (asdf:defsystem \"my-system\"
    :defsystem-depends-on (\"autoload\")
    :class \"autoload:autoload-system\"
    :autoloaded-systems (\"dyndep\")
    :record-autoloads (\"autoloads.lisp\" :package #:my-pkg)
    :components ((:file \"package\")
                 (:file \"autoloads\")
                 ...))
  ```

  With the above,

  - It is an error if an [AUTOLOAD][pax:macro] refers to a
    system other than `dyndep`.

  - `(`RECORD-SYSTEM-AUTOLOADS `\"my-system\")` will update
    `autoloads.lisp`.

  - `(`ASDF:TEST-SYSTEM `\"my-system\")` [checks][
    check-system-autoloads] that `autoload.lisp` is up-to-date."))

(defmethod shared-initialize :after ((system autoload-system) slot-names
                                     &key &allow-other-keys)
  (declare (ignore slot-names))
  (setf (slot-value system 'system-autoloaded-systems)
        (mapcar #'asdf:coerce-name
                (slot-value system 'system-autoloaded-systems)))
  #+clisp
  (unless (slot-value system 'asdf::default-component-class)
    (setf (slot-value system 'asdf::default-component-class)
          'autoload-cl-source-file)))

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
    (without-asdf-session
      (asdf:operate 'list-autoloads-op system :force t)
      (when follow-autoloaded
        (loop with processed = ()
              for pending = (set-difference *listed-autoloaded-systems*
                                            processed :test #'equal)
              while pending
              do (dolist (s pending)
                   (when (and (null (asdf:find-system s nil))
                              installer)
                     (funcall installer s))
                   (when (asdf:find-system s nil)
                     (asdf:operate 'list-autoloads-op s :force t)))
                 (setq processed (append pending processed)))))
    (reverse *listed-autoloaded-systems*)))

(defun check-function-autoload (name asdf-system-name)
  (when *autoload-system*
    (let ((asdf-system-name (asdf:coerce-name asdf-system-name))
          (system-autoloaded-systems
            (system-autoloaded-systems *autoload-system*)))
      (unless (find asdf-system-name system-autoloaded-systems :test #'equal)
        (warn "~@<~S, the system to be autoloaded for function ~S, is ~
              not among ~S, the ~S of ~S.~:@>"
              asdf-system-name name system-autoloaded-systems
              'system-autoloaded-systems
              (asdf:component-name *autoload-system*))))))


;;;; @GENERATING-DOCUMENTATION

(defvar *recording-from-system* nil)
(defvar *recorded-autoload-infos*)

(defun maybe-record-autoload-info (info)
  ;; Do not record definitions from dependencies of autoloaded
  ;; systems.
  (when (and *recording-from-system*
             (eq *recording-from-system* *autoload-system*))
    ;; This is called from a macro, and macros are allowed to be
    ;; expanded multiple times.
    (pushnew (cons (asdf:component-name *autoload-system*) info)
             *recorded-autoload-infos* :test #'equal)))

(defun autoloads (system &key (process-arglist t) (process-docstring t)
                  export-from)
  "Return a list of forms that set up autoloading for definitions such
  as DEFUN/AUTOLOADED in [autoloaded direct dependencies][
  SYSTEM-AUTOLOADED-SYSTEMS] of SYSTEM.

  - For function definitions such as DEFUN/AUTOLOADED, an
    [AUTOLOAD][pax:macro] form is emitted.

     If PROCESS-ARGLIST is T, then the autoload forms will pass the
     ARGLIST argument of the corresponding DEFUN/AUTOLOADED to
     AUTOLOAD. If it is NIL, then ARGLIST will not be passed to
     AUTOLOAD.

  - For DEFVAR/AUTOLOADED, a DEFVAR/AUTOLOAD is emitted.

     If the initial value form in DEFVAR/AUTOLOADED is detected as a
     simple constant form, then it is passed as :INITIAL-VALUE to
     DEFVAR/AUTOLOAD. Simple constant forms are strings, numbers,
     characters, keywords, constants in the CL package, and QUOTEd
     nested lists containing any of the previous or any symbol from
     the [CL][package].

  - If PROCESS-DOCSTRINGS, then the docstrings extracted from
    DEFUN/AUTOLOADED or DEFVAR/AUTOLOADED will be associated with the
    definition.

  - EXPORT-FROM is a package designator or a list thereof. If a NAME
    is involved in e.g. a DEFUN/AUTOLOADED or DEFVAR/AUTOLOADED, then
    an EXPORT form is added to the autoload forms for each package in
    EXPORT-FROM from which NAME is exported. For SETF names, the
    SECOND element is exported. EXPORT-FROM is not needed in the usual
    case of a static DEFPACKAGE, but is a convenient way to foreshadow
    the exports dynamically performed by an autoloaded system.

  Note that if a function is not defined by DEFUN/AUTOLOADED or its
  kin in @BASICS, then AUTOLOADS will not detect it. For such
  functions, [AUTOLOAD][pax:macro]s must be written manually using the
  MANUALP argument.

  Also note that this is an expensive operation, as it reloads the direct
  dependencies one by one with ASDF:LOAD-SYSTEM :FORCE and records the
  association with the system and the autoloaded definitions such as
  DEFUN/AUTOLOADED."
  (without-asdf-session
    (mapcan (lambda (info)
              (info-to-autoload-forms info process-arglist process-docstring
                                      export-from))
            (mapcan #'extract-autoload-infos (system-autoloaded-systems
                                              (asdf:find-system system))))))

(defun write-autoloads (forms stream &key package)
  "Write the autoload FORMS to STREAM that can be LOADed. When
  PACKAGE, emit an IN-PACKAGE form with its name, and print the forms
  with *PACKAGE* bound to it."
  (let ((*package* (if package
                       (find-package-or-error package)
                       *package*))
        (*print-pretty* t)
        (*print-case* :downcase))
    (when package
      (let ((*package* (find-package :keyword)))
        (format stream "~S~%~%"
                `(in-package ,(safe-package-designator package)))))
    (format stream "~{~S~%~^~%~}" forms)))

;;; This gets printed as :CL-USER, which works in many cases
;;; regardless of readtable case especially when used in conjunction
;;; with *PRINT-CASE* :DOWNCASE. Using uninterned symbols would break
;;; CHECK-FUNCTION-AUTOLOAD, which uses EQUAL to compare autoload
;;; forms.
(defun safe-package-designator (package)
  (intern (package-name package) :keyword))

(defun extract-autoload-infos (system)
  (let* ((system (asdf:find-system system))
         (*recording-from-system* system)
         (*recorded-autoload-infos* ()))
    (asdf:load-system system :force t)
    (reverse *recorded-autoload-infos*)))

(defun info-to-autoload-forms (info process-arglist process-docstring
                               export-from)
  (let ((asdf-system-name (first info))
        (definer (second info))
        (name (third info)))
    (append (ecase definer
              ((defun/autoloaded)
               (destructuring-bind (arglist docstring) (cdddr info)
                 `((autoload ,name ,asdf-system-name
                             ,@(when process-arglist
                                 `(:arglist ',arglist))
                             ,@(let ((docstring
                                       ;; Prefer the current one.
                                       (or (documentation name 'function)
                                           docstring)))
                                 (when (and process-docstring docstring)
                                   `(:docstring ,docstring)))))))
              ((defvar/autoloaded)
               (destructuring-bind (val-form valp docstring) (cdddr info)
                 `((defvar/autoload ,name
                       ,@(when (and valp (simple-constant-form-p val-form))
                           `(:initial-value ,val-form))
                     ,@(let ((docstring
                               (or (documentation name 'variable)
                                   docstring)))
                         (when (and process-docstring docstring)
                           `(:docstring ,docstring))))))))
            (when export-from
              (let ((name (unpack-function-name name)))
                (loop for pkg-designator in export-from
                      for pkg = (find-package-or-error pkg-designator)
                      when (and pkg (external-symbol-p name pkg))
                        collect `(export ',name
                                         ,(safe-package-designator pkg))))))))

(defun record-autoloads (system output &key (process-arglist t)
                         (process-docstring t) package export-from)
  (write-autoloads (autoloads system :process-arglist process-arglist
                              :process-docstring process-docstring
                              :export-from export-from)
                   output :package package))

(defun record-system-autoloads (system)
  "Write the AUTOLOADS of SYSTEM to the file in its
  [:RECORD-AUTOLOADS][ SYSTEM-RECORD-AUTOLOADS], which may be a
  [pathname designator][pax:clhs] or a list of the form

      (pathname &key (process-arglist t) (process-docstring t)
                     package export-from)

  See [AUTOLOADS][function] and WRITE-AUTOLOADS for the description of
  these arguments. PATHNAME is relative to
  ASDF:SYSTEM-SOURCE-DIRECTORY of SYSTEM and is OPENed with :IF-EXISTS
  :SUPERSEDE."
  (let ((system (asdf:find-system system)))
    (check-type system autoload-system)
    (multiple-value-bind (pathname args) (system-record-autoloads* system)
      (let ((pathname (asdf:system-relative-pathname system pathname)))
        (with-file-superseded (stream pathname)
          (let ((*print-case* :downcase)
                (*package* (find-package :keyword)))
            (format stream ";;;; This file was emptied by
                          ;;;;~%~
                          ;;;;   ~S~%~
                          ;;;;~%~
                          ;;;; Recording is ongoing or has failed. ~
                               Do not edit.~%~%"
                    `(record-system-autoloads ,(asdf:component-name system)))))
        (with-file-superseded (stream pathname)
          (let ((*print-case* :downcase)
                (*package* (find-package :keyword)))
            (format stream ";;;; This file was generated by~%~
                            ;;;;~%~
                            ;;;;   ~S~%~
                            ;;;;~%~
                            ;;;; Do not edit.~%~%"
                    `(record-system-autoloads ,(asdf:component-name system))))
          (let ((*suppress-has-not-been-declared-warnings* t))
            (apply #'record-autoloads system stream args)))))))

(defun system-record-autoloads* (system)
  (let ((args (uiop:ensure-list (system-record-autoloads system))))
    (handler-case
        (destructuring-bind (pathname &key (process-arglist t)
                             (process-docstring t) package export-from)
            args
          (check-type pathname (or string pathname))
          (values pathname `(:process-arglist ,process-arglist
                             :process-docstring ,process-docstring
                             :package ,package
                             :export-from ,(uiop:ensure-list export-from))))
      ((and error (not type-error)) ()
        (error "~@<~S, the ~S of ~S, is not of the form ~S.~:@>"
               args :record-autoloads (asdf:component-name system)
               '(pathname &key (process-arglist t) (process-docstring t)
                 package export-from))))))

(defun check-system-autoloads (system &key (errorp t))
  "In the AUTOLOAD-SYSTEM SYSTEM, check that there is a
  [:RECORD-AUTOLOADS][ system-record-autoloads] and the file generated
  by RECORD-SYSTEM-AUTOLOADS is up-to-date. If ERRORP, then signal an
  error if it is not or the file cannot be read.

  This compares the current AUTOLOADS to those in the file with EQUAL
  and is thus sensitive to the order of definitions.

  This function is called automatically by ASDF:TEST-OP on a
  AUTOLOAD-SYSTEM method if SYSTEM-TEST-AUTOLOADS."
  (let ((system (asdf:find-system system)))
    (check-type system autoload-system)
    (when (system-record-autoloads system)
      (multiple-value-bind (pathname args) (system-record-autoloads* system)
        (destructuring-bind (&key (process-arglist t) (process-docstring t)
                             package export-from)
            args
          (flet ((fail (control &rest args)
                   (if errorp
                       (error "~@<In system ~S, ~?.~:@>"
                              (asdf:component-name system)
                              control args)
                       (return-from check-system-autoloads nil))))
            (let ((pathname (asdf:system-relative-pathname system pathname)))
              (unless (uiop:file-exists-p pathname)
                (fail "~A file ~S is missing." :record-autoloads pathname))
              (let ((recorded-forms
                      (let ((*package* (if package
                                           (find-package-or-error package)
                                           *package*)))
                        (if errorp
                            (uiop:read-file-forms pathname)
                            (handler-case
                                (uiop:read-file-forms pathname)
                              (error (e)
                                (fail "reading file ~S failed with ~A."
                                      pathname e))))))
                    (current-forms (autoloads
                                    system :process-arglist process-arglist
                                    :process-docstring process-docstring
                                    :export-from export-from)))
                (when package
                  (let ((expected `(in-package
                                    ,(safe-package-designator package))))
                    (unless (equal (pop recorded-forms) expected)
                      (fail "the expected ~S form is not found." expected))))
                (loop for recorded-form in recorded-forms
                      for current-form in current-forms
                      do (unless (equal recorded-form current-form)
                           (fail "recorded and current forms differ.~%~
                                  Recorded form:~%  ~S~%~%Current form:~%  ~S"
                                 recorded-form current-form)))
                (unless (= (length recorded-forms) (length current-forms))
                  (fail "number of recorded (~S) and current forms (~S) differ."
                        (length recorded-forms) (length current-forms)))
                t))))))))

(defmethod asdf:perform ((op asdf:test-op) (system autoload-system))
  (when (system-test-autoloads system)
    (check-system-autoloads system)))
