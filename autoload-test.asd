;;;; -*- mode: Lisp -*-

(asdf:defsystem "autoload-test"
  :licence "MIT, see COPYING."
  :author "Gábor Melis"
  :mailto "mega@retes.hu"
  :homepage ""
  :bug-tracker ""
  :source-control ""
  :description "Test system for AUTOLOAD."
  :long-description ""
  :depends-on ("autoload" "try")
  :components ((:module "test"
                :serial t
                :components ((:file "package")
                             (:file "test"))))
  :perform (asdf:test-op (o s)
             (uiop:symbol-call '#:autoload-test '#:test)))
