(cl:in-package :autoload-test)

(defmacro with-test-systems (&body body)
  `(unwind-protect
        (progn
          (load (asdf:system-relative-pathname
                 "autoload-test" "test/simple-test/%simple-test.system"))
          (load (asdf:system-relative-pathname
                 "autoload-test" "test/package-test/%package-test.system"))
          ,@body)
     (ignore-errors (uiop:delete-package* :%simple-test))
     (ignore-errors (uiop:delete-package* :%package-test))
     (ignore-errors (uiop:delete-package* :%aaa))
     (ignore-errors (uiop:delete-package* :%3rd-party))
     (asdf:clear-system "%simple-test")
     (asdf:clear-system "%simple-test/full")
     (asdf:clear-system "%package-test")
     (asdf:clear-system "%package-test/full")))

(define-symbol-macro foo
    (read-from-string "%simple-test::foo"))

(define-symbol-macro *var/no-value*
    (read-from-string "%simple-test::*var/no-value*"))

(define-symbol-macro *var/simple-value*
    (read-from-string "%simple-test::*var/simple-value*"))

(define-symbol-macro *var/complex-value*
    (read-from-string "%simple-test::*var/complex-value*"))

(deftest test-simple ()
  (autoload::without-asdf-session
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
          (is (null (documentation *var/complex-value* 'variable))))))))

(deftest test-package ()
  (autoload::without-asdf-session
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
                (eq * :external))))))))


(deftest test-all ()
  (test-simple)
  (test-package))

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
