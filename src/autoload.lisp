(in-package :autoload)

;;;; Machinery for associating autoload stubs with function names,
;;;; including [setf function names][clhs], and for recording the
;;;; state of variable definitions.

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


;;;; @BASICS

(define-condition autoload-warning (simple-warning)
  ()
  (:documentation "Signalled when inconsistencies are detected by e.g.
  [AUTOLOAD][macro] and DEFVAR/AUTOLOADED."))

(defun signal-autoload-warning (format-control &rest format-args)
  (warn 'autoload-warning :format-control format-control
        :format-arguments format-args))


;;;; @FUNCTIONS

(defmacro autoload (name asdf-system-name &key (arglist nil arglistp)
                    (docstring nil docstringp) (explicitp t))
  "Define a stub function with NAME to [load][asdf:load-system]
  ASDF-SYSTEM-NAME and return NAME. The arguments are not evaluated.
  If NAME has a [function definition][fdefinition clhs] and it is not
  FUNCTION-AUTOLOAD-P, then do nothing and return NIL.

  The stub is not defined at [compile time][clhs], which matches the
  required semantics of DEFUN. NAME is DECLAIMed with FTYPE FUNCTION
  and NOTINLINE.

  - ARGLIST will be installed as the stub's arglist if specified and
    it's supported on the platform (currently only SBCL). If ARGLIST
    is a string, then the effective value of ARGLIST is then read from
    it. If the read fails, an AUTOLOAD-WARNING is signalled and
    processing continues as if ARGLIST had not been provided.

      Arglists are for interactive purposes only. For example, they
      are shown by @SLIME-AUTODOC and returned by DREF:ARGLIST.

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

  - It is an AUTOLOAD-WARNING if NAME is redefined with another
    [AUTOLOAD][macro].

  - It is an AUTOLOAD-WARNING if the promise of EXPLICITP is broken,
    as it indicates confusion whether @GENERATING-AUTOLOADS should be
    done automatically or not.

  Also, see [SYSTEM-AUTOLOADED-SYSTEMS][ (reader autoload-system)] for
  further consistency checking."
  (declare (ignorable arglist))
  (check-function-autoload name asdf-system-name)
  `(progn
     (declaim
      ;; This is mainly to prevent undefined function compiler
      ;; warnings about NAME. A normal DEFUN takes care of this at
      ;; compile time, but the DEFUN below is not a [top level
      ;; form][clhs].
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
              (format nil "[AUTOLOADed][pax:macro] function in ~
                          the ~A ASDF:SYSTEM."
                      (%escape-markdown asdf-system-name)))
         (load-system-and-check-redefinition ',asdf-system-name ',name
                                             ',explicitp)
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
         (signal-autoload-warning
          "~@<Autoloaded function ~S was redefined ~
          with ~S in the ~S ASDF:SYSTEM.~:@>"
          name 'autoload asdf-system-name))
        ((functionp (state name :function))
         (when explicitp
           (signal-autoload-warning
            "~@<Autoloaded function ~S was redefined ~
            in the ~S ASDF:SYSTEM but not by ~S, ~S or ~S.~:@>"
            name asdf-system-name 'defun/autoloaded 'defgeneric/autoloaded
            'define-autoloaded-function)))
        (t
         (assert (eq (state name :function) :resolved))
         (unless explicitp
           (signal-autoload-warning
            "~@<Autoloaded function ~S was declared with ~S ~S but was ~
            redefined in the ~S ASDF:SYSTEM explicitly by ~S, ~S or ~S.~:@>"
            name :explicitp nil asdf-system-name 'defun/autoloaded
            'defgeneric/autoloaded 'define-autoloaded-function)))))

(defun function-autoload-p (name)
  "See if NAME's function definition is an autoloader function
   established by [AUTOLOAD][macro]."
  ;; This detects redefinitions by DEFUN too.
  (eq (state name :function) (fdefinition* name)))

(defmacro defun/autoloaded (name lambda-list &body body)
  "Like DEFUN, but mark the function for automatically
  @GENERATING-AUTOLOADS and silence redefinition warnings. Also, warn
  if NAME has never been FUNCTION-AUTOLOAD-P."
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

(defun defun/autoloaded-info-to-autoload-form
    (asdf-system-name info process-arglist process-docstring)
  (destructuring-bind (name lambda-list docstring) info
    `((autoload ,name ,asdf-system-name
                ,@(when process-arglist
                    `(:arglist ,(prin1-to-string* lambda-list)))
                ,@(let ((docstring
                          ;; Prefer the current one.
                          (or (documentation name 'function)
                              docstring)))
                    (when (and process-docstring docstring)
                      `(:docstring ,docstring)))))))

