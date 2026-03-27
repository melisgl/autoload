(in-package :autoload)

(named-readtables:in-readtable pythonic-string-reader:pythonic-string-syntax)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (import '(pax:clhs pax:macro pax:section pax:defsection pax:reader
            pax:define-glossary-term pax:make-github-source-uri-fn
            pax:register-doc-in-pax-world dref:define-restart)
          :autoload))

(defsection @autoload-manual (:title "Autoload Manual" :export nil)
  (@links-and-systems section)
  (@introduction section)
  (@basics section)
  (@asdf-integration section))

(defsection @links-and-systems (:title "Links and Systems" :export nil)
  "Here is the [official
  repository](https://github.com/melisgl/autoload/) and the [HTML
  documentation](http://melisgl.github.io/mgl-pax-world/autoload.html)
  for the latest version."
  ("autoload" asdf:system)
  ("autoload-doc" asdf:system))

(defsection @introduction (:title "Introduction" :export nil)
  """Libraries often choose to limit dependencies, even if it means
  sacrificing features or duplicating code, to minimize

  - compilation time,

  - memory usage in deployment, and

  - the risk of breakage through dependencies.

  This library reduces the tension arising from the former two
  considerations by letting heavy dependencies be loaded on demand.
  The core idea is

  ```
  (defmacro autoload (name asdf-system)
    `(defun ,name (&rest args)
       (asdf:load-system ,asdf-system)
       (apply ',name args)))
  ```

  Suppose we have a library called `my-lib` that autoloads `my-lib/full`.
  In `my-lib`, we could use [AUTOLOAD][macro] as

  ```
  (autoload foo "my-lib/full")
  ```

  and have

  ```
  (defun foo (x)
    "doc"
    (1+ x))
  ```

  in `my-lib/full`.

  However, manually keeping the autoload declarations in sync with the
  definitions is fragile, so instead we mark autoloaded functions in
  the `my-lib/full` system:

  ```
  (defun/autoloaded foo (x)
    "doc"
    (1+ x))
  ```

  and [generate autoloads][ @generating-autoloads] through the
  @ASDF-INTEGRATION:

  ```
  (asdf:defsystem "my-lib"
    :defsystem-depends-on ("autoload")
    :class "autoload:autoload-system"
    :autoloaded-systems ("my-lib/full")
    :record-autoloads "autoloads.lisp"
    :components ((:file "autoloads")
                 ...))
  ```
  ```
  (asdf:defsystem "my-lib/full"
    :defsystem-depends-on ("autoload")
    :class "autoload:autoload-system"
    :components (...))
  ```

  Then, the autoloaded definitions can be extracted:

  ```
  (autoloads "my-lib")
  => ((autoload foo :arglist "(x)" :docstring "doc"))
  ```

  This is implemented by loading the :AUTOLOADED-SYSTEMS of `my-lib`
  and recording DEFUN/AUTOLOADEDs. AUTOLOADS is a low-level utility
  used by [RECORD-SYSTEM-AUTOLOADS][ function], which writes its
  results to the system's :RECORD-AUTOLOADS, `"autoloads.lisp"` in the above
  example. So, all we need to do is call it to regenerate the
  autoloads file:

  ```
  (record-system-autoloads "my-lib")
  ```

  To prevent the autoloads file from getting out of sync with the
  definitions, ASDF:TEST-SYSTEM calls CHECK-SYSTEM-AUTOLOADS by
  default.

  ASDF, and by extension @QUICKLISP, don't know about the declared
  :AUTOLOADED-SYSTEMS, so `(QL:QUICKLOAD "my-lib")` does not install
  the autoloaded dependencies. This can be done with

  ```
  (autoloaded-systems "my-lib" :installer #'ql:quickload)
  ```
  """)

(defsection @basics (:title "Basics" :export nil)
  (@functions section)
  (@variables section)
  (@packages section)
  (@conditions section))

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

(defsection @packages (:title "Packages" :export nil)
  (defpackage/autoloaded macro))

(defsection @conditions (:title "Conditions" :export nil)
  (autoload-error condition)
  (autoload-warning condition))

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
  (check-system-autoloads function)
  (record-system-autoloads restart))

(define-restart record-system-autoloads ()
  "Provided by CHECK-SYSTEM-AUTOLOADS and also when the compilation of
  the autoloads file declared in [:RECORD-AUTOLOADS][
  system-record-autoloads (reader autoload-system)] fails. The
  function RECORD-SYSTEM-AUTOLOADS can be used as a condition handler
  to invoke this restart.")

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
