(cl:defpackage :autoload
  (:use #:common-lisp)
  (:export
   ;; Basics
   ;;; Functions
   #:autoload #:function-autoload-p
   #:defun/autoloaded #:defgeneric/autoloaded #:define-autoloaded-function
   ;;; Variables
   #:defvar/autoload #:variable-autoload-p #:defvar/autoloaded
   ;;; Packages
   #:defpackage/autoloaded
   ;; ASDF integration
   #:autoload-system #:system-autoloaded-systems #:system-record-autoloads
   #:autoloaded-systems
   ;;; Generating autoloads
   #:autoloads #:write-autoloads
   #:record-system-autoloads #:check-system-autoloads))
