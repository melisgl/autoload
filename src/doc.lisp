(in-package :autoload)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (import '(pax:clhs pax:macro pax:section pax:defsection pax:reader
            pax:define-glossary-term pax:make-github-source-uri-fn
            pax:register-doc-in-pax-world)
          :autoload))

(defsection @autoload-manual (:title "Autoload Manual" :export nil)
  (@links-and-systems section)
  (@basics section)
  (@asdf-integration section))

(defsection @links-and-systems (:title "Links and Systems" :export nil)
  "Here is the [official
  repository](https://github.com/melisgl/autoload/) and the [HTML
  documentation](http://melisgl.github.io/mgl-pax-world/autoload.html)
  for the latest version."
  ("autoload" asdf:system)
  ("autoload-doc" asdf:system))

(defsection @basics (:title "Basics" :export nil)
  (autoload-warning condition)
  (@functions section)
  (@variables section)
  (@packages section))

(defsection @functions (:title "Functions" :export nil)
  (autoload macro)
  (function-autoload-p function)
  (defun/autoloaded macro)
  (defgeneric/autoloaded macro)
  (define-autoloaded-function macro))

(defsection @variables (:title "Variables" :export nil)
  (declare-variable-autoload macro)
  (variable-autoload-p function)
  (defvar/autoloaded macro))

(defsection @packages (:title "Package" :export nil)
  (defpackage/autoloaded macro))

(defsection @asdf-integration (:title "ASDF Integration" :export nil)
  (autoload-system class)
  (system-autoloaded-systems (reader autoload-system))
  (system-record-autoloads (reader autoload-system))
  (system-test-autoloads (reader autoload-system))
  (autoloaded-systems function)
  (@generating-autoloads section)
  (autoload-cl-source-file class))

(defsection @generating-autoloads (:title "Generating Autoloads" :export nil)
  (autoloads function)
  (write-autoloads function)
  (record-system-autoloads function)
  (check-system-autoloads function))

(define-glossary-term @slime-autodoc
    (:title "SLIME autodoc"
     :url "https://slime.common-lisp.dev/doc/html/slime_002dautodoc_002dmode.html#slime_002dautodoc_002dmode"))

(define-glossary-term @quicklisp
    (:title "Quicklisp"
     :url "https://www.quicklisp.org/"))


;;;; Register in PAX World

(defun autoload-sections ()
  (list @autoload-manual))

(defun autoload-pages ()
  `((:objects
     (, @autoload-manual)
     :source-uri-fn ,(make-github-source-uri-fn
                      "autoload" "https://github.com/melisgl/autoload"))))

(register-doc-in-pax-world :autoload (autoload-sections) (autoload-pages))


#+nil
(progn
  (asdf:load-system "autoload-doc")
  (pax:update-asdf-system-readmes @autoload-manual "autoload"
                                  :formats '(:plain :markdown)))
