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

(defpackage :%3rd-party)

(defun/autoloaded foo-with-unreadable-arglist (&optional (x '%3rd-party::z))
  x)
