;;;; -*- mode: Lisp -*-

;;; This is in a separate .asd file to help OS-level packaging
;;; (https://github.com/melisgl/try/issues/5) by making the dependency
;;; graph of .asd files (as opposed to that of ASDF systems) acyclic.
(asdf:defsystem "autoload-test"
  :description "Test system for AUTOLOAD."
  :depends-on ("autoload" "try")
  :components ((:module "test"
                :serial t
                :components ((:file "package")
                             (:file "test"))))
  :perform (asdf:test-op (o s)
             (uiop:symbol-call '#:autoload-test '#:test)))
