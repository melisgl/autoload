(in-package :autoload)

(defsection @basics (:title "Basics")
  (@autoload glossary-term)
  (@loaddef glossary-term)
  (@auto glossary-term)
  (@loading-systems section)
  (@conditions section)
  (@functions section)
  (@classes section)
  (@variables section)
  (@packages section))

(define-glossary-term @autoload (:title "autoload")
  "An autoload definition defines a stub that, when used, triggers
  loading of an ASDF:SYSTEM. See AUTOLOAD and AUTOLOAD-CLASS.")

(define-glossary-term @loaddef (:title "loaddef")
  "A loaddef is either an @AUTOLOAD or some other Lisp form that
  foreshadows a definition without setting up autoloading of an
  ASDF:SYSTEM. See DEFVAR/AUTO and DEFPACKAGE/AUTO.")

(define-glossary-term @auto (:title "auto")
  "An auto definition, such as DEFUN/AUTO, DEFGENERIC/AUTO,
  DEFCLASS/AUTO, DEFPACKAGE/AUTO, marks the definition for
  @AUTOMATIC-LOADDEFS and signals an AUTOLOAD-WARNING if there was no
  corresponding @LOADDEF.")


(defsection @loading-systems (:title "Loading Systems")
  """[autoload-system-for function][docstring]""")

;;; The AUTOLOAD-SYSTEM in which the current file is being compiled or
;;; loaded
(defvar *autoload-system* nil)

(defvar *test-load-system* nil)

(defun autoload-system-for (system-name name kind)
  "When an @AUTOLOAD definition is used, it triggers the loading of
  ASDF:SYSTEMs. Unlike normal ASDF dependencies (declared in
  :DEPENDS-ON), autoload dependencies
  (may be declared in @AUTO-DEPENDS-ON) are allowed to be circular.
  The rules for loading are as follows.

  1. It is an AUTOLOAD-ERROR if loading is triggered during [compile
     time][clhs] or during a LOAD of either a [source file][clhs] or a
     [compiled file][clhs]. This is to prevent infinite autoload
     recursion.

  2. It is an AUTOLOAD-ERROR if the system does not [exist][
     asdf:find-system].

  3. The system is loaded under WITH-COMPILATION-UNIT :OVERRIDE T and
     WITH-STANDARD-IO-SYNTAX but with *PRINT-READABLY* NIL. Other
     non-portable measures may be taken to standardize the dynamic
     environment. Errors signalled during the load are not handled or
     resignalled by the Autoload library.

  4. It is an AUTOLOAD-ERROR if the definition established by the
     @AUTOLOAD is not redefined as a non-autoload definition or
     deleted by the loaded system.

       For AUTOLOAD, this means that the autoload function stub must
       be redefined as a normal function (e.g. by DEFUN, DEFUN/AUTO)
       or made FMAKUNBOUND. For AUTOLOAD-CLASS, the class stub must be
       redefined with DEFCLASS, DEFCLASS/AUTO or deleted with `(SETF
       (FIND-CLASS ...) NIL)`."
  (when (or *compile-file-pathname* *load-pathname*)
    (error 'autoload-error :name name :kind kind
           :system-name system-name :cause :during-compile-or-load))
  (when (and (null *test-load-system*)
             (null (asdf:find-system system-name nil)))
    (error 'autoload-error :name name :kind kind
           :system-name system-name :cause :system-not-found))
  (with-compilation-unit
      ;; Combined with :OVERRIDE T, this switches to the default policy.
      #+sbcl (:override t :policy '(optimize))
    #-sbcl (:override t)
    (with-standard-io-syntax
      (let ((*print-readably* nil)
            ;; If we are compiling or loading through ASDF, and
            ;; SYSTEM-NAME does not inherit from AUTOLOAD-SYSTEM or
            ;; has a :DEFAULT-COMPONENT-CLASS that does not inherit
            ;; from AUTOLOAD-CL-SOURCE-FILE, then prevent the current
            ;; *AUTOLOAD-SYSTEM* from leaking.
            (*autoload-system* nil))
        (without-asdf-session
          (if *test-load-system*
              (funcall *test-load-system* system-name)
              (asdf:load-system system-name))))))
  (when (autoloadp name kind)
    (error 'autoload-error :name name :kind kind
           :system-name system-name :cause :not-resolved)))

(defun autoloadp (name kind)
  (case kind
    ((:function) (autoload-fbound-p name))
    ((:class) (autoload-class-p name))
    (t (eq (state name kind) :declared))))

(defun check-loaddef (name kind &optional system-name)
  (when *autoload-system*
    (when system-name
      (let ((system-name (asdf:coerce-name system-name))
            (deps (system-auto-depends-on *autoload-system*)))
        (unless (find system-name deps :test #'equal)
          (signal-autoload-warning
           "~@<~S, the system to be autoloaded for ~A ~S, is ~
           not among ~S, the ~S of ~S.~:@>"
           system-name kind name deps 'system-auto-depends-on
           (asdf:component-name *autoload-system*)))))
    (maybe-gather-unresolved-loaddef name kind)))


(defsection @conditions (:title "Conditions")
  (autoload-error condition)
  (autoload-warning condition))

(define-condition autoload-warning (simple-warning)
  ()
  (:documentation "See AUTOLOAD, @AUTOs and @AUTO-DEPENDS-ON for when
  this is signalled."))

(defun signal-autoload-warning (format-control &rest format-args)
  (warn 'autoload-warning :format-control format-control
        :format-arguments format-args))

(defvar *suppress-missing-loaddef-warnings* nil)

(defun maybe-signal-missing-loaddef (name kind)
  (unless (state name kind)
    (unless *suppress-missing-loaddef-warnings*
      (signal-autoload-warning "~@<Missing loaddef for autoloaded ~A ~S.~:@>"
                               kind name))))

(define-condition autoload-error (error)
  ((name
    :initarg :name
    :reader autoload-error-name)
   (kind
    :initarg :kind
    :reader autoload-error-kind)
   (system-name
    :initarg :system-name
    :reader autoload-error-system-name)
   (cause
    :initarg :cause
    :initform nil
    :reader autoload-error-cause))
  (:report (lambda (condition stream)
             (let ((name (autoload-error-name condition))
                   (kind (autoload-error-kind condition))
                   (system-name (autoload-error-system-name condition))
                   (cause (autoload-error-cause condition)))
               (cond
                 ((eq cause :during-compile-or-load)
                  (format stream "~@<Attempted to load ASDF:SYSTEM ~S ~
                          for ~A ~S during ~S or ~S. See ~S.~:@>"
                          system-name kind name
                          'compile-file 'load '@loading-systems))
                 ((eq cause :system-not-found)
                  (format stream "~@<Could not find ASDF:SYSTEM ~S for ~
                          autoloaded ~A ~S. It may not be installed. ~
                          See ~S.~:@>"
                          system-name kind name 'autodeps))
                 ((eq cause :not-resolved)
                  (format stream "~@<Autoloaded ~A ~S was not ~
                          resolved by the ~S ASDF:SYSTEM.~:@>"
                          kind name system-name))
                 (t
                  (format stream "~@<Autoload failure for ~A ~S in ~
                          ASDF:SYSTEM ~S.~:@>"
                          kind name system-name))))))
  (:documentation "Signalled for some failures during @LOADING-SYSTEMS."))


;;;; Machinery for associating autoload stubs with function names,
;;;; including [setf function names][clhs], and for recording the
;;;; state of variable definitions.

(declaim (inline kind-to-indicator))

;;; Translate KIND to a package-internal variable, which we use as an
;;; indicator on SYMBOL-PLISTs.
(defun kind-to-indicator (kind)
  (ecase kind
    ((:function) '%autoload-function)
    ((:class) '%autoload-class)
    ((:defvar) '%autoload-variable)))

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
  (multiple-value-bind (name setf*) (unpack-function-name name)
    (setf (getf (get name (kind-to-indicator kind)) setf*)
          fn)))

(defsetf state set-state)


(defsection @functions (:title "Functions")
  (autoload macro)
  (autoload-fbound-p function)
  (defun/auto macro)
  (defgeneric/auto macro))

(defmacro autoload (name system-name &key (arglist nil arglistp) docstring)
  "Define a stub function with NAME that loads SYSTEM-NAME, expecting
  it to redefine the function, and then calls the newly loaded
  definition. Return NAME. The arguments are not evaluated. If NAME
  has an FDEFINITION and it is not AUTOLOAD-FBOUND-P, then do
  nothing and return NIL.

  The stub first [loads SYSTEM-NAME][@loading-systems], then it APPLYs
  the function NAME to the arguments originally provided to the stub.

  The stub is not defined at [compile time][clhs], which matches the
  required semantics of DEFUN. NAME is DECLAIMed with FTYPE FUNCTION
  and NOTINLINE.

  - ARGLIST will be installed as the stub's arglist if specified and
    it's supported on the platform (currently only SBCL). If ARGLIST
    is a string, the effective value of ARGLIST is read from it. If
    the read fails, an AUTOLOAD-WARNING is signalled and processing
    continues as if ARGLIST had not been provided.

      Arglists are for interactive purposes only. For example, they
      are shown by @SLIME-AUTODOC and returned by DREF:ARGLIST.

  - DOCSTRING, if non-NIL, will be the stub's docstring. If NIL, then
    a generic docstring that says what system it autoloads will be
    used.

  When AUTOLOAD is macroexpanded during the compilation or loading of
  an AUTOLOAD-SYSTEM, it signals an AUTOLOAD-WARNING if SYSTEM-NAME is
  not among those declared in @AUTO-DEPENDS-ON."
  (declare (ignorable arglist))
  (check-loaddef name :function system-name)
  `(progn
     (declaim
      ;; This is mainly to prevent undefined function compiler
      ;; warnings about NAME. A normal DEFUN takes care of this at
      ;; compile time, but the DEFUN below is not a [top level
      ;; form][clhs].
      ;;
      ;; Also, this works around a CMUCL bug that results in "Function
      ;; with declared result type NIL returned" errors when the real
      ;; function definition returns.
      (ftype function ,name)
      ;; And this is needed because we are actively redefining the
      ;; function.
      (notinline ,name))
     (when (or (null (fdefinition* ',name))
               (autoload-fbound-p ',name))
       (defun ,name (&rest args)
         ,(or docstring
              (let ((*package* (find-package :keyword)))
                (format nil "~S in the ~A ASDF:SYSTEM."
                        'autoload (%escape-markdown system-name))))
         (autoload-system-for ',system-name ',name :function)
         ;; Make sure that the function redefined by ASDF:LOAD-SYSTEM
         ;; is invoked and not this stub, which could be the case
         ;; without the FDEFINITION call.
         (apply (fdefinition ',name) args))
       (after-function-autoload-definition ',name ',arglistp ',arglist)
       ',name)))

(defun after-function-autoload-definition (name arglistp arglist)
  (declare (ignorable arglistp arglist))
  (setf (state name :function) (fdefinition* name))
  #+sbcl
  (when arglistp
    (etypecase arglist
      (cons
       (setf (sb-c::%fun-lambda-list (fdefinition* name)) arglist))
      (string
       (multiple-value-bind (sexp successp)
           (read-from-string-or-warn arglist 'autoload :arglist)
         (when successp
           (setf (sb-c::%fun-lambda-list (fdefinition* name)) sexp)))))))

(defun read-from-string-or-warn (string definer definer-arg)
  (check-type string string)
  (multiple-value-bind (sexp error)
      (ignore-errors (values (read-from-string string)))
    (cond (error
           (signal-autoload-warning "~@<~S ~S ~S could not be read: ~_~A~:@>"
                                    definer definer-arg string error)
           (values nil nil))
          (t
           (values sexp t)))))

(defun autoload-fbound-p (name)
  "See if NAME's function definition is an autoload stub established
  by AUTOLOAD."
  (check-type name (or symbol list))
  ;; This detects redefinitions by DEFUN too.
  (let ((fn (fdefinition* name)))
    (and fn (eq (state name :function) fn))))

;;; Even though ASDF:SYSTEM names rarely contain special Markdown
;;; characters, play nice with PAX and escape the names if
;;; MGL-PAX:ESCAPE-MARKDOWN is loaded.
(defun %escape-markdown (string)
  (let ((symbol (uiop:find-symbol* '#:escape-markdown '#:mgl-pax nil)))
    (if (and symbol (not (autoload-fbound-p symbol))
             (fdefinition* symbol))
        (funcall symbol string)
        string)))

(defun unpack-name-with-definer (name &optional default-definer)
  (if (and (consp name)
           (consp (cdr name))
           (null (cddr name))
           (symbolp (first name))
           (not (eq (first name) 'setf)))
      (values (first name) (second name))
      (values default-definer name)))

(defmacro defun/auto (name lambda-list &body body)
  "Like DEFUN, but mark the function for @AUTOMATIC-LOADDEFS and
  silence redefinition warnings. See EXTRACT-LOADDEFS for the
  corresponding @LOADDEF.

  Also, warn if NAME has never been AUTOLOAD-FBOUND-P.

  NAME may be of the form (DEFINER NAME). In that case, instead of
  DEFUN, DEFINER is used."
  (multiple-value-bind (definer name) (unpack-name-with-definer name 'defun)
    (maybe-record-autoload-info 'defun/auto name lambda-list
                                (find-docstring-in-body body))
    `(progn
       (maybe-signal-missing-loaddef ',name :function)
       ;; We don't want to FMAKUNBOUND a generic function and lose its
       ;; methods.
       (when (autoload-fbound-p ',name)
         ;; This prevents redefinition warnings and allows DEFINER to
         ;; be a DEFGENERIC without running into an error when trying
         ;; to redefine a DEFUN (the autoload stub).
         (fmakunbound ',name))
       (,definer ,name ,lambda-list ,@body)
       (setf (state ',name :function) :resolved)
       ',name)))

(defmacro defgeneric/auto (name lambda-list &body body)
  "A shorthand for `(` DEFUN/AUTO `(DEFGENERIC NAME) ...)`."
  `(defun/auto (defgeneric ,name) ,lambda-list ,@body))

(defun defun/auto-info-to-loaddefs
    (system-name info process-arglist process-docstring)
  "- For function definitions such as DEFUN/AUTO, an AUTOLOAD @LOADDEF
  is emitted.

      If PROCESS-ARGLIST is T, then the autoload forms will pass the
      ARGLIST argument of the corresponding DEFUN/AUTO to AUTOLOAD. If
      it is NIL, then ARGLIST will not be passed to AUTOLOAD."
  (destructuring-bind (name lambda-list docstring) info
    `((autoload ,name ,system-name
                ,@(when process-arglist
                    `(:arglist ,(prin1-to-string* lambda-list)))
                ,@(let ((docstring
                          ;; Prefer the current one.
                          (or (documentation name 'function)
                              docstring)))
                    (when (and process-docstring docstring)
                      `(:docstring ,docstring)))))))


(defsection @classes (:title "Classes")
  (autoload-class macro)
  (autoload-class-p function)
  (defclass/auto macro))

(defmacro autoload-class (class-name system-name &key docstring)
  "Define a dummy class with CLASS-NAME and arrange for SYSTEM-NAME to
  be [loaded][ @loading-systems] when it or any of its subclasses are
  [instantiated][ make-instance clhs]. Return the class object. The
  arguments are not evaluated. If CLASS-NAME [denotes][find-class
  clhs] a CLASS and it is not AUTOLOAD-CLASS-P, then do nothing and
  return NIL.

  - DOCSTRING, if non-NIL, will be the stub's docstring. If NIL, then
    a generic docstring that says what system it autoloads will be
    used.

  The dummy class is defined at [compile time][clhs] too to
  approximate the semantics of DEFCLASS. The dummy class is a
  STANDARD-CLASS with no superclasses or slots. These are visible
  through introspection e.g. via CLOSER-MOP:CLASS-DIRECT-SUPERCLASSES.
  Introspection does not trigger autoloading.

  When AUTOLOAD-CLASS is macroexpanded during the compilation or
  loading of an AUTOLOAD-SYSTEM, it signals an AUTOLOAD-WARNING if
  SYSTEM-NAME is not among those declared in @AUTO-DEPENDS-ON.

  Note that INITIALIZE-INSTANCE :AROUND methods specialized on a
  subclass of CLASS-NAME may run twice in the context of the
  MAKE-INSTANCE that triggers autoloading."
  (check-loaddef class-name :class system-name)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (when (or (null (find-class ',class-name nil))
               (autoload-class-p ',class-name))
       (prog1
           (defclass ,class-name (%autoload-class)
             ()
             (:documentation
              ,(or docstring
                   (let ((*package* (find-package :keyword)))
                     (format nil "~S in the ~A ASDF:SYSTEM." 'autoload-class
                             (%escape-markdown system-name))))))
         (setf (get ',class-name '%autoload-system) ',system-name)
         (setf (state ',class-name :class) (find-class ',class-name))))))

(defclass %autoload-class () ())

(defmethod initialize-instance :around ((instance %autoload-class)
                                        &rest initargs
                                        &key &allow-other-keys)
  (let* ((cpl (closer-mop:class-precedence-list (class-of instance)))
         (stub-classes (remove-if-not #'autoload-class-p cpl)))
    (cond (stub-classes
           (dolist (stub-class stub-classes)
             (let* ((stub-name (class-name stub-class))
                    (system-name (get stub-name '%autoload-system)))
               (autoload-system-for system-name stub-name :class)))
           ;; Instead of CALL-NEXT-METHOD, invoke INITIALIZE-INSTANCE
           ;; again to recompute the effective methods.
           (apply #'initialize-instance instance initargs))
          (t
           ;; There are no stubs, so the :AROUND method must have been
           ;; reentered after the class was already redefined. This
           ;; happens on ECL, CLISP and ABCL.
           (call-next-method)))))

(defun autoload-class-p (class-designator)
  "See if the class denoted by CLASS-DESIGNATOR was declared as an
  AUTOLOAD-CLASS and was not redefined or deleted since. Subclasses do
  not inherit this property."
  (let ((class (if (symbolp class-designator)
                   (find-class class-designator nil)
                   class-designator)))
    (when (and (typep class 'class)
               ;; It can be a different class object if there was an
               ;; intervening (SETF (FIND-CLASS ...) NIL).
               (eq (state (class-name class) :class) class))
      ;; The class object is unchanged, but it may not be the stub.
      (let ((supers (closer-mop:class-direct-superclasses class)))
        (and (= (length supers) 1)
             (eq (class-name (first supers)) '%autoload-class))))))

(defmacro defclass/auto (name direct-superclasses direct-slots &rest options)
  "Like DEFCLASS, but mark the class for @AUTOMATIC-LOADDEFS. See
  EXTRACT-LOADDEFS for the corresponding @LOADDEF.

  Also, warn if NAME has never been AUTOLOAD-CLASS-P.

  NAME may be of the form (DEFINER NAME). In that case, instead of
  DEFCLASS, DEFINER is used."
  (multiple-value-bind (definer name) (unpack-name-with-definer name 'defclass)
    (maybe-record-autoload-info 'defclass/auto name
                                (find-docstring-in-body options))
    `(progn
       (maybe-signal-missing-loaddef ',name :class)
       (,definer ,name ,direct-superclasses
                 ,direct-slots
                 ,@options)
       (setf (state ',name :class) :resolved))))

(defun defclass/auto-info-to-loaddefs
    (system-name info process-arglist process-docstring)
   "- For class definitions such as DEFCLASS/AUTO, an AUTOLOAD-CLASS
  @LOADDEF is emitted."
  (declare (ignore process-arglist))
  (destructuring-bind (name docstring) info
    `((autoload-class ,name ,system-name
                      ,@(let ((docstring
                                (or (documentation name 'type)
                                    docstring)))
                          (when (and process-docstring docstring)
                            `(:docstring ,docstring)))))))


(defsection @variables (:title "Variables")
  (defvar/auto macro))

;;; Be wary of changing this: although not exported, it is a loaddef.
(defmacro foreshadow-defvar (var &key (init nil initp) docstring)
  (check-loaddef var :defvar)
  `(progn
     (defvar ,var
       ,@(when initp
           `(,init)))
     ,@(when docstring
         `((unless (eq (state ',var :defvar) :resolved)
             (setf (documentation ',var 'variable) ,docstring))))
     (unless (state ',var :defvar)
       (setf (state ',var :defvar) :declared))))

(defmacro defvar/auto (var &optional (val nil valp) doc)
  "Like DEFVAR, but mark the variable for @AUTOMATIC-LOADDEFS. See
  EXTRACT-LOADDEFS for the corresponding @LOADDEF.

  Also, this works with the _global_ binding on Lisps that support
  it (currently Allegro, CCL, ECL, SBCL). This is to handle the case
  when a system that uses DEFVAR with a default value is autoloaded
  while that variable is locally bound:

  ```cl-transcript
  ;; Some base system only foreshadows *X*.
  (declaim (special *x*))
  (let ((*x* 1))
    ;; Imagine that the system that defines *X* is autoloaded here.
    (defvar/auto *x* 2)
    *x*)
  => 1
  ```

  In case the global binding has been set between the [corresponding
  loaddef][ extract-loaddefs] and the first evaluation of this form,
  VAL is evaluated for side effect.

  DEFVAR/AUTO warns if VAR does not have a loaddef in
  @AUTO-LOADDEFS.

  VAR may be of the form (DEFINER VAR). In that case, instead of
  DEFVAR, DEFINER is used. Note that DEFPARAMETER is not a suitable
  DEFINER, as it doesn't follow DEFVAR semantics."
  (multiple-value-bind (definer var) (unpack-name-with-definer var 'defvar)
    (maybe-record-autoload-info 'defvar/auto var val valp doc)
    `(progn
       (maybe-signal-missing-loaddef ',var :defvar)
       (,definer ,var)
       ;; Only evaluate VAL if necessary to mimic the semantics of
       ;; DEFVAR, and evaluate VAL for side effect if necessary.
       ,@(when valp
           `((cond ((not (symbol-globally-boundp ',var))
                    (setf (symbol-global-value ',var) ,val))
                   ((eq (state ',var :defvar) :declared)
                    ,val))))
       ,@(when doc
           `((setf (documentation ',var 'variable) ,doc)))
       (setf (state ',var :defvar) :resolved)
       ',var)))

(defun defvar/auto-info-to-loaddefs
    (system-name info process-arglist process-docstring)
  "- For DEFVAR/AUTO, the emitted @LOADDEF declaims the variable
  special and maybe sets its initial value and docstring.

      If the initial value form in DEFVAR/AUTO is detected as a simple
      constant form, then it is evaluated and its value is assigned to
      the variable as in DEFVAR. Simple constant forms are strings,
      numbers, characters, keywords, constants in the CL package, and
      QUOTEd nested lists containing any of the previous or any symbol
      from the `CL` package."
  (declare (ignore system-name process-arglist))
  (destructuring-bind (name val-form val-form-p docstring) info
    `((foreshadow-defvar
       ,name
       ,@(when (and val-form-p
                    ;; If VAL-FORM has no dependencies, then
                    ;; initialize early. Alternatively, we could save
                    ;; VAL-FORM as a string and have FORESHADOW-DEFVAR
                    ;; try to read and execute it, giving up on any
                    ;; error, but that could compute the wrong value.
                    (simple-constant-form-p val-form))
           `(:init ,val-form))
       ,@(let ((docstring
                 (or (documentation name 'variable)
                     docstring)))
           (when (and process-docstring docstring)
             `(:docstring ,docstring)))))))


(defsection @packages (:title "Packages")
  (defpackage/auto macro))

(defmacro defpackage/auto (name &rest options)
  "Like DEFPACKAGE, but mark the package for @AUTOMATIC-LOADDEFS and
  extend the existing definition additively. See EXTRACT-LOADDEFS for
  the corresponding @LOADDEFs.

  The additivity means that instead of replacing the package
  definition or signalling errors on redefinition, it expands into
  individual package-altering operations such as SHADOW, USE-PACKAGE
  and EXPORT. This allows the package state to be built incrementally,
  but the `(DEFINER NAME)` syntax is not supported. DEFPACKAGE/AUTO
  may be used on the same package multiple times.

  In addition, DEFPACKAGE/AUTO deviates from DEFPACKAGE in the
  following ways.

  - The default :USE list is empty.

  - :SIZE is not supported.

  - Implementation-specific extensions such as :LOCAL-NICKNAMES are
    not supported. Use `ADD-PACKAGE-LOCAL-NICKNAME` after the
    DEFPACKAGE/AUTO.

  Alternatively, one may use, for example, DEFPACKAGE or
  UIOP:DEFINE-PACKAGE and arrange for @AUTOMATIC-LOADDEFS for the
  package by listing it in :PACKAGES of @AUTO-LOADDEFS."
  (check-defpackage-options options)
  (let ((nicknames (filter-options :nicknames options :append))
        (shadows (filter-options :shadow options :append))
        (shadowing-imports (filter-options :shadowing-import-from options
                                           :collect))
        (use (filter-options :use options :append))
        (imports (filter-options :import-from options :collect))
        (interns (filter-options :intern options :append))
        (exports (filter-options :export options :append))
        (doc (filter-options :documentation options :single))
        (pkg-name (string name)))
    (maybe-record-autoload-info 'defpackage/auto pkg-name)
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (ensure-package-names ,pkg-name ',(mapcar #'string nicknames))
       ,@(when shadows
           `((shadow ',(mapcar #'string shadows) ,pkg-name)))
       ,@(loop for (pkg . syms) in shadowing-imports
               collect `(shadowing-import
                         (find-symbols-or-error ',(mapcar #'string syms)
                                                ,(string pkg))
                         ,pkg-name))
       ,@(when use
           `((use-package ',(mapcar #'string use) ,pkg-name)))
       ,@(loop for (pkg . syms) in imports
               collect `(import (find-symbols-or-error ',(mapcar #'string syms)
                                                       ,(string pkg))
                                ,pkg-name))
       ,@(when interns
           `((mapc (lambda (s) (intern s ,pkg-name))
                   ',(mapcar #'string interns))))
       ,@(when exports
           `((export (mapcar (lambda (s) (intern s ,pkg-name))
                             ',(mapcar #'string exports))
                     ,pkg-name)))
       ,@(when doc
           `((setf (documentation (find-package ,pkg-name) t) ,doc)))
       (find-package ,pkg-name))))

(defun check-defpackage-options (options)
  (loop for option in options
        unless (and (listp option)
                    (member (first option)
                            '(:nicknames :shadow :shadowing-import-from
                              :use :import-from :intern :export
                              :documentation)))
          do (error "~@<Unexpected option ~S in ~S.~:@>"
                    option 'defpackage/auto)))

(defun filter-options (name options mode)
  (ecase mode
    (:append (loop for (opt . args) in options
                   when (eq opt name)
                     append args))
    (:collect (loop for (opt . args) in options
                    when (eq opt name)
                      collect args))
    (:single (let ((matches (loop for (opt . args) in options
                                  when (eq opt name)
                                    collect (car args))))
               (when (rest matches)
                 (error "The ~S option can only occur once." name))
               (first matches)))))

(defun find-symbols-or-error (symbol-names package-name)
  (let ((package (find-package-or-error package-name)))
    (mapcar (lambda (name)
              (multiple-value-bind (symbol status) (find-symbol name package)
                (unless status
                  (error "~@<Symbol ~S not found in package ~S.~:@>"
                         name package-name))
                symbol))
            symbol-names)))

(defun generate-package-loaddefs (package-designators
                                  &key (process-docstring t))
  "- For DEFPACKAGE/AUTO and the provided PACKAGES,
  individual package-altering @LOADDEFs are emitted.

      As in the expansion of DEFPACKAGE/AUTO itself, these
      operations are additive. To handle circular dependencies, first
      all packages are created, then their state is reconstructed in
      phases following [DEFPACKAGE][clhs].

      Any reference to non-existent packages (e.g. in :USE) or symbols
      in non-existent packages (e.g. :IMPORT-FROM) is silently
      skipped."
  (let ((packages (sort (delete-duplicates (mapcar #'find-package-or-error
                                                   package-designators))
                        #'string< :key #'package-name))
        ;; We create the packages first, in case their :USEs are
        ;; circular. The phases follow the order specified in
        ;; [DEFPACKAGE][clhs].
        (phase-1-create nil)
        (phase-2-shadow nil)
        (phase-3-use nil)
        (phase-4-import nil)
        (phase-5-export nil))
    (dolist (pkg packages)
      (let* ((pkg-name (package-name pkg))
             (nicknames (package-nicknames pkg))
             (shadows nil)
             (shadowing-imports nil)
             (use-list (mapcar #'package-name (package-use-list pkg)))
             (imports nil)
             (exports nil))
        ;; Split PACKAGE-SHADOWING-SYMBOLS into SHADOWs and
        ;; SHADOWING-IMPORTs
        (dolist (sym (package-shadowing-symbols pkg))
          (if (or (eql (symbol-package sym) pkg)
                  ;; UNINTERNed. Maybe it was a SHADOWING-IMPORT, but
                  ;; we can't tell.
                  (null (symbol-package sym)))
              (push (symbol-name sym) shadows)
              (push (package-and-symbol-name sym) shadowing-imports)))
        ;; Do all [accessible][clhs] symbols.
        (do-symbols (sym pkg)
          (multiple-value-bind (found-sym status)
              (find-symbol (symbol-name sym) pkg)
            (when (eq found-sym sym)
              ;; [External symbol][clhs]s are to be EXPORTed.
              (when (eq status :external)
                (push (symbol-name sym) exports))
              ;; Maybe add to IMPORTS
              (when (and
                     ;; [Present][clhs]
                     (or (eq status :internal) (eq status :external))
                     ;; Not UNINTERNed
                     (symbol-package sym)
                     ;; Home package is not this package.
                     (not (eql (symbol-package sym) pkg))
                     ;; SHADOWING-IMPORTs are already recorded.
                     (not (member sym (package-shadowing-symbols pkg))))
                (push (package-and-symbol-name sym) imports)))))
        (flet ((-> (name)
                 (canonical-name name))
               (->s (names)
                 ;; REMOVE-DUPLICATES because DO-SYMBOLS may visit
                 ;; symbols that are inherited from multiple packages
                 ;; multiple times and also due to
                 ;; https://gitlab.com/embeddable-common-lisp/ecl/-/work_items/827.
                 (remove-duplicates
                  (sort (mapcar #'canonical-name names) #'string<)
                  :test #'equal))
               (->s* (package-and-name-list)
                 (remove-duplicates
                  (sort (mapcar (lambda (package-and-name)
                                  (destructuring-bind (package . name)
                                      package-and-name
                                    (cons (canonical-name package)
                                          (canonical-name name))))
                                package-and-name-list)
                        (lambda (cons1 cons2)
                          (or (string< (car cons1) (car cons2))
                              (and (string= (car cons1) (car cons2))
                                   (string< (cdr cons1) (cdr cons2))))))
                  :test #'equal)))
          (push `(ensure-package-names ,(-> pkg-name)
                                       ,(maybe-quote (->s nicknames)))
                phase-1-create)
          (let ((doc (documentation (find-package pkg-name) t)))
            (when (and doc process-docstring)
              (push `(set-package-documentation ,(-> pkg-name) ,doc)
                    phase-1-create)))
          (when shadows
            (push `(shadow* ',(->s shadows) ,(-> pkg-name)) phase-2-shadow))
          (when shadowing-imports
            (push `(shadowing-import* ',(->s* shadowing-imports)
                                      ,(-> pkg-name))
                  phase-2-shadow))
          (when use-list
            (push `(use-package* ',(->s use-list) ,(-> pkg-name))
                  phase-3-use))
          (when imports
            (push `(import* ',(->s* imports) ,(-> pkg-name))
                  phase-4-import))
          (when exports
            ;; If a USE-PACKAGE, SHADOWING-IMPORT or IMPORT was
            ;; skipped because a package was missing, then INTERN
            ;; makes the symbol present, which will cause a package
            ;; conflict in any later USE-PACKAGE, SHADOWING-IMPORT or
            ;; IMPORT that tries to make another symbol with the same
            ;; name accessible.
            (push `(export* ',(->s exports) ,(-> pkg-name))
                  phase-5-export)))))
    (when (or phase-1-create phase-2-shadow phase-3-use phase-4-import
              phase-5-export)
      `(,@(nreverse phase-1-create)
        ,@(nreverse phase-2-shadow)
        ,@(nreverse phase-3-use)
        ,@(nreverse phase-4-import)
        ,@(nreverse phase-5-export)))))

(defun maybe-quote (object)
  (if object
      `(quote ,object)
      nil))

(defun modern-mode-p ()
  #.(string= (uiop:standard-case-symbol-name "xxx") "xxx"))

(defun canonical-name (name)
  (if (and (not (modern-mode-p))
           (string= (string-upcase name) name))
      (string-downcase name)
      name))

(defun native-name (name)
  (if (and (not (modern-mode-p))
           (string= (string-downcase name) name))
      (string-upcase name)
      name))

(defun package-and-symbol-name (symbol)
  (cons (canonical-name (package-name (symbol-package symbol)))
        (canonical-name (symbol-name symbol))))

(defun existing-packages (packages)
  (remove-if-not #'find-package
                 (mapcar #'native-name (uiop:ensure-list packages))))

(defun symbols/existing (package-and-name-list)
  (let ((symbols ()))
    (dolist (entry package-and-name-list)
      (destructuring-bind (symbol-package . symbol-name) entry
        (let ((p (find-package (native-name symbol-package))))
          (when p
            (push (intern (native-name symbol-name) p)
                  symbols)))))
    (reverse symbols)))

(defun %ensure-package-names (name nicknames)
  (let ((native (native-name name))
        (native-nicks (mapcar #'native-name nicknames)))
    (if (find-package native)
        (let ((old-name (package-name (find-package native))))
          (rename-package native native
                          (remove native
                                  (union (package-nicknames native)
                                         (cons old-name native-nicks)
                                         :test #'string=)
                                  :test #'string=)))
        (make-package native :nicknames native-nicks :use ()))))

(defun %shadow* (names package)
  (shadow (mapcar #'native-name names) (native-name package)))

(defun %shadowing-import/existing (package-and-name-list package)
  (shadowing-import (symbols/existing package-and-name-list)
                    (native-name package)))

(defun %use-package/existing (packages package)
  (use-package (existing-packages packages) (native-name package)))

(defun %import/existing (package-and-name-list package)
  (import (symbols/existing package-and-name-list) (native-name package)))

(defun %intern-and-export (names package)
  (let ((package (native-name package)))
    (export (mapcar (lambda (name)
                      (intern (native-name name) package))
                    names)
            package)))

;;; These are not exported, but they are loaddefs, so treat them as
;;; public.

(defmacro ensure-package-names (name nicknames)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%ensure-package-names ,name ,nicknames)))

(defmacro set-package-documentation (package-name doc)
  `(setf (documentation (find-package (native-name ,package-name)) t)
         ,doc))

(defmacro shadow* (names package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%shadow* ,names ,package)))

(defmacro shadowing-import* (package-and-name-list package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%shadowing-import/existing ,package-and-name-list ,package)))

(defmacro use-package* (packages package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%use-package/existing ,packages ,package)))

(defmacro import* (package-and-name-list package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%import/existing ,package-and-name-list ,package)))

(defmacro export* (names package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%intern-and-export ,names ,package)))


(defmacro with-record-loaddefs-restart (form &key (test t) on-restart)
  (let ((condition (gensym "condition")))
    `(restart-case
         ,form
       (record-loaddefs ()
         :test (lambda (,condition)
                 (declare (ignore ,condition))
                 ,test)
         :report (lambda (stream)
                   (format stream "Record system loaddefs."))
         ,on-restart))))


(defsection @asdf-integration (:title "ASDF Integration")
  (autoload-system class)
  (autoload-cl-source-file class)
  (system-auto-depends-on (reader autoload-system))
  (system-auto-loaddefs (reader autoload-system))
  (autodeps function)
  (@automatic-loaddefs section))

(defclass autoload-system (asdf:system)
  ((auto-depends-on
    :initarg :auto-depends-on
    :initform nil
    :reader system-auto-depends-on
    :documentation "This is the list of the names of systems that this
     system may autoload. The names are canonicalized with
     ASDF:COERCE-NAME. It is an AUTOLOAD-WARNING if an @AUTOLOAD
     refers to a system not listed here. This is also used by
     EXTRACT-LOADDEFS and affects the checks performed by the AUTOLOAD
     macro.")
   (auto-loaddefs
    :initform nil
    :initarg :auto-loaddefs
    :reader system-auto-loaddefs
    :documentation "When non-NIL, this specifies arguments for
    @AUTOMATIC-LOADDEFS. It may be a single pathname designator or a
    list of the form

        (loaddefs-file &key (process-arglist t) (process-docstring t)
                            packages (test t))

    - LOADDEFS-FILE designates the pathname where [RECORD-LOADDEFS][
      function] writes the [extracted loaddefs][ extract-loaddefs].
      The pathname is relative to ASDF:SYSTEM-SOURCE-DIRECTORY of
      SYSTEM and is OPENed with :IF-EXISTS :SUPERSEDE.

    - PROCESS-ARGLIST, PROCESS-DOCSTRING and [PACKAGES][pax:argument]
      are passed on by RECORD-LOADDEFS to EXTRACT-LOADDEFS.

    - If TEST, then CHECK-LOADDEFS is run by ASDF:TEST-SYSTEM.

    Conditions signalled while ASDF is compiling or loading the file
    given have a RECORD-LOADDEFS restart.")
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
    :auto-depends-on (\"dyndep\")
    :auto-loaddefs \"loaddefs.lisp\"
    :components ((:file \"package\")
                 (:file \"loaddefs\")
                 ...))
  ```

  With the above,

  - It is an error if an AUTOLOAD refers to a system other than
    `dyndep`.

  - `(`[RECORD-LOADDEFS][function] `\"my-system\")` will update
    `loaddefs.lisp`.

  - `(ASDF:TEST-SYSTEM \"my-system\")` [checks][ check-loaddefs] that
    `loaddefs.lisp` is up-to-date.

  If the package definitions are also generated with
  [RECORD-LOADDEFS][ function] (e.g. because there is a
  DEFPACKAGE/AUTO in `dyndep` or @AUTO-LOADDEFS specifies
  :PACKAGES), then we can do without the `package.lisp` file:

  ```
  (asdf:defsystem \"my-system\"
    :defsystem-depends-on (\"autoload\")
    :class \"autoload:autoload-system\"
    :auto-depends-on (\"dyndep\")
    :auto-loaddefs (\"loaddefs.lisp\" :packages #:my-pkg)
    :components ((:file \"loaddefs\")
                 ...))
  ```"))

(defmethod shared-initialize :after ((system autoload-system) slot-names
                                     &key &allow-other-keys)
  (declare (ignore slot-names))
  (setf (slot-value system 'auto-depends-on)
        (mapcar #'asdf:coerce-name (slot-value system 'auto-depends-on)))
  #+(or clisp ecl)
  (unless (slot-value system 'asdf::default-component-class)
    (setf (slot-value system 'asdf::default-component-class)
          'autoload-cl-source-file)))


(defclass autoload-cl-source-file (asdf:cl-source-file)
  ()
  (:documentation "The :DEFAULT-COMPONENT-CLASS of AUTOLOAD-SYSTEM.
@ASDF-INTEGRATION relies on source files belonging to this class. When
combining autoload with another ASDF extension that has its own
ASDF:CL-SOURCE-FILE subclass, define a new class that inherits from
both, and use that as :DEFAULT-COMPONENT-CLASS."))

(defmacro with-autoload-system ((autoload-cl-source-file) &body body)
  (let ((cl-file (gensym "CL-FILE"))
        (loaddefs-file-p (gensym "LOADDEFS-FILE-P")))
    `(let* ((,cl-file ,autoload-cl-source-file)
            (*autoload-system* (asdf:component-system ,cl-file))
            (,loaddefs-file-p (loaddefs-file-p ,cl-file)))
       (loop
         (with-record-loaddefs-restart
             (return (progn ,@body))
             :test ,loaddefs-file-p
             :on-restart (record-loaddefs *autoload-system*))))))

(defun loaddefs-file-p (autoload-cl-source-file)
  (declare (type autoload-cl-source-file autoload-cl-source-file))
  (let* ((f autoload-cl-source-file)
         (f-file (asdf:component-pathname f))
         (system (asdf:component-system f))
         (loaddefs-file (ignore-errors (split-system-auto-loaddefs system)))
         (loaddefs-file (when loaddefs-file
                           (asdf:system-relative-pathname system
                                                          loaddefs-file))))
    (declare (type autoload-system system))
    (uiop:pathname-equal f-file loaddefs-file)))

(defmethod asdf:perform :around ((op asdf:compile-op)
                                 (c autoload-cl-source-file))
  (with-autoload-system (c)
    (call-next-method)))

(defmethod asdf:perform :around ((op asdf:load-op)
                                 (c autoload-cl-source-file))
  (with-autoload-system (c)
    (call-next-method)))

(defmethod asdf:perform :around ((op asdf:load-source-op)
                                 (c autoload-cl-source-file))
  (with-autoload-system (c)
    (call-next-method)))


;;; ASDF:PERFORM is designed for side effects, and we can't just
;;; return stuff normally. LIST-AUTOLOADED-OP gathers systems here.
(defvar *listed-autodeps*)

(defclass list-autoloaded-op (asdf:sideway-operation)
  ())

(defmethod asdf:operation-done-p ((op list-autoloaded-op) (c asdf:component))
  nil)

(defmethod asdf:perform ((op list-autoloaded-op) (system autoload-system))
  (dolist (s (system-auto-depends-on system))
    (pushnew s *listed-autodeps* :test #'equal)))

(defmethod asdf:perform ((op list-autoloaded-op) (system asdf:system))
  nil)

(defun autodeps (system &key (cross-autoloaded t) installer)
  "Return the list of the names of systems that may be autoloaded by
  SYSTEM or any of its direct or indirect dependencies. This
  recursively visits systems in the dependency tree, traversing both
  normal (:DEPENDS-ON) and autoloaded (@AUTO-DEPENDS-ON) dependencies.
  It works even if SYSTEM is not an AUTOLOAD-SYSTEM.

  - CROSS-AUTOLOADED controls whether systems only reachable from
    SYSTEM via intermediate autoloaded dependencies are visited. Thus,
    if CROSS-AUTOLOADED is NIL, then the returned list is the first
    boundary of autoloaded systems.

  - If INSTALLER is non-NIL, it is called when an autoloaded system
    that is not installed (i.e. ASDF:FIND-SYSTEM fails) is visited.
    INSTALLER is passed a single argument, the name of the system to
    be installed. It may or may not install the system.

  If an autoloaded system is not installed (i.e. ASDF:FIND-SYSTEM
  fails, even after INSTALLER had a chance), then its dependencies are
  unknown and cannot be traversed. Note that autoloaded systems that
  are not installed are still visited and included in the returned
  list.

  The following example makes sure that all autoloaded dependencies
  (direct or indirect) of `my-system` are installed:

      (autodeps \"my-system\" :installer #'ql:quickload)"
  (let ((*listed-autodeps* ()))
    (without-asdf-session
      ;; This will visit all systems in the dependency tree of SYSTEM.
      (asdf:operate 'list-autoloaded-op system :force t)
      (when cross-autoloaded
        (loop with processed = ()
              for pending = (set-difference *listed-autodeps*
                                            processed :test #'equal)
              while pending
              do (dolist (s pending)
                   (when (and installer (null (asdf:find-system s nil)))
                     (funcall installer s))
                   (when (asdf:find-system s nil)
                     (asdf:operate 'list-autoloaded-op s :force t)))
                 (setq processed (append pending processed)))))
    (reverse *listed-autodeps*)))


(defsection @automatic-loaddefs (:title "Automatically Generating Loaddefs")
  (extract-loaddefs function)
  (write-loaddefs function)
  (record-loaddefs function)
  (check-loaddefs function)
  (record-loaddefs restart))

(defvar *gathering-unresolved-from-system* nil)
(defvar *gathered-unresolved-loaddefs*)

(defun maybe-gather-unresolved-loaddef (name kind)
  ;; We rely on CHECK-MANUAL-LOADDEFS having loaded the dependencies.
  ;; Thus everything should be resolved.
  (when (and *autoload-system*
             (eq *autoload-system* *gathering-unresolved-from-system*)
             (autoloadp name kind))
    ;; We are called from macros, which can be expanded multiple times.
    (pushnew `(,kind ,name) *gathered-unresolved-loaddefs*
             :test #'equal)))

(defvar *recording-from-system* nil)
(defvar *recorded-autoload-infos*)

(defmacro with-loaddefs-file-syntax (&body body)
  `(uiop:with-safe-io-syntax (:package :cl)
     (let ((*print-pretty* t)
           (*print-case* :downcase)
           (*print-right-margin* 78)
           (*print-miser-width* nil))
       ,@body)))

(defun prin1-to-string* (object)
  ;; We need to print the same string on all Lisp implementations for
  ;; the sake of the EQUAL comparison in CHECK-LOADDEFS.
  ;; *PRINT-PRETTY* NIL would be the easy way, but CLISP still prints
  ;; (QUOTE X) as 'X.
  (with-loaddefs-file-syntax
    (let ((*print-right-margin* most-positive-fixnum)
          (*print-miser-width* nil))
      (prin1-to-string object))))

(defun maybe-record-autoload-info (definer name &rest rest)
  ;; Do not record definitions from dependencies of autoloaded
  ;; systems.
  (when (and *recording-from-system*
             (eq *recording-from-system* *autoload-system*))
    ;; This is called from a macro, and macros are allowed to be
    ;; expanded multiple times.
    (pushnew (list* (asdf:component-name *autoload-system*) definer name rest)
             *recorded-autoload-infos*
             :test (lambda (new entry)
                     (declare (ignore new))
                     (and (eq (second entry) definer)
                          (equal (third entry) name))))))

(defun extract-loaddefs (system &key (process-arglist t) (process-docstring t)
                         packages)
  "Return a list of @LOADDEF forms that set up autoloading
  for definitions such as DEFUN/AUTO in @AUTO-DEPENDS-ON of
  SYSTEM.

  There is rarely a need to call this function directly, as
  [RECORD-LOADDEFS][ function] and CHECK-LOADDEFS provide
  @ASDF-INTEGRATION.

  Note that this is an expensive operation, as it loads or reloads the
  direct dependencies one by one with ASDF:LOAD-SYSTEM :FORCE T and
  records the association with the system and the autoloaded
  definitions such as DEFUN/AUTO.

  [defun/auto-info-to-loaddefs function][docstring]

  [defclass/auto-info-to-loaddefs function][docstring]

  [defvar/auto-info-to-loaddefs function][docstring]

  [generate-package-loaddefs function][docstring]

  - If PROCESS-DOCSTRING, then the docstrings extracted from @AUTO
    definitions will be associated with the definition.

  Note that if a function is not defined with DEFUN/AUTO, then
  EXTRACT-LOADDEFS will not detect it. For such functions, AUTOLOAD
  forms must be written manually. Similar considerations apply to
  variables and packages."
  (let* ((infos (without-asdf-session
                  (mapcan #'extract-autoload-infos
                          (system-auto-depends-on (asdf:find-system system)))))
         (package-infos (remove 'defpackage/auto infos
                                :test-not #'eq :key #'second))
         (other-infos (remove 'defpackage/auto infos
                              :test #'eq :key #'second)))
    (append
     ;; These are already ordered.
     (generate-package-loaddefs (union (mapcar #'third package-infos)
                                       (uiop:ensure-list packages))
                                :process-docstring process-docstring)
     (sort-loaddefs (mapcan (lambda (info)
                              (info-to-loaddefs info process-arglist
                                                process-docstring))
                            other-infos)))))

(defun sort-loaddefs (loaddefs)
  (mapcar #'car
          (sort (mapcar (lambda (loaddef)
                          (cons loaddef (prin1-to-string* loaddef)))
                        loaddefs)
                #'string< :key #'cdr)))

(defun write-loaddefs (loaddefs stream)
  "Write LOADDEFS to STREAM so they can be LOADed or included in an
ASDF:DEFSYSTEM."
  (with-loaddefs-file-syntax
    (format stream "~S~%~%" `(in-package :cl))
    (format stream "~{~S~%~^~%~}" loaddefs)))

(defun read-loaddefs-file (pathname)
  (with-loaddefs-file-syntax
    (uiop:read-file-forms pathname)))

(defun extract-autoload-infos (system)
  (let* ((system (asdf:find-system system))
         (*recording-from-system* system)
         (*recorded-autoload-infos* ())
         (asdf:*compile-file-warnings-behaviour* :ignore))
    (asdf:load-system system :force t)
    (reverse *recorded-autoload-infos*)))

(defun info-to-loaddefs (info process-arglist process-docstring)
  (let ((system-name (pop info))
        (definer (pop info)))
    (ecase definer
      ((defun/auto)
       (defun/auto-info-to-loaddefs system-name info
         process-arglist process-docstring))
      ((defclass/auto)
       (defclass/auto-info-to-loaddefs system-name info
         process-arglist process-docstring))
      ((defvar/auto)
       (defvar/auto-info-to-loaddefs system-name info
         process-arglist process-docstring)))))

(defun record-loaddefs (system)
  "EXTRACT-LOADDEFS from SYSTEM and WRITE-LOADDEFS. The arguments of
  these functions are taken from SYSTEM's @AUTO-LOADDEFS.

  As EXTRACT-LOADDEFS loads the direct autoloaded dependencies,
  compiler warnings (e.g. about undefined specials and functions) may
  occur that go away once the generated loaddefs are in place. The
  easiest way to trigger this is to call RECORD-LOADDEFS before these
  dependencies have been loaded. In this case, temporarily emptying
  the loaddefs file and fixing these warnings is recommended.

  RECORD-LOADDEFS may also be used as a [condition handler][clhs], in
  which case it invokes the RECORD-LOADDEFS restart."
  (when (or (null system) (typep system 'condition))
    (invoke-restart 'record-loaddefs)
    (return-from record-loaddefs))
  (let ((system (asdf:find-system system)))
    (check-type system autoload-system)
    (multiple-value-bind (pathname args) (split-system-auto-loaddefs system)
      (let ((pathname (asdf:system-relative-pathname system pathname))
            #+clisp (custom:*reopen-open-file* nil))
        (with-file-superseded (stream pathname)
          (with-loaddefs-file-syntax
            (format stream ";;;; This file was emptied by~%~
                            ;;;;~%~
                            ;;;;   ~S~%~
                            ;;;;~%~
                            ;;;; Recording is ongoing or has failed. ~
                                 Do not edit.~%~%"
                    `(record-loaddefs ,(asdf:component-name system)))))
        (with-file-superseded (stream pathname)
          (with-loaddefs-file-syntax
            (format stream ";;;; This file was generated by~%~
                            ;;;;~%~
                            ;;;;   ~S~%~
                            ;;;;~%~
                            ;;;; Do not edit.~%~%"
                    `(record-loaddefs ,(asdf:component-name system))))
          (let ((*suppress-missing-loaddef-warnings* t))
            (write-loaddefs (apply #'extract-loaddefs system args)
                            stream)))))))

(defun split-system-auto-loaddefs (system)
  (let ((args (uiop:ensure-list (system-auto-loaddefs system))))
    (handler-case
        (destructuring-bind (pathname &key (process-arglist t)
                             (process-docstring t) packages (test t))
            args
          (check-type pathname (or string pathname))
          (values pathname `(:process-arglist ,process-arglist
                             :process-docstring ,process-docstring
                             :packages ,packages)
                  test))
      ((and error (not type-error)) ()
        (error "~@<~S, the ~S of ~S, is not of the form ~S.~:@>"
               args :auto-loaddefs (asdf:component-name system)
               '(pathname &key (process-arglist t) (process-docstring t)
                 packages (test t)))))))

(defun system-test-loaddefs-p (system)
  (and (system-auto-loaddefs system)
       (nth-value 2 (split-system-auto-loaddefs system))))

(defun check-loaddefs (system &key (errorp t))
  "In the AUTOLOAD-SYSTEM SYSTEM, check that both recorded and manual
  autoload declarations are correct.

  - If there is an @AUTO-LOADDEFS, check that the file generated by
    [RECORD-LOADDEFS][ function] is up-to-date.

  - Check that all manual (non-generated) autoload declarations with
    AUTOLOADs in SYSTEM are resolved (the corresponding function or
    variable is defined) by loading @AUTO-DEPENDS-ON.

  If ERRORP, then signal an error if a check fails or the loaddefs
  file cannot be read. If @AUTO-LOADDEFS is specified, then the
  RECORD-LOADDEFS restart is provided.

  If ERRORP is NIL, then instead of signalling an error, return NIL.

  This function is called automatically by ASDF:TEST-OP on an
  AUTOLOAD-SYSTEM method if @AUTO-LOADDEFS has :TEST T."
  (let ((system (asdf:find-system system)))
    (check-type system autoload-system)
    (flet ((fail (provide-restart-p control &rest args)
             (if errorp
                 (with-record-loaddefs-restart
                     (progn
                       (cerror "Return NIL."
                               "~@<In system ~S, ~?~:@>"
                               (asdf:component-name system)
                               control args)
                       (return-from check-loaddefs nil))
                   :test (and provide-restart-p
                              (system-auto-loaddefs system))
                   :on-restart (progn
                                 (record-loaddefs system)
                                 (return-from check-loaddefs
                                   (check-loaddefs system :errorp errorp))))
                 (return-from check-loaddefs nil))))
      (check-recorded-loaddefs system #'fail)
      (check-manual-loaddefs system #'fail)
      t)))

(defun check-recorded-loaddefs (system fail)
  (when (system-auto-loaddefs system)
    (multiple-value-bind (pathname extract-args)
        (split-system-auto-loaddefs system)
      (let ((pathname (asdf:system-relative-pathname system pathname)))
        (unless (uiop:file-exists-p pathname)
          (funcall fail t "~A file ~S is missing." :auto-loaddefs pathname))
        (let ((recorded-forms
                (handler-case
                    (read-loaddefs-file pathname)
                  (error (e)
                    (funcall fail t "reading file ~S failed with ~A."
                             pathname e))))
              (current-forms (apply #'extract-loaddefs system extract-args)))
          (let ((expected '(in-package :cl)))
            (unless (equal (pop recorded-forms) expected)
              (funcall fail t "the expected ~S form is not found."
                       expected)))
          (loop for recorded-form in recorded-forms
                for current-form in current-forms
                do (unless (equal recorded-form current-form)
                     (funcall fail t "recorded and current loaddefs differ.~%~
                              Recorded form:~%  ~S~%~%Current form:~%  ~S"
                              recorded-form current-form)))
          (unless (= (length recorded-forms) (length current-forms))
            (funcall fail t
                     "number of recorded (~S) and current loaddefs (~S) differ."
                     (length recorded-forms) (length current-forms))))))))

;;; Since this is called only if CHECK-LOADDEFS succeeds, any
;;; unresolved autoload must be manual.
(defun check-manual-loaddefs (system fail)
  (without-asdf-session
    (map nil #'asdf:load-system (system-auto-depends-on system))
    (let ((unresolved (unresolved-loaddefs system)))
      (when unresolved
        (funcall fail nil
                 "the following manual loaddefs are unresolved: ~_~S."
                 unresolved)))))

(defun unresolved-loaddefs (system)
  (let ((*gathering-unresolved-from-system* system)
        (*gathered-unresolved-loaddefs* ()))
    (asdf:load-system system :force t)
    *gathered-unresolved-loaddefs*))

(defmethod asdf:perform ((op asdf:test-op) (system autoload-system))
  (when (system-test-loaddefs-p system)
    (check-loaddefs system)))
