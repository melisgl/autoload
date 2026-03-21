(cl:in-package :autoload-test)

(defmacro with-test-systems (&body body)
  `(unwind-protect
        (progn
          (load (asdf:system-relative-pathname
                 "autoload-test" "test/data/%autoload-test.system"))
          ,@body)
     (ignore-errors (delete-package :%autoload-test))
     (asdf:clear-system "%autoload-test")
     (asdf:clear-system "%autoload-test/full")))

(define-symbol-macro foo
    (read-from-string "%autoload-test::foo"))

(define-symbol-macro *var/no-value*
    (read-from-string "%autoload-test::*var/no-value*"))

(define-symbol-macro *var/simple-value*
    (read-from-string "%autoload-test::*var/simple-value*"))

(define-symbol-macro *var/complex-value*
    (read-from-string "%autoload-test::*var/complex-value*"))

(deftest test-lifecycle ()
  (autoload::without-asdf-session
    (let ((data-dir (asdf:system-relative-pathname
                     "autoload-test" "test/data/")))
      (flet ((data-file (file)
               (merge-pathnames file data-dir)))
        (with-test-systems
          (uiop:delete-file-if-exists (data-file "autoloads.lisp"))
          ;; This tests AUTOLOAD::*SUPPRESS-HAS-NOT-BEEN-DECLARED-WARNINGS*.
          (signals-not (warning)
            (record-system-autoloads "%autoload-test"))
          (let ((*package* (find-package :autoload-test)))
            (is (equal (uiop:read-file-forms
                        (data-file "autoloads.lisp"))
                       (uiop:read-file-forms
                        (data-file "expected-autoloads.lisp"))))))
        (with-test-systems
          (asdf:load-system "%autoload-test" :force t)
          (is (not (asdf:component-loaded-p "%autoload-test/full")))
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


(deftest test-all ()
  (test-lifecycle))

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
