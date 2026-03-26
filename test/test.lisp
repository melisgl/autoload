(cl:in-package :autoload-test)

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
     (asdf:clear-system "%test-system/full")))

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
    (read-from-string "%simple-test::foo-gf)"))

(define-symbol-macro missing-fn
    (read-from-string "%simple-test::missing-fn)"))

(define-symbol-macro missing-system
    (read-from-string "%simple-test::missing-system)"))

(deftest test-simple ()
  (let ((dir (asdf:system-relative-pathname
              "autoload-test" "test/simple-test/")))
    (labels ((test-file (file)
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
                 (asdf:load-system "%simple-test" :force t)))
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
                         (asdf:load-system "%simple-test" :force t))
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
          ;; This tests AUTOLOAD::*SUPPRESS-HAS-NOT-BEEN-DECLARED-WARNINGS*.
          (signals-not (autoload-warning)
            (record-system-autoloads "%simple-test"))
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
          (is (equal (documentation foo 'function) "foo docstring"))
          (is (not (asdf:component-loaded-p "%simple-test/full")))
          (is (equal (funcall foo 'secret) 'secret))
          (is (asdf:component-loaded-p "%simple-test/full"))
          (is (not (function-autoload-p foo)))))
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
          (signals (error :pred "may not be installed")
            (funcall missing-system))
          (is (function-autoload-p missing-system))))
      (with-test ("AUTOLOAD not redefined")
        (with-test-systems
          (load-simple-test)
          (is (not (asdf:component-loaded-p "%simple-test/full")))
          (is (function-autoload-p missing-fn))
          (signals (error :pred "is still")
            (funcall missing-fn))
          (is (asdf:component-loaded-p "%simple-test/full"))
          (is (function-autoload-p missing-fn)))))))

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
        (is (null (find-package :%3rd-party)))
        (is (match-values (uiop:find-symbol* '#:plain-import-target
                                             :%package-test nil)
              (eq (symbol-package *) (find-package :%package-test))
              (eq * :external)))))))

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
          (signals (error :pred "differ" :handler #'continue)
            (is (not (check-system-autoloads "%test-system"))))
          ;; Test the RECORD-SYSTEM-AUTOLOADS restart.
          (signals (error :pred "differ"
                          :handler (lambda (condition)
                                     (declare (ignore condition))
                                     (invoke-restart 'record-system-autoloads)))
            (is (check-system-autoloads "%test-system")))))
      (with-test ("unresolved variable autoload")
        (with-test-systems
          (write-manual nil)
          (write-full t nil nil)
          (signals (autoload-warning :pred "has not been declared"
                                     :handler #'muffle-warning)
            (asdf:load-system "%test-system/full" :force t))
          ;; Test the CONTINUE restart.
          (signals (error :pred "differ" :handler #'continue)
            (is (not (check-system-autoloads "%test-system"))))
          ;; Test the RECORD-SYSTEM-AUTOLOADS restart.
          (signals (error :pred "differ"
                          :handler (lambda (condition)
                                     (declare (ignore condition))
                                     (invoke-restart 'record-system-autoloads)))
            (is (check-system-autoloads "%test-system")))))
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
            (signals (error :pred "manual" :handler #'continue)
              (is (not (check-system-autoloads "%test-system")))))
          (with-test ("ASDF:TEST-SYSTEM")
            (signals (error :pred "manual" :handler #'continue)
              (asdf:test-system "%test-system")))
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
          (signals (error
                    :handler (lambda (condition)
                               (declare (ignore condition))
                               (invoke-restart 'record-system-autoloads)))
            (let ((*standard-output* (make-broadcast-stream))
                  (*error-output* (make-broadcast-stream)))
              (with-compilation-unit (:override t)
                (asdf:load-system "%test-system" :force t)))))))))


(deftest test-all ()
  (let ((*compile-verbose* nil))
    (test-simple)
    (test-package)
    (test-test-system)))

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
