(cl:in-package :autoload-test)

(defmacro with-test-systems (&body body)
  `(unwind-protect
        (autoload::without-asdf-session
          (load (asdf:system-relative-pathname
                 "autoload-test" "test/simple-test/%simple-test.system"))
          (load (asdf:system-relative-pathname
                 "autoload-test" "test/package-test/%package-test.system"))
          (load (asdf:system-relative-pathname
                 "autoload-test" "test/test-system/%test-system.system"))
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

(deftest test-simple ()
  (let ((dir (asdf:system-relative-pathname
              "autoload-test" "test/simple-test/")))
    (flet ((test-file (file)
             (merge-pathnames file dir)))
      (with-test-systems
        (uiop:delete-file-if-exists (test-file "autoloads.lisp"))
        ;; This tests AUTOLOAD::*SUPPRESS-HAS-NOT-BEEN-DECLARED-WARNINGS*.
        (signals-not (autoload-warning)
          (record-system-autoloads "%simple-test"))
        (let ((*package* (find-package :autoload-test)))
          (is (equal (uiop:read-file-forms
                      (test-file "autoloads.lisp"))
                     (uiop:read-file-forms
                      (test-file "expected-autoloads.lisp"))))))
      (with-test-systems
        ;; KLUDGE: (ASDF:LOAD-SYSTEM "%SIMPLE-TEST" :FORCE T) does
        ;; not seem to work on ECL.
        (load (compile-file (test-file "package.lisp")))
        ;; Warning is from
        ;; %SIMPLE-TEST::FOO-WITH-UNREADABLE-ARGLIST.
        (handler-bind ((autoload-warning #'muffle-warning))
          (load (compile-file (test-file "autoloads.lisp"))))
        (is (not (asdf:component-loaded-p "%simple-test/full")))
        (is (not (function-autoload-p 'non-existent)))
        ;; FOO
        (is (function-autoload-p foo))
        (is (equal (documentation foo 'function) "foo docstring"))
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
        (is (null (documentation *var/complex-value* 'variable)))))))

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
               (write-line "(cl:defun %test-system::bar ())" stream)))))
      (with-test ("sunshine")
        (with-test-systems
          (autoload::with-file-superseded
              (stream (test-file "manual-autoloads.lisp")))
          (write-manual nil)
          (write-full t t nil)
          (record-system-autoloads "%test-system")
          (is (check-system-autoloads "%test-system" :errorp nil))))
      (with-test ("unresolved function autoload")
        (with-test-systems
          (write-manual nil)
          (write-full nil t nil)
          ;; KLUDGE: ASDF uses FILE-WRITE-DATE to decide whether the
          ;; fasl is stale. FILE-WRITE-DATE has a resolution of one
          ;; second. Since we have compiled and overwritten full.lisp
          ;; in quick succession, force loading.
          (asdf:load-system "%test-system/full" :force t)
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
          (write-full t nil nil)
          (asdf:load-system "%test-system/full" :force t)
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
          (asdf:load-system "%test-system/full" :force t)
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
          (signals (error :pred "manual" :handler #'continue)
            (is (not (check-system-autoloads "%test-system"))))
          ;; Test that there is no RECORD-SYSTEM-AUTOLOADS restart.
          (signals (error :pred "manual"
                    :handler (lambda (condition)
                               (is (null (find-restart 'record-system-autoloads
                                                       condition)))
                               (continue condition)))
            (is (not (check-system-autoloads "%test-system")))))))))


(deftest test-all ()
  (test-simple)
  (test-package)
  (test-test-system))

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
