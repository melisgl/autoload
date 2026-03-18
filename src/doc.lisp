(in-package :autoload)

(pax:defsection @autoload-manual (:title "Autoload Manual" :export nil)
  (@links-and-systems pax:section)
  (@api pax:section)
  (@asdf-integration pax:section))

(pax:defsection @links-and-systems (:title "Links and Systems" :export nil)
  "Here is the [official
  repository](https://github.com/melisgl/autoload/) and the [HTML
  documentation](http://melisgl.github.io/mgl-pax-world/autoload.html)
  for the latest version."
  ("autoload" asdf:system)
  ("autoload-doc" asdf:system))

(pax:defsection @api (:title "API" :export nil)
  (autoload pax:macro)
  (function-autoload-p function)
  (defun/autoloaded pax:macro)
  (defvar/autoloaded pax:macro))

(pax:defsection @asdf-integration (:title "ASDF Integration" :export nil)
  (autoload-system class)
  (system-autoloaded-systems (pax:reader autoload-system))
  (autoloaded-systems function))


;;;; Register in PAX World

(defun autoload-sections ()
  (list @autoload-manual))

(defun autoload-pages ()
  `((:objects
     (, @autoload-manual)
     :source-uri-fn ,(pax:make-github-source-uri-fn
                      "autoload" "https://github.com/melisgl/autoload"))))

(pax:register-doc-in-pax-world :autoload (autoload-sections) (autoload-pages))


#+nil
(progn
  (asdf:load-system "autoload-doc")
  (pax:update-asdf-system-readmes @autoload-manual "autoload"
                                  :formats '(:plain :markdown)))
