;;;; -*- mode: Lisp -*-

;;; This is in a separate .asd file to help OS-level packaging
;;; (https://github.com/melisgl/try/issues/5) by making the dependency
;;; graph of .asd files (as opposed to that of ASDF systems) acyclic.
(asdf:defsystem "autoload-doc"
  :description "Parts of the Autoload library that depend on
  [`mgl-pax`][asdf:system] are in this system to avoid the circular
  dependencies that would arise because [`mgl-pax`][asdf:system]
  depends on [`autoload`][asdf:system]. Note that
  [`mgl-pax/navigate`][ asdf:system] and [`mgl-pax/document`][
  asdf:system] depend on this system, which renders most of this an
  implementation detail."
  :depends-on ("autoload" "dref" "mgl-pax" "named-readtables"
               "pythonic-string-reader")
  :components ((:module "src/"
                :serial t
                :components ((:file "doc")))))
