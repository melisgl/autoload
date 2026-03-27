;;;; -*- mode: Lisp -*-

;;; This is in a separate .asd file help OS-level packaging by making
;;; the dependency graph of .asd files (as opposed to just ASDF
;;; systems) acyclic. See https://github.com/melisgl/try/issues/5.
(asdf:defsystem "autoload-doc"
  :description "Parts of [`autoload`][asdf:system] that depend on
  [`mgl-pax`][asdf:system]. Since [`mgl-pax`][asdf:system] depends on
  `autoload`, these parts get a separate system to break the
  circularity. Note that [`mgl-pax/navigate`][asdf:system] and
  [`mgl-pax/document`][asdf:system] depend on this system, which
  renders most of this an implementation detail."
  :depends-on ("autoload" "mgl-pax" "named-readtables"
               "pythonic-string-reader")
  :components ((:module "src/"
                :serial t
                :components ((:file "doc")))))
