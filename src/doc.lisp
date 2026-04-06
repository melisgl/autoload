(in-package :autoload)

(named-readtables:in-readtable pythonic-string-reader:pythonic-string-syntax)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (shadowing-import '(pax:docstring))
  (import '(pax:clhs pax:macro pax:section pax:defsection
            pax:glossary-term pax:note
            pax:reader pax:define-glossary-term pax:make-github-source-uri-fn
            pax:register-doc-in-pax-world dref:define-restart)
          :autoload))

(defsection @autoload-manual (:title "Autoload Manual")
  (@links-and-systems section)
  (@introduction section)
  (@basics section)
  (@asdf-integration section))

(defsection @links-and-systems (:title "Links and Systems")
  "Here is the [official
  repository](https://github.com/melisgl/autoload/) and the [HTML
  documentation](http://melisgl.github.io/mgl-pax-world/autoload.html)
  for the latest version."
  ("autoload" asdf:system)
  ("autoload-doc" asdf:system))

(defsection @introduction (:title "Introduction")
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

  Suppose we have a library called `my-lib` that autoloads
  `my-lib/full`. In `my-lib`, we could use AUTOLOAD as

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

  However, manually keeping the loaddefs (e.g. the AUTOLOAD form
  above) in sync with the definitions is fragile, so instead we mark
  autoloaded functions in the `my-lib/full` system:

  ```
  (defun/auto foo (x)
    "doc"
    (1+ x))
  ```

  and [generate loaddefs][ @automatic-loaddefs] through the
  @ASDF-INTEGRATION:

  ```
  (asdf:defsystem "my-lib"
    :defsystem-depends-on ("autoload")
    :class "autoload:autoload-system"
    :auto-depends-on ("my-lib/full")
    :auto-loaddefs "loaddefs.lisp"
    :components ((:file "loaddefs")
                 ...))
  ```
  ```
  (asdf:defsystem "my-lib/full"
    :defsystem-depends-on ("autoload")
    :class "autoload:autoload-system"
    :components (...))
  ```

  Then, the loaddefs can be extracted:

  ```
  (extract-loaddefs "my-lib")
  => ((autoload foo "my-lib/full" :arglist "(x)" :docstring "doc"))
  ```

  This is implemented by loading the :AUTO-DEPENDS-ON of `my-lib` and
  recording DEFUN/AUTOs. EXTRACT-LOADDEFS is a low-level utility
  used by [RECORD-LOADDEFS][ function], which writes its results to
  the system's @AUTO-LOADDEFS, `"loaddefs.lisp"` in the above example.
  So, all we need to do is call it to regenerate the loaddefs file:

  ```
  (record-loaddefs "my-lib")
  ```

  To prevent the loaddefs file from getting out of sync with the
  definitions, ASDF:TEST-SYSTEM calls CHECK-LOADDEFS by default.

  ASDF, and by extension @QUICKLISP, don't know about the declared
  @AUTO-DEPENDS-ON, so `(QL:QUICKLOAD "my-lib")` does not install the
  autoloaded dependencies. This can be done with

  ```
  (autodeps "my-lib" :installer #'ql:quickload)
  ```

  If all the autoloaded dependencies are installed, one can eagerly
  load them to ensure that autoloading is not triggered later (e.g.
  in deployment):

  ```
  (map nil #'asdf:load-system (autodeps "my-lib"))
  ```
  """)

(defsection @basics (:title "Basics")
  (@autoload glossary-term)
  (@loaddef glossary-term)
  (@auto glossary-term)
  (@loading-systems section)
  (@conditions section)
  (@functions section)
  (@variables section)
  (@packages section))

(define-glossary-term @autoload (:title "autoload")
  "An autoload definition defines a stub that, when used, triggers
  loading of an ASDF:SYSTEM. See AUTOLOAD and AUTOLOAD-CLASS.")

(define-glossary-term @loaddef (:title "loaddef")
  "A loaddef is either an @AUTOLOAD or some other Lisp form that
  foreshadows a definition without setting up autoloading of an
  ASDF:SYSTEM. See DEFVAR/AUTO and DEFPACKAGE/AUTO.")

(define-glossary-term @auto (:title "auto")
  "An auto definition, such as DEFUN/AUTO, DEFGENERIC/AUTO,
  DEFCLASS/AUTO, DEFPACKAGE/AUTO, marks the definition for
  @AUTOMATIC-LOADDEFS and signals an AUTOLOAD-WARNING if there was no
  corresponding @LOADDEF.")

(defsection @loading-systems (:title "Loading Systems")
  """[autoload-system-for function][docstring]""")

(defsection @conditions (:title "Conditions")
  (autoload-error condition)
  (autoload-warning condition))

(defsection @functions (:title "Functions")
  (autoload macro)
  (autoload-fbound-p function)
  (defun/auto macro)
  (defgeneric/auto macro)
  (define-auto-function macro))

(defsection @classes (:title "Classes")
  (autoload-class macro)
  (autoload-class-p function)
  (defclass/auto macro))

(defsection @variables (:title "Variables")
  (defvar/auto macro))

(defsection @packages (:title "Packages")
  (defpackage/auto macro))

(defsection @asdf-integration (:title "ASDF Integration")
  (autoload-system class)
  (autoload-cl-source-file class)
  (system-auto-depends-on (reader autoload-system))
  (system-auto-loaddefs (reader autoload-system))
  (autodeps function)
  (@automatic-loaddefs section))

(defsection @automatic-loaddefs
    (:title "Automatically Generating Loaddefs")
  (extract-loaddefs function)
  (write-loaddefs function)
  (record-loaddefs function)
  (check-loaddefs function)
  (record-loaddefs restart))

(define-restart record-loaddefs ()
  "Provided by CHECK-LOADDEFS and also when the compilation of the
  loaddefs file declared in @AUTO-LOADDEFS fails. The function
  RECORD-LOADDEFS can be used as a condition handler to invoke this
  restart.")

(define-glossary-term @slime-autodoc
    (:title "SLIME autodoc"
     :url "https://slime.common-lisp.dev/doc/html/slime_002dautodoc_002dmode.html#slime_002dautodoc_002dmode"))

(define-glossary-term @quicklisp
    (:title "Quicklisp"
     :url "https://www.quicklisp.org/"))

(note @auto-depends-on
  "[:AUTO-DEPENDS-ON][ system-auto-depends-on (reader autoload-system)]")

(note @auto-loaddefs
  "[:AUTO-LOADDEFS][ system-auto-loaddefs (reader autoload-system)]")


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
