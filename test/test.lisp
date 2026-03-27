(cl:in-package :autoload-test)

(deftest test-autoload-defaults ()
  (let ((loadedp (and (not (function-autoload-p 'pax:escape-markdown))
                      (ignore-errors (fdefinition 'pax:escape-markdown)))))
    ;; KLUDGE: Some Lisps don't immediately associate the arglist and
    ;; docstring with the definition.
    (with-compilation-unit (:override t)
      #-ecl
      (progn (fmakunbound 'xyz) (autoload xyz "*xyz"))
      ;; KLUDGE: Some Lisps don't immediately associate the arglist and
      ;; docstring with the definition.
      #+ecl
      (eval '(progn (fmakunbound 'xyz) (autoload xyz "*xyz"))))
    (is (equal (dref:arglist #'xyz) '(&rest autoload::args)))
    (is (equal
         (dref:docstring #'xyz)
         (if loadedp
             "[AUTOLOADed][pax:macro] function in the \\*xyz ASDF:SYSTEM."
             "[AUTOLOADed][pax:macro] function in the *xyz ASDF:SYSTEM.")))))


(defun empty-file (pathname)
  (autoload::with-file-superseded (stream pathname)
    (declare (ignorable stream))))

(defmacro with-test-systems (&body body)
  `(unwind-protect
        (autoload::without-asdf-session
          (let ((asdf:*compile-file-warnings-behaviour* :ignore))
            (load (asdf:system-relative-pathname
                   "autoload-test" "test/simple-test/%simple-test.system"))
            (load (asdf:system-relative-pathname
                   "autoload-test" "test/package-test/%package-test.system"))
            (load (asdf:system-relative-pathname
                   "autoload-test" "test/test-system/%test-system.system")))
          ,@body)
     (ignore-errors (uiop:delete-package* :%simple-test))
     (ignore-errors (uiop:delete-package* :%package-test))
     (ignore-errors (uiop:delete-package* :%aaa))
     (ignore-errors (uiop:delete-package* :%3rd-party))
     (ignore-errors (uiop:delete-package* :%test-system))
     (asdf:clear-system "%simple-test")
     (asdf:clear-system "%simple-test/full")
     (asdf:clear-system "%package-test")
     (asdf:clear-system "%package-test/full")
     (asdf:clear-system "%test-system")
     (asdf:clear-system "%test-system/full")
     (asdf:clear-system "%installer-test")
     (asdf:clear-system "%not-installed-1")
     (asdf:clear-system "%not-installed-2")))

(define-symbol-macro foo
    (read-from-string "%simple-test::foo"))

(define-symbol-macro *var/no-value*
    (read-from-string "%simple-test::*var/no-value*"))

(define-symbol-macro *var/simple-value*
    (read-from-string "%simple-test::*var/simple-value*"))

(define-symbol-macro *var/complex-value*
    (read-from-string "%simple-test::*var/complex-value*"))

(define-symbol-macro xxx
    (read-from-string "%simple-test::xxx"))

(define-symbol-macro setf-xxx
    (read-from-string "(cl:setf %simple-test::xxx)"))

(define-symbol-macro foo-gf
    (read-from-string "%simple-test::foo-gf"))

(define-symbol-macro missing-fn
    (read-from-string "%simple-test::missing-fn"))

(define-symbol-macro missing-system
    (read-from-string "%simple-test::missing-system"))

(define-symbol-macro custom
    (read-from-string "%simple-test::custom"))

(deftest test-simple ()
  (let ((dir (asdf:system-relative-pathname
              "autoload-test" "test/simple-test/")))
    ;; KLUDGE: ECL runs into evaluator errors with
    ;; ASDF:LOAD-SOURCE-OP.
    (dolist (load-source-p '(#-ecl t nil))
      (with-test ((format nil "load-source-p ~S" load-source-p))
        (labels
            ((test-file (file)
               (merge-pathnames file dir))
             (missing-system-condition-p (condition)
               (search "\"%missing\", the system to be autoloaded"
                       (try::%describe-condition-for-matching condition)))
             (unreadable-arglist-condition-p (condition)
               (let ((s (try::%describe-condition-for-matching condition)))
                 (and (search "3rd-party::z" s)
                      (search "could not be read" s))))
             (unexpected-condition-p (condition)
               (and (not (missing-system-condition-p condition))
                    (not (unreadable-arglist-condition-p condition))))
             (%load-simple-test ()
               (let ((*error-output* (make-broadcast-stream)))
                 (if load-source-p
                     (asdf:operate 'asdf:load-source-op "%simple-test")
                     (asdf:load-system "%simple-test" :force t))))
             (load-simple-test (&optional empty-autoloads-file-p)
               (signals-not (autoload-warning :pred #'unexpected-condition-p
                             :handler #'muffle-warning)
                 ;; CCC [handle][clhs]s warnings in COMPILE-FILE.
                 #-ccl
                 (signals (autoload-warning :pred #'missing-system-condition-p
                           :handler #'muffle-warning)
                   (if empty-autoloads-file-p
                       (%load-simple-test)
                       ;; Some Lisps let compile-time warnings through
                       ;; but handle load-time ones.
                       #-(or abcl clisp cmucl ecl)
                       (signals (autoload-warning
                                 :pred #'unreadable-arglist-condition-p
                                 :handler #'muffle-warning)
                         (%load-simple-test))
                       #+(or abcl clisp cmucl ecl)
                       (%load-simple-test)))
                 #+ccl
                 (%load-simple-test))))
          (with-test ("RECORD-SYSTEM-AUTOLOADS")
            (with-test-systems
              (empty-file (test-file "autoloads.lisp"))
              (load-simple-test t)
              ;; RECORD-SYSTEM-AUTOLOADS should handle this missing file.
              (uiop:delete-file-if-exists (test-file "autoloads.lisp"))
              (if (not load-source-p)
                  ;; This tests
                  ;; AUTOLOAD::*SUPPRESS-HAS-NOT-BEEN-DECLARED-WARNINGS*.
                  (signals-not (autoload-warning :handler #'muffle-warning)
                    (record-system-autoloads "%simple-test"))
                  ;; KLUDGE: For some reason, this loads the base
                  ;; system, which emits a warning for
                  ;; %MISSING-SYSTEM.
                  (handler-bind ((autoload-warning #'muffle-warning))
                    (record-system-autoloads "%simple-test")))
              (let ((*package* (find-package :autoload-test)))
                (is (equal (uiop:read-file-forms
                            (test-file "autoloads.lisp"))
                           (uiop:read-file-forms
                            (test-file "expected-autoloads.lisp")))))))
          (with-test ("variables and simple DEFUN")
            (with-test-systems
              (load-simple-test)
              (is (not (function-autoload-p 'non-existent)))
              ;; *VAR/NO-VALUE*
              (is (variable-autoload-p *var/no-value*))
              (is (not (boundp *var/no-value*)))
              (is (equal (documentation *var/no-value* 'variable)
                         "*var/no-value* docstring"))
              ;; *VAR/SIMPLE-VALUE*
              (is (variable-autoload-p *var/simple-value*))
              (is (and (boundp *var/simple-value*)
                       (equal (symbol-value *var/simple-value*)
                              '("xxx" 7 :key nil t))))
              (is (equal (documentation *var/simple-value* 'variable)
                         "*var/simple-value* docstring"))
              ;; *VAR/COMPLEX-VALUE*
              (is (variable-autoload-p *var/complex-value*))
              (is (not (boundp *var/complex-value*)))
              (is (null (documentation *var/complex-value* 'variable)))
              ;; FOO
              (is (function-autoload-p foo))
              #+sbcl
              (is (equal (dref:arglist (dref:dref foo 'function))
                         (read-from-string "(%simple-test::x)")))
              (is (equal (documentation foo 'function) "foo docstring"))
              (is (not (asdf:component-loaded-p "%simple-test/full")))
              (is (equal (funcall foo 'secret) 'secret))
              (is (asdf:component-loaded-p "%simple-test/full"))
              (is (not (function-autoload-p foo)))))
          (with-test ("traced stub")
            (with-test-systems
              (load-simple-test)
              (is (function-autoload-p foo))
              ;; CMUCL sometimes fails with a type error somewhere in the
              ;; tracing machinery.
              #-cmucl
              (eval `(trace ,foo))
              (is (not (asdf:component-loaded-p "%simple-test/full")))
              (let ((*trace-output* (make-broadcast-stream)))
                (is (equal (funcall foo 'secret) 'secret)))
              (is (asdf:component-loaded-p "%simple-test/full"))
              (is (not (function-autoload-p foo)))))
          (with-test ("GLOBAL-SYMBOL-VALUE")
            (with-test-systems
              (load-simple-test)
              (progv (list *var/simple-value*) '(:local)
                (is (eq (symbol-value *var/simple-value*) :local))
                (is (equal (funcall foo 'secret) 'secret))
                (is (eq (symbol-value *var/simple-value*) :local)))
              (is (equal (symbol-value *var/simple-value*)
                         '("xxx" 7 :key nil t)))))
          (with-test ("DEFUN (SETF XXX)")
            (with-test-systems
              (load-simple-test)
              (is (not (asdf:component-loaded-p "%simple-test/full")))
              (is (function-autoload-p setf-xxx))
              (is (eq (eval (read-from-string
                             "(cl:setf (%simple-test::xxx)
                                   'autoload-test::secret)"))
                      'secret))
              (is (asdf:component-loaded-p "%simple-test/full"))
              (is (not (function-autoload-p setf-xxx)))))
          (with-test ("DEFGENERIC")
            (with-test-systems
              (load-simple-test)
              (is (not (asdf:component-loaded-p "%simple-test/full")))
              (is (function-autoload-p foo-gf))
              (is (eq (funcall foo-gf 7) 8))
              (is (asdf:component-loaded-p "%simple-test/full"))
              (is (not (function-autoload-p foo-gf)))))
          (with-test ("AUTOLOAD missing system")
            (with-test-systems
              (load-simple-test)
              (is (not (asdf:component-loaded-p "%simple-test/full")))
              (is (function-autoload-p missing-system))
              (signals (autoload-error
                        :pred (lambda (c)
                                (eq (autoload::autoload-error-cause c)
                                    :system-not-found)))
                (funcall missing-system))
              (is (function-autoload-p missing-system))))
          (with-test ("AUTOLOAD not redefined")
            (with-test-systems
              (load-simple-test)
              (is (not (asdf:component-loaded-p "%simple-test/full")))
              (is (function-autoload-p missing-fn))
              (signals (autoload-error
                        :pred (lambda (c)
                                (eq (autoload::autoload-error-cause c)
                                    :not-resolved)))
                (funcall missing-fn))
              (is (asdf:component-loaded-p "%simple-test/full"))
              (is (function-autoload-p missing-fn))))
          (with-test ("DEFINE-AUTOLOADED-FUNCTION")
            (with-test-systems
              (load-simple-test)
              (is (not (asdf:component-loaded-p "%simple-test/full")))
              (is (function-autoload-p custom))
              (is (eq (funcall custom 'secret) 'secret))
              (is (asdf:component-loaded-p "%simple-test/full"))
              (is (not (function-autoload-p custom))))))))))

(deftest test-package ()
  (let ((dir (asdf:system-relative-pathname "autoload-test"
                                            "test/package-test/")))
    (flet ((test-file (file)
             (merge-pathnames file dir)))
      (with-test-systems
        (uiop:delete-file-if-exists (test-file "autoloads.lisp"))
        (signals-not (autoload-warning :handler nil)
          (record-system-autoloads "%package-test"))
        (let ((*package* (find-package :autoload-test)))
          (is (equal (uiop:read-file-forms
                      (test-file "autoloads.lisp"))
                     (uiop:read-file-forms
                      (test-file "expected-autoloads.lisp")))))
        (asdf:load-system "%package-test" :force t))
      (with-test-systems
        (load (compile-file (test-file "autoloads.lisp")))
        (let ((pkg (find-package :%package-test))
              (%aaa (find-package :%aaa)))
          ;; Ensure packages were created
          (is (not (null pkg)))
          (is (not (null %aaa)))
          ;; Check nicknames
          (is (subsetp (list (string '#:%ptest) (string '#:%ptest-alt))
                       (package-nicknames pkg) :test #'string=))
          ;; Check circular use-list
          (is (member (find-package :cl) (package-use-list pkg)))
          (is (member %aaa (package-use-list pkg)))
          (is (member pkg (package-use-list %aaa)))
          ;; Check shadows (including the uninterned GHOST-SHADOW)
          (let ((shadows (mapcar #'symbol-name
                                 (package-shadowing-symbols pkg))))
            (is (member (string '#:cons) shadows :test #'string=))
            (is (member (string '#:ghost-shadow) shadows :test #'string=)))
          ;; Check documentation
          (is (equal (documentation pkg t) "%PACKAGE-TEST docstring"))
          ;; Check exports and missing dependencies. %3rd-party isn't
          ;; loaded yet, so PLAIN-IMPORT-TARGET and SHADOW-TARGET are
          ;; gracefully interned in %PACKAGE-TEST rather than
          ;; imported.
          (is (null (find-package :%3rd-party)))
          (is (match-values (uiop:find-symbol* '#:plain-import-target pkg nil)
                (eq (symbol-package *) pkg)
                (eq * :external)))
          (is (match-values (uiop:find-symbol* '#:foo pkg nil)
                (eq (symbol-package *) pkg)
                (eq * :external)))
          ;; Check the transitive export on %AAA
          (is (match-values (uiop:find-symbol* '#:missing %aaa nil)
                (eq (symbol-package *) %aaa)
                (eq * :external))))))))

(deftest test-test-system ()
  (let ((dir (asdf:system-relative-pathname
              "autoload-test" "test/test-system/")))
    (labels
        ((test-file (file)
           (merge-pathnames file dir))
         (write-manual (bar-p)
           (autoload::with-file-superseded
               (stream (test-file "manual-autoloads.lisp"))
             (when bar-p
               (format stream "(autoload:autoload %test-system::bar ~
                       \"%test-system/full\")"))))
         (write-full (foo-p *foo*-p bar-p)
           (autoload::with-file-superseded (stream (test-file "full.lisp"))
             (when foo-p
               (write-line "(autoload:defun/autoloaded %test-system::foo ())"
                           stream))
             (when *foo*-p
               (write-line "(autoload:defvar/autoloaded %test-system::*foo*)"
                           stream))
             (when bar-p
               (format stream "(cl:fmakunbound '%test-system::bar)~%~
                       (cl:defun %test-system::bar ())~%")))))
      (with-test ("sunshine")
        (with-test-systems
          (empty-file (test-file "autoloads.lisp"))
          (write-manual nil)
          (write-full t t nil)
          (record-system-autoloads "%test-system")
          (is (check-system-autoloads "%test-system" :errorp nil))))
      (with-test ("unresolved function autoload")
        (with-test-systems
          (write-manual nil)
          (write-full nil t nil)
          ;; Compile-time warnings are handled by the compiler on some
          ;; Lisps.
          (signals-not (autoload-warning)
            ;; KLUDGE: ASDF uses FILE-WRITE-DATE to decide whether the
            ;; fasl is stale. FILE-WRITE-DATE has a resolution of one
            ;; second. Since we have compiled and overwritten
            ;; full.lisp in quick succession, force loading.
            (asdf:load-system "%test-system/full" :force t))
          ;; Test the CONTINUE restart.
          (let ((n-continues 0))
            (signals (error :pred "differ"
                      :handler (lambda (condition)
                                 (when (= (incf n-continues) 1)
                                   (continue condition))))
              (is (not (check-system-autoloads "%test-system")))))
          ;; Test the RECORD-SYSTEM-AUTOLOADS restart.
          (let ((n-handles 0))
            (signals (error :pred "differ"
                      :handler (lambda (condition)
                                 (when (= (incf n-handles) 1)
                                   (record-system-autoloads condition))))
              (is (check-system-autoloads "%test-system"))))))
      (with-test ("unresolved variable autoload")
        (with-test-systems
          (write-manual nil)
          (write-full t nil nil)
          (signals (autoload-warning :pred "has not been declared"
                    :handler #'muffle-warning)
            (asdf:load-system "%test-system/full" :force t))
          ;; Test the CONTINUE restart.
          (let ((n-continues 0))
            (signals (error :pred "differ"
                      :handler (lambda (condition)
                                 (when (= (incf n-continues) 1)
                                   (continue condition))))
              (is (not (check-system-autoloads "%test-system")))))
          ;; Test the RECORD-SYSTEM-AUTOLOADS restart.
          (let ((n-handles 0))
            (signals (error :pred "differ"
                      :handler (lambda (condition)
                                 (when (= (incf n-handles) 1)
                                   (record-system-autoloads condition))))
              (is (check-system-autoloads "%test-system"))))))
      (with-test ("resolved manual function autoload")
        (with-test-systems
          (write-manual t)
          (write-full t t t)
          (asdf:load-system "%test-system" :force t)
          (signals (autoload-warning :pred "has not been declared"
                    :handler #'muffle-warning)
            (asdf:load-system "%test-system/full" :force t))
          (record-system-autoloads "%test-system")
          (is (check-system-autoloads "%test-system"))))
      (with-test ("unresolved manual function autoload")
        (with-test-systems
          (write-manual t)
          (write-full t t nil)
          (asdf:load-system "%test-system" :force t)
          (asdf:load-system "%test-system/full" :force t)
          (record-system-autoloads "%test-system")
          ;; Test the CONTINUE restart.
          (with-test ("CONTINUE")
            (let ((n-continues 0))
              (signals (error :pred "manual"
                        :handler (lambda (condition)
                                   (when (= (incf n-continues) 1)
                                     (continue condition))))
                (is (not (check-system-autoloads "%test-system"))))))
          (with-test ("ASDF:TEST-SYSTEM")
            (let ((n-continues 0))
              (signals (error :pred "manual"
                        :handler (lambda (condition)
                                   (when (= (incf n-continues) 1)
                                     (continue condition))))
                (asdf:test-system "%test-system"))))
          ;; Test that there is no RECORD-SYSTEM-AUTOLOADS restart.
          (signals (error :pred "manual"
                    :handler (lambda (condition)
                               (is (null (find-restart
                                          'record-system-autoloads
                                          condition)))
                               (continue condition)))
            (is (not (check-system-autoloads "%test-system"))))))
      (with-test ("compile error in autoloads")
        (with-test-systems
          (write-manual t)
          (write-full t t t)
          (autoload::with-file-superseded (stream (test-file "autoloads.lisp"))
            (format stream "yyy:xxx"))
          (signals (error :handler #'record-system-autoloads)
            (let ((*standard-output* (make-broadcast-stream))
                  (*error-output* (make-broadcast-stream)))
              (with-compilation-unit (:override t)
                (asdf:load-system "%test-system" :force t)))))))))

(deftest test-autoloaded-systems ()
  (with-test-systems
    (asdf:defsystem "%installer-test"
      :class "autoload:autoload-system"
      :autoloaded-systems ("%not-installed-1"))
    (is (equal (autoloaded-systems "%installer-test" :follow-autoloaded nil)
               '("%not-installed-1")))
    (let* ((installed ())
           (systems
             (autoloaded-systems
              "%installer-test"
              :installer
              (lambda (system-name)
                (cond ((string= system-name "%not-installed-1")
                       (eval '(asdf:defsystem "%not-installed-1"
                               :class "autoload:autoload-system"
                               :autoloaded-systems ("%not-installed-2"))))
                      ((string= system-name "%not-installed-2")
                       (eval '(asdf:defsystem "%not-installed-2"
                               :class "autoload:autoload-system"))))
                (push system-name installed)))))
      (is (equal systems '("%not-installed-1" "%not-installed-2")))
      (is (equal (reverse installed)
                 '("%not-installed-1" "%not-installed-2"))))))


(deftest test-all ()
  (test-autoload-defaults)
  (let ((*compile-verbose* nil))
    (test-simple)
    (test-package)
    (test-test-system))
  (test-autoloaded-systems))

(defun test (&key (debug nil) (print 'leaf) (describe *describe*))
  (with-compilation-unit (:override t)
    ;; Bind *PACKAGE* so that names of tests printed have package
    ;; names, and M-. works on them in Slime.
    (let ((*package* (find-package :common-lisp))
          (*print-duration* nil)
          (*print-compactly* t)
          (*print-parent* nil)
          (*defer-describe* t))
      (warn-on-tests-not-run ((find-package :autoload-test))
        (print (try 'test-all :debug debug :print print
                    :describe describe))))))
