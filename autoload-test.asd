;;;; -*- mode: Lisp -*-

;;; This is in a separate .asd file help OS-level packaging by making
;;; the dependency graph of .asd files (as opposed to just ASDF
;;; systems) acyclic. See https://github.com/melisgl/try/issues/5.
(asdf:defsystem "autoload-test"
  :description "Test system for AUTOLOAD."
  :depends-on ("autoload" "try")
  :components ((:module "test"
                :serial t
                :components ((:file "package")
                             (:file "test"))))
  :perform (asdf:test-op (o s)
             (uiop:symbol-call '#:autoload-test '#:test)))
