(cl:defpackage :autoload
  (:use #:common-lisp)
  (:export
   ;; Basics
   ;;; Functions
   #:autoload #:autoload-fbound-p
   #:defun/autoloaded #:defgeneric/autoloaded #:define-autoloaded-function
   ;;; Variables
   #:defvar/autoloaded
   ;;; Packages
   #:defpackage/autoloaded
   ;;; Conditions
   #:autoload-error #:autoload-warning
   ;; ASDF integration
   #:autoload-system #:autoload-cl-source-file
   #:system-auto-depends-on #:system-auto-loaddefs #:autodeps
   ;;; Automatically generating loaddefs
   #:extract-loaddefs #:write-loaddefs
   #:record-loaddefs #:check-loaddefs))
