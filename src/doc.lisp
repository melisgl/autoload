(in-package :autoload)

(named-readtables:in-readtable pythonic-string-reader:pythonic-string-syntax)

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

  This library reduces the tension arising from the first two
  considerations by letting heavy dependencies be loaded on demand.
  The core idea is

  ```
  (defmacro autoload (name asdf-system)
    `(defun ,name (&rest args)
       (asdf:load-system ,asdf-system)
       (apply ',name args)))
  ```

  Suppose we have a library called `my-lib` that autoloads
  `my-lib/full`. In `my-lib`, we could use [AUTOLOAD][pax:dislocated]
  as

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

  However, manually keeping the @LOADDEFs (e.g. the AUTOLOAD form
  above) in sync with the definitions is fragile, so we introduce the
  DEFUN/AUTO @AUTODEF to mark autoloaded functions in the
  `my-lib/full` system:

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

  This is implemented by loading the @AUTO-DEPENDS-ON of `my-lib` and
  recording DEFUN/AUTOs. EXTRACT-LOADDEFS is a low-level utility used
  by [RECORD-LOADDEFS][ function], which writes its results to the
  system's @AUTO-LOADDEFS, `"loaddefs.lisp"` in the above example.
  So, all we need to do is call it to regenerate the loaddefs file:

  ```
  (record-loaddefs "my-lib")
  ```

  To prevent the loaddefs file from getting out of sync with the
  definitions, ASDF:TEST-SYSTEM calls CHECK-LOADDEFS by default.

  ASDF, and by extension @QUICKLISP, doesn't know about the declared
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

(dref:define-restart record-loaddefs ()
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
