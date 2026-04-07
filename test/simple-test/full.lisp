(cl:in-package :%simple-test)

(defun/auto foo (x)
  "foo docstring"
  x)

(defvar/auto *var/no-value*)
(setf (documentation '*var/no-value* 'variable)
      "*var/no-value* docstring")

(defvar/auto *var/simple-value* '("xxx" 7 :key nil t)
                   "*var/simple-value* docstring")

(defvar/auto *var/complex-value* (1+ 2))

(defvar/auto *var/circular-value* '#1=(1+ #1#))

(defpackage :%3rd-party)

(defun/auto foo-with-unreadable-arglist (&optional (x '%3rd-party::z))
  x)

(defun/auto (setf xxx) (x) x)

;;; We will check that this method is not lost in
;;; DEFGENERIC/AUTO.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (fmakunbound 'foo-gf))

;;; Prevent redefinition warnings from DEFGENERIC/AUTO below.
#+(or clisp sbcl) (defgeneric foo-gf (x))

(defmethod foo-gf ((x integer))
  (1+ x))

(defgeneric/auto foo-gf (x)
  (:method (x)
    x)
  (:documentation "foo-gf docstring"))

(defmacro my-defun (name lambda-list &body body)
  `(defun ,name ,lambda-list
     (list 'my-defun-ran ,@body)))

(defmacro my-defclass (name supers slots &rest options)
  `(defclass ,name ,supers
     ((custom-slot :initform 'my-defclass-ran) ,@slots)
     ,@options))

(defun/auto (my-defun test-custom-fun) (x) x)

(defclass/auto (my-defclass test-custom-class) () ())
