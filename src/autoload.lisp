(in-package :autoload)

;;; The AUTOLOAD-SYSTEM being in which the current file is being
;;; compiled or loaded
(defvar *autoload-system* nil)

(defmacro autoload (name asdf-system-name &key (docstring nil docstringp))
  "Define a stub function with NAME to [load][asdf:load-system]
  ASDF-SYSTEM-NAME and return NAME. The arguments are not evaluated.
  If NAME has a [function definition][fdefinition pax:clhs] and it is
  not FUNCTION-AUTOLOAD-P, then do nothing and return NIL.

  The stub is not defined at [compile time][pax:clhs], which matches
  the required semantics of DEFUN. NAME is DECLAIMed with FTYPE
  FUNCTION and NOTINLINE.

  - The stub is defined with DOCSTRING if specified, else with a
    generic docstring that says what system it autoloads.

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
  (assert (special-variable-name-p var))
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
   ;; KLUDGE: (:DEFAULT-INITARGS :DEFAULT-COMPONENT-CLASS
   ;; 'AUTOLOAD-CL-SOURCE-FILE) doesn't work, so do it directly.
   (asdf::default-component-class :initform 'autoload-cl-source-file))
  (:documentation "Inherit from this class in your ASDF:DEFSYSTEM form
  to be able to specify the list of systems autoloaded by the system
  being defined, against which [AUTOLOAD][pax:macro]s are then
  checked.

  ```
  (asdf:defsystem \"some-system\"
    :defsystem-depends-on (\"autoload\")
    :class \"autoload:autoload-system\"
    :autoloaded-systems (\"other-system\"))
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

(defun autoloaded-systems (system &key (follow-autoloaded t))
  "Return the list of the names of systems that may be autoloaded by
  SYSTEM or any of its normal dependencies (the transitive closure of
  its :DEPENDS-ON). This works even if SYSTEM is not an
  AUTOLOAD-SYSTEM.

  If FOLLOW-AUTOLOADED, look further for autoloaded systems among the
  normal and autoloaded dependencies of any autoloaded systems found.
  If an autoloaded system is not installed (i.e. ASDF:FIND-SYSTEM
  fails), then that system is not followed."
  (let ((*listed-autoloaded-systems* ()))
    (asdf:operate 'list-autoloads-op system :force t)
    (when follow-autoloaded
      (loop with processed = ()
            for pending = (set-difference *listed-autoloaded-systems* processed
                                          :test #'equal)
            while pending
            do (dolist (s pending)
                 (when (asdf:find-system s nil)
                   (asdf:operate 'list-autoloads-op s :force t)))
               (setq processed (append pending processed))))
    (reverse *listed-autoloaded-systems*)))
