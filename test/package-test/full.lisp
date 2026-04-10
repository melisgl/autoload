;;; Imagine that this is defined in a dependency of
;;; %package-test/full.
(mgl-pax:define-package :%3rd-party
  (:export #:missing #:shadow-target #:plain-import-target)
  (:use :cl))

(autoload:defpackage/auto :%package-test
  (:nicknames :%ptest :%ptest-alt)
  (:use :cl)
  (:shadow #:cons)
  (:shadowing-import-from :%3rd-party #:shadow-target)
  (:import-from :%3rd-party #:plain-import-target)
  (:export #:foo #:plain-import-target)
  (:documentation "%PACKAGE-TEST docstring"))

(cl:in-package :%package-test)

;;; Cover the uninterned symbol shadow branch. DEFPACKAGE does not
;;; easily create uninterned shadows, so we explicitly inject it into
;;; the live package state.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (shadow (list (make-symbol "GHOST-SHADOW")) :%package-test))

(cl:in-package :%package-test)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (use-package :autoload))

(mgl-pax:define-package :%aaa
  (:use :cl)
  (:export #:aaa-foo #:forward-import-target))

(defun %aaa:aaa-foo ())

;; Circular :USEs
(eval-when (:compile-toplevel :load-toplevel :execute)
  (use-package :%package-test :%aaa)
  (use-package :%aaa :%package-test))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (use-package :%aaa :%3rd-party)
  (import '%3rd-party:missing :%aaa)
  (export '%3rd-party:missing :%aaa)
  (import '%aaa::forward-import-target :%package-test))

(defvar/auto *var/3rd-part-init* '%3rd-party::z)

(defvar/auto *var/reconstructed-package-init-good* '%aaa:aaa-foo)

(defvar/auto *var/reconstructed-package-init-bad* (%aaa:aaa-foo))
