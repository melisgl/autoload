(mgl-pax:define-package :autoload
  (:use #:common-lisp)
  (:import-from
   #:mgl-pax
   #:clhs #:macro #:section #:defsection #:glossary-term #:note
   #:docstring #:reader #:define-glossary-term
   #:make-github-source-uri-fn #:register-doc-in-pax-world))
