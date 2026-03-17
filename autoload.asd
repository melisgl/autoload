;;;; -*- mode: Lisp -*-

(asdf:defsystem "autoload"
  :licence "MIT, see COPYING."
  :version "0.0.1"
  :author "Gábor Melis"
  :mailto "mega@retes.hu"
  :homepage "http://github.com/melisgl/autoload"
  :bug-tracker "https://github.com/melisgl/autoload/issues"
  :source-control (:git "https://github.com/melisgl/autoload.git")
  :description "Bare-bones autoloading facility. See
  AUTOLOAD::@AUTOLOAD-MANUAL."
  :components ((:module "src/"
                :serial t
                :components ((:file "package")
                             (:file "autoload")))))
