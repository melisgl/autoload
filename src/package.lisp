(cl:defpackage :autoload
  (:use #:common-lisp)
  (:export
   ;; Basics
   #:autoload #:defun/autoloaded #:defvar/autoloaded
   ;; ASDF integration
   #:autoload-system #:system-autoloaded-systems #:system-record-autoloads
   #:autoloaded-systems
   ;; Generating autoloads
   #:autoloads #:write-autoloads #:record-system-autoloads))
