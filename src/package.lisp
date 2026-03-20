(cl:defpackage :autoload
  (:use #:common-lisp)
  (:export
   ;; Basics
   #:autoload #:function-autoload-p #:defun/autoloaded #:defgeneric/autoloaded
   #:define-autoloaded-function #:defvar/autoloaded
   ;; ASDF integration
   #:autoload-system #:system-autoloaded-systems #:system-record-autoloads
   #:autoloaded-systems
   ;; Generating autoloads
   #:autoloads #:write-autoloads #:record-system-autoloads))
