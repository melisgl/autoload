(cl:defpackage :autoload
  (:use #:common-lisp)
  (:export
   ;; Basics
   #:autoload-error
   #:autoload-warning
   ;;; Functions
   #:autoload
   #:autoload-fbound-p
   #:defun/auto
   #:defgeneric/auto
   ;;; Classes
   #:autoload-class
   #:autoload-class-p
   #:defclass/auto
   ;;; Variables
   #:defvar/auto
   ;;; Packages
   #:defpackage/auto
   ;; ASDF integration
   #:autoload-system
   #:autoload-cl-source-file
   #:system-auto-depends-on
   #:system-auto-loaddefs
   #:autodeps
   ;;; Automatically generating loaddefs
   #:extract-loaddefs
   #:write-loaddefs
   #:record-loaddefs
   #:check-loaddefs))
