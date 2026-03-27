(cl:in-package :%simple-test)

(defun/autoloaded foo (x)
  "foo docstring"
  x)

(defvar/autoloaded *var/no-value*)
(setf (documentation '*var/no-value* 'variable)
      "*var/no-value* docstring")

(defvar/autoloaded *var/simple-value* '("xxx" 7 :key nil t)
                   "*var/simple-value* docstring")

(defvar/autoloaded *var/complex-value* (1+ 2))

(defvar/autoloaded *var/circular-value* '#1=(1+ #1#))

(defpackage :%3rd-party)

(defun/autoloaded foo-with-unreadable-arglist (&optional (x '%3rd-party::z))
  x)

(defun/autoloaded (setf xxx) (x) x)

;;; We will check that this method is not lost in
;;; DEFGENERIC/AUTOLOADED.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (fmakunbound 'foo-gf))

;;; Prevent redefinition warnings from DEFGENERIC/AUTOLOADED below.
(defgeneric foo-gf (x))

(defmethod foo-gf ((x integer))
  (1+ x))

(defgeneric/autoloaded foo-gf (x)
  (:method (x)
    x)
  (:documentation "foo-gf docstring"))

(define-autoloaded-function defun custom (x)
  "custom doc"
  x)
