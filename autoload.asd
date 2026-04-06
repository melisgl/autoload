;;;; -*- mode: Lisp -*-

(asdf:defsystem "autoload"
  :licence "MIT, see COPYING."
  :version "0.0.1"
  :author "Gábor Melis"
  :mailto "mega@retes.hu"
  :homepage "https://github.com/melisgl/autoload"
  :bug-tracker "https://github.com/melisgl/autoload/issues"
  :source-control (:git "https://github.com/melisgl/autoload.git")
  :description "An ASDF autoloading facility. See
  AUTOLOAD::@AUTOLOAD-MANUAL."
  :depends-on ("closer-mop" "mgl-pax-bootstrap")
  :components ((:module "src/"
                :serial t
                :components ((:file "package")
                             (:file "util")
                             (:file "autoload"))))
  :in-order-to ((asdf:test-op (asdf:test-op "autoload-test"))))