(defvar *suppress-has-not-been-declared-warnings* nil)

(defun before-autoloaded-function-definition (name)
  (unless (state name :function)
    (unless *suppress-has-not-been-declared-warnings*
      (signal-autoload-warning
       "~@<Defining ~S as an autoloaded function, ~
       but it has not been declared with ~S.~:@>"
       name 'autoload)))
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

(defmacro declare-variable-autoload (var &key (init nil initp) docstring)
  "Define VAR with DEFVAR and mark it as VARIABLE-AUTOLOAD-P.

  - Depending on whether INIT is specified, `(DEFVAR <VAR>
    <init>)` or `(DEFVAR <VAR>)` is executed.

  - If DOCSTRING is non-NIL, then the DOCUMENTATION of VAR as a
    VARIABLE is set to it.

  Note that on accessing VAR, nothing is autoloaded.
  DECLARE-VARIABLE-AUTOLOAD is solely to allow DEFVAR/AUTOLOADED to
  perform some checking."
  `(progn
     (defvar ,var
       ,@(when initp
           `(,init)))
     ,@(when docstring
         `((setf (documentation ',var 'variable) ,docstring)))
     (setf (state ',var :variable) :declared)))

(defun variable-autoload-p (name)
  "See if NAME has been declared with DECLARE-VARIABLE-AUTOLOAD and
  not defined with DEFVAR/AUTOLOADED since."
  (eq (state name :variable) :declared))

(defmacro defvar/autoloaded (var &optional (val nil valp) doc)
  "Like DEFVAR, but mark the variable for automatically
  @GENERATING-AUTOLOADS.

  Also, this works with the _global_ binding on Lisps that support
  it (currently Allegro, CCL, ECL, SBCL). This is to handle the case
  when a system that uses DEFVAR with a default value is autoloaded
  while that variable is locally bound:

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

(defun defvar/autoloaded-info-to-autoload-form
    (asdf-system-name info process-arglist process-docstring)
  (declare (ignore asdf-system-name process-arglist))
  (destructuring-bind (name val-form val-form-p docstring) info
    `((declare-variable-autoload ,name
          ,@(when (and val-form-p
                       ;; If VAL-FORM has no dependencies, then
                       ;; initialize early. Alternatively, we could
                       ;; save VAL-FORM as a string and have
                       ;; DECLARE-VARIABLE-AUTOLOAD try to read and
                       ;; execute it, giving up on any error, but that
                       ;; could compute the wrong value.
                       (simple-constant-form-p val-form))
              `(:init ,val-form))
        ,@(let ((docstring
                  (or (documentation name 'variable)
                      docstring)))
            (when (and process-docstring docstring)
              `(:docstring ,docstring)))))))

(defun before-autoloaded-variable-definition (name)
  (unless (state name :variable)
    (unless *suppress-has-not-been-declared-warnings*
      (signal-autoload-warning
       "~@<Defining ~S with ~S, but it has not been declared with ~S.~:@>"
       name 'defvar/autoloaded 'declare-variable-autoload))))

(defun after-autoloaded-variable-definition (name val valp doc)
  (when valp
    (unless (symbol-globally-boundp name)
      (setf (symbol-global-value name) val)))
  (when doc
    (setf (documentation name 'function) doc))
  (setf (state name :variable) :resolved))


;;;; @PACKAGES

(defmacro defpackage/autoloaded (name &rest options)
  "Like DEFPACKAGE, but mark the package for @GENERATING-AUTOLOADS
  automatically and extend the existing definition additively.

  The additivity means that instead of replacing the package
  definition or signaling errors on redefinition, it expands into
  individual package-altering operations such as SHADOW, USE-PACKAGE
  and EXPORT. This allows the package state to be built incrementally.
  DEFPACKAGE/AUTOLOADED may be used on the same package multiple
  times.

  In addition, DEFPACKAGE/AUTOLOADED deviates from DEFPACKAGE in the
  following ways.

  - The default :USE list is empty.

  - :SIZE is not supported.

  - Implementation-specific extensions such as :LOCAL-NICKNAMES are
    not supported. Use `ADD-PACKAGE-LOCAL-NICKNAMES` after the
    DEFPACKAGE/AUTOLOADED.

  Alternatively, one may use, for example, DEFPACKAGE or
  UIOP:DEFINE-PACKAGE and arrange for @GENERATING-AUTOLOADS for the
  package by listing it in :PACKAGES of
  [SYSTEM-RECORD-AUTOLOADS][ (reader autoload-system)]."
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
    (maybe-record-autoload-info `(defpackage/autoloaded ,pkg-name))
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

(defun generate-package-autoloads (package-designators
                                   &key (process-docstring t))
  (let ((packages (sort (delete-duplicates (mapcar #'find-package-or-error
                                                   package-designators))
                        #'string< :key #'package-name))
        ;; MAKE-PACKAGE forms for all packages. We execute these
        ;; first, in case their :USEs are circular. The phases follow
        ;; the order specified in [DEFPACKAGE][clhs].
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
        (dolist (sym #-ecl (package-shadowing-symbols pkg)
                     ;; https://gitlab.com/embeddable-common-lisp/ecl/-/work_items/827
                     #+ecl (remove-duplicates (package-shadowing-symbols pkg)))
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
                 (sort (mapcar #'canonical-name names) #'string<))
               (->s* (package-and-name-list)
                 (sort (mapcar (lambda (package-and-name)
                                 (cons (canonical-name (car package-and-name))
                                       (canonical-name (cdr package-and-name))))
                               package-and-name-list)
                       (lambda (cons1 cons2)
                         (or (string< (car cons1) (car cons2))
                             (and (string= (car cons1) (car cons2))
                                  (string< (cdr cons1) (cdr cons2))))))))
          (push `(ensure-package-names ,(-> pkg-name)
                                       ,(maybe-quote (->s nicknames)))
                phase-1-create)
          (let ((doc (documentation (find-package pkg-name) t)))
            (when (and doc process-docstring)
              (push `(setf (documentation (find-package (native-name
                                                         ,(-> pkg-name)))
                                          t)
                           ,doc)
                    phase-1-create)))
          (when shadows
            (push `(shadow* ',(->s shadows) ,(-> pkg-name)) phase-2-shadow))
          (when shadowing-imports
            (push `(shadowing-import/existing ',(->s* shadowing-imports)
                                              ,(-> pkg-name))
                  phase-2-shadow))
          (when use-list
            (push `(use-package/existing ',(->s use-list) ,(-> pkg-name))
                  phase-3-use))
          (when imports
            (push `(import/existing ',(->s* imports) ,(-> pkg-name))
                  phase-4-import))
          (when exports
            ;; If a USE-PACKAGE, SHADOWING-IMPORT or IMPORT was skipped
            ;; because a package was missing, then INTERN makes the
            ;; symbol present, which will cause a package conflict in
            ;; any later USE-PACKAGE, SHADOWING-IMPORT or IMPORT that
            ;; tried to make another symbol with the same name
            ;; accessible.
            (push `(intern-and-export ',(->s exports) ,(-> pkg-name))
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

(defun existing-symbols (package-and-name-list)
  (let ((symbols ()))
    (dolist (entry package-and-name-list)
      (destructuring-bind (symbol-package . symbol-name) entry
        (let ((p (find-package (native-name symbol-package))))
          (when p
            (multiple-value-bind (symbol status)
                (find-symbol (native-name symbol-name) p)
              (when status
                (push symbol symbols)))))))
    (reverse symbols)))

(defun %ensure-package-names (name nicknames)
  (let ((native (native-name name))
        (native-nicks (mapcar #'native-name nicknames)))
    (if (find-package native)
        (rename-package native native native-nicks)
        (make-package native :nicknames native-nicks :use ()))))

(defun %shadow* (names package)
  (shadow (mapcar #'native-name names) (native-name package)))

(defun %shadowing-import/existing (package-and-name-list package)
  (shadowing-import (existing-symbols package-and-name-list)
                    (native-name package)))

(defun %use-package/existing (packages package)
  (use-package (existing-packages packages) (native-name package)))

(defun %import/existing (package-and-name-list package)
  (import (existing-symbols package-and-name-list) (native-name package)))

(defun %intern-and-export (names package)
  (let ((package (native-name package)))
    (export (mapcar (lambda (name)
                      (intern (native-name name) package))
                    names)
            package)))

;;; These are not exported, but GENERATE-PACKAGE-AUTOLOADS outputs
;;; them, so treat them as public.

(defmacro ensure-package-names (name nicknames)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%ensure-package-names ,name ,nicknames)))

(defmacro shadow* (names package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%shadow* ,names ,package)))

(defmacro shadowing-import/existing (package-and-name-list package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%shadowing-import/existing ,package-and-name-list ,package)))

(defmacro use-package/existing (packages package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%use-package/existing ,packages ,package)))

(defmacro import/existing (package-and-name-list package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%import/existing ,package-and-name-list ,package)))

(defmacro intern-and-export (names package)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (%intern-and-export ,names ,package)))


(defclass autoload-cl-source-file (asdf:cl-source-file)
  ()
  (:documentation "The :DEFAULT-COMPONENT-CLASS of AUTOLOAD-SYSTEM.
  The [SYSTEM-AUTOLOADED-SYSTEMS][ (reader autoload-system)] and
  [SYSTEM-RECORD-AUTOLOADS][ (reader autoload-system)] features rely
  on source file belonging to this class. When combining autoload with
  another ASDF extension that has own ASDF:CL-SOURCE-FILE subclass,
  define a new class that inherits from both and use that as
  :DEFAULT-COMPONENT-CLASS."))

;;; The AUTOLOAD-SYSTEM in which the current file is being compiled or
;;; loaded
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
    [AUTOLOAD][macro] signals an error if the ASDF:SYSTEM to be loaded
    is among those declared here.")
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

  - It is an error if an [AUTOLOAD][macro] refers to a
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
  #+(or clisp ecl)
  (unless (slot-value system 'asdf::default-component-class)
    (setf (slot-value system 'asdf::default-component-class)
          'autoload-cl-source-file)))

;;; ASDF:PERFORM is designed for side effects, and we can't just
;;; return stuff normally. LIST-AUTOLOADED-OP gathers systems here.
(defvar *listed-autoloaded-systems*)

(defclass list-autoloaded-op (asdf:sideway-operation)
  ())

(defmethod asdf:operation-done-p ((op list-autoloaded-op) (c asdf:component))
  nil)

(defmethod asdf:perform ((op list-autoloaded-op) (system autoload-system))
  (dolist (s (system-autoloaded-systems system))
    (pushnew s *listed-autoloaded-systems* :test #'equal)))

(defmethod asdf:perform ((op list-autoloaded-op) (system asdf:system))
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
      (asdf:operate 'list-autoloaded-op system :force t)
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
                     (asdf:operate 'list-autoloaded-op s :force t)))
                 (setq processed (append pending processed)))))
    (reverse *listed-autoloaded-systems*)))

(defun check-function-autoload (name asdf-system-name)
  (when *autoload-system*
    (let ((asdf-system-name (asdf:coerce-name asdf-system-name))
          (system-autoloaded-systems
            (system-autoloaded-systems *autoload-system*)))
      (unless (find asdf-system-name system-autoloaded-systems :test #'equal)
        (signal-autoload-warning
         "~@<~S, the system to be autoloaded for function ~S, is ~
         not among ~S, the ~S of ~S.~:@>"
         asdf-system-name name system-autoloaded-systems
         'system-autoloaded-systems
         (asdf:component-name *autoload-system*))))))


;;;; @GENERATING-AUTOLOADS

(defvar *recording-from-system* nil)
(defvar *recorded-autoload-infos*)

(defmacro with-autoloads-file-syntax (&body body)
  `(uiop:with-safe-io-syntax (:package :cl)
     (let ((*print-pretty* t)
           (*print-case* :downcase))
       ,@body)))

(defun prin1-to-string* (object)
  ;; We need to print the same string on all Lisp implementations for
  ;; the sake of the EQUAL comparison in CHECK-SYSTEM-AUTOLOADS.
  ;; *PRINT-PRETTY* NIL would be the easy way, but CLISP still prints
  ;; (QUOTE X) as 'X.
  (with-autoloads-file-syntax
    (let ((*print-right-margin* most-positive-fixnum)
          (*print-miser-width* nil))
      (prin1-to-string object))))

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
                  packages)
  "Return a list of forms that set up autoloading for definitions such
  as DEFUN/AUTOLOADED in [autoloaded direct dependencies][
  SYSTEM-AUTOLOADED-SYSTEMS (reader autoload-system)] of SYSTEM.

  Note that this is an expensive operation, as it loads or reloads the
  direct dependencies one by one with ASDF:LOAD-SYSTEM :FORCE T and
  records the association with the system and the autoloaded
  definitions such as DEFUN/AUTOLOADED.

  - For function definitions such as DEFUN/AUTOLOADED, an
    [AUTOLOAD][macro] form is emitted.

     If PROCESS-ARGLIST is T, then the autoload forms will pass the
     ARGLIST argument of the corresponding DEFUN/AUTOLOADED to
     AUTOLOAD. If it is NIL, then ARGLIST will not be passed to
     AUTOLOAD.

  - For DEFVAR/AUTOLOADED, a DECLARE-VARIABLE-AUTOLOAD is emitted.

     If the initial value form in DEFVAR/AUTOLOADED is detected as a
     simple constant form, then it is passed as INIT to
     DECLARE-VARIABLE-AUTOLOAD. Simple constant forms are strings,
     numbers, characters, keywords, constants in the CL package, and
     QUOTEd nested lists containing any of the previous or any symbol
     from the [CL][package].

  - For DEFPACKAGE/AUTOLOADED and the provided PACKAGES, individual
    package-altering operations are emitted.

      As in the expansion of DEFPACKAGE/AUTOLOADED itself, these
      operations are additive. To handle circular dependencies, first
      all packages are created, then their state is reconstructed in
      phases following [DEFPACKAGE][clhs].

  - If PROCESS-DOCSTRING, then the docstrings extracted from
    DEFUN/AUTOLOADED or DEFVAR/AUTOLOADED will be associated with the
    definition.

  Note that if a function is not defined with DEFUN/AUTOLOADED or its
  kin in @BASICS, then AUTOLOADS will not detect it. For such
  functions, [AUTOLOAD][macro]s must be written manually. Similar
  considerations apply to variables and packages."
  (let* ((infos (without-asdf-session
                  (mapcan #'extract-autoload-infos
                          (system-autoloaded-systems
                           (asdf:find-system system)))))
         (package-infos (remove 'defpackage/autoloaded infos
                                :test-not #'eq :key #'second))
         (other-infos (remove 'defpackage/autoloaded infos
                              :test #'eq :key #'second)))
    (append (generate-package-autoloads (union (mapcar #'third package-infos)
                                               (uiop:ensure-list packages))
                                        :process-docstring process-docstring)
            (mapcan (lambda (info)
                      (info-to-autoload-forms info process-arglist
                                              process-docstring))
                    other-infos))))

(defun write-autoloads (forms stream)
  "Write the autoload FORMS to STREAM that can be LOADed or included
  in an ASDF:DEFSYSTEM."
  (with-autoloads-file-syntax
    (format stream "~S~%~%" `(in-package :cl))
    (format stream "~{~S~%~^~%~}" forms)))

(defun read-autoloads-file (pathname)
  (with-autoloads-file-syntax
    (uiop:read-file-forms pathname)))

(defun extract-autoload-infos (system)
  (let* ((system (asdf:find-system system))
         (*recording-from-system* system)
         (*recorded-autoload-infos* ())
         (asdf:*compile-file-warnings-behaviour* :ignore))
    (asdf:load-system system :force t)
    (reverse *recorded-autoload-infos*)))

(defun info-to-autoload-forms (info process-arglist process-docstring)
  (let ((asdf-system-name (pop info))
        (definer (pop info)))
    (ecase definer
      ((defun/autoloaded)
       (defun/autoloaded-info-to-autoload-form asdf-system-name info
         process-arglist process-docstring))
      ((defvar/autoloaded)
       (defvar/autoloaded-info-to-autoload-form asdf-system-name info
         process-arglist process-docstring)))))

(defun record-autoloads (system output &key (process-arglist t)
                         (process-docstring t) packages)
  (write-autoloads (autoloads system :process-arglist process-arglist
                              :process-docstring process-docstring
                              :packages packages)
                   output))

(defun record-system-autoloads (system)
  "Write the AUTOLOADS of SYSTEM to the file in its
  [:RECORD-AUTOLOADS][ SYSTEM-RECORD-AUTOLOADS (reader
  autoload-system)], which may be a [pathname designator][clhs] or a
  list of the form

      (pathname &key (process-arglist t) (process-docstring t) packages)

  See [AUTOLOADS][function] and WRITE-AUTOLOADS for the description of
  these arguments. PATHNAME is relative to
  ASDF:SYSTEM-SOURCE-DIRECTORY of SYSTEM and is OPENed with :IF-EXISTS
  :SUPERSEDE.

  As AUTOLOADS loads the direct autoloaded dependencies, compiler
  warnings (e.g. about undefined specials and functions) may occur
  that go away once the generated autoloads are in place. The easiest
  way to trigger this is to call RECORD-SYSTEM-AUTOLOADS before these
  dependencies have been loaded. In this case, temporarily emptying
  the autoloads file and fixing these warnings is recommended."
  (let ((system (asdf:find-system system)))
    (check-type system autoload-system)
    (multiple-value-bind (pathname args) (system-record-autoloads* system)
      (let ((pathname (asdf:system-relative-pathname system pathname))
            #+clisp (custom:*reopen-open-file* nil))
        (with-file-superseded (stream pathname)
          (with-autoloads-file-syntax
            (format stream ";;;; This file was emptied by
                            ;;;;~%~
                            ;;;;   ~S~%~
                            ;;;;~%~
                            ;;;; Recording is ongoing or has failed. ~
                                 Do not edit.~%~%"
                    `(record-system-autoloads ,(asdf:component-name system)))))
        (with-file-superseded (stream pathname)
          (with-autoloads-file-syntax
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
                             (process-docstring t) packages)
            args
          (check-type pathname (or string pathname))
          (values pathname `(:process-arglist ,process-arglist
                             :process-docstring ,process-docstring
                             :packages ,packages)))
      ((and error (not type-error)) ()
        (error "~@<~S, the ~S of ~S, is not of the form ~S.~:@>"
               args :record-autoloads (asdf:component-name system)
               '(pathname &key (process-arglist t) (process-docstring t)))))))

(defun check-system-autoloads (system &key (errorp t))
  "In the AUTOLOAD-SYSTEM SYSTEM, check that there is a
  [:RECORD-AUTOLOADS][ system-record-autoloads] and the file generated
  by RECORD-SYSTEM-AUTOLOADS is up-to-date.

  If ERRORP, then signal an error if it is not or the file cannot be
  read. RECORD-SYSTEM-AUTOLOADS restart is provided.

  This compares the current AUTOLOADS to those in the file with EQUAL
  and is thus sensitive to the order of definitions.

  This function is called automatically by ASDF:TEST-OP on a
  AUTOLOAD-SYSTEM method if SYSTEM-TEST-AUTOLOADS."
  (let ((system (asdf:find-system system)))
    (check-type system autoload-system)
    (when (system-record-autoloads system)
      (multiple-value-bind (pathname args) (system-record-autoloads* system)
        (destructuring-bind (&key (process-arglist t) (process-docstring t)
                             packages)
            args
          (flet ((fail (control &rest args)
                   (if errorp
                       (restart-case
                           (error "~@<In system ~S, ~?.~:@>"
                                  (asdf:component-name system)
                                  control args)
                         (record-system-autoloads ()
                           :report (lambda (stream)
                                     (format stream
                                             "Re-record system autoloads."))
                           (record-system-autoloads system)))
                       (return-from check-system-autoloads nil))))
            (let ((pathname (asdf:system-relative-pathname system pathname)))
              (unless (uiop:file-exists-p pathname)
                (fail "~A file ~S is missing." :record-autoloads pathname))
              (let ((recorded-forms
                      (if errorp
                          (read-autoloads-file pathname)
                          (handler-case
                              (read-autoloads-file pathname)
                            (error (e)
                              (fail "reading file ~S failed with ~A."
                                    pathname e)))))
                    (current-forms (autoloads
                                    system :process-arglist process-arglist
                                    :process-docstring process-docstring
                                    :packages packages)))
                (let ((expected '(in-package :cl)))
                  (unless (equal (pop recorded-forms) expected)
                    (fail "the expected ~S form is not found." expected)))
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
