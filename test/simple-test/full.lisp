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
(defgeneric foo-gf (x))

(defmethod foo-gf ((x integer))
  (1+ x))

(defgeneric/auto foo-gf (x)
  (:method (x)
    x)
  (:documentation "foo-gf docstring"))

(define-auto-function defun custom (x)
  "custom doc"
  x)
