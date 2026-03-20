<a id="x-28AUTOLOAD-3A-40AUTOLOAD-MANUAL-20MGL-PAX-3ASECTION-29"></a>

# Autoload Manual

## Table of Contents

- [1 Links and Systems][d60b]
- [2 Basics][fa90]
- [3 ASDF Integration][0c5c]
    - [3.1 Generating Autoloads][48d3]

###### \[in package AUTOLOAD\]
<a id="x-28AUTOLOAD-3A-40LINKS-AND-SYSTEMS-20MGL-PAX-3ASECTION-29"></a>

## 1 Links and Systems

Here is the [official
repository](https://github.com/melisgl/autoload/) and the [HTML
documentation](http://melisgl.github.io/mgl-pax-world/autoload.html)
for the latest version.

<a id="x-28-22autoload-22-20ASDF-2FSYSTEM-3ASYSTEM-29"></a>

- [system] **"autoload"**

    - _Version:_ 0.0.1
    - _Description:_ An ASDF autoloading facility. See
        [Autoload Manual][6caf].
    - _Licence:_ MIT, see COPYING.
    - _Author:_ Gábor Melis
    - _Mailto:_ [mega@retes.hu](mailto:mega@retes.hu)
    - _Homepage:_ [http://github.com/melisgl/autoload](http://github.com/melisgl/autoload)
    - _Bug tracker:_ [https://github.com/melisgl/autoload/issues](https://github.com/melisgl/autoload/issues)
    - _Source control:_ [GIT](https://github.com/melisgl/autoload.git)

<a id="x-28-22autoload-doc-22-20ASDF-2FSYSTEM-3ASYSTEM-29"></a>

- [system] **"autoload-doc"**

    - _Description:_ Parts of [`autoload`][5968] that depend on
        `mgl-pax`. This is a separate system because
        `mgl-pax-bootstrap` depends on [`autoload`][7da0]. Note that
        `mgl-pax/navigate` and
        `mgl-pax/document` depend on this system, which
        renders most of this an implementation detail.
    - *Depends on:* [autoload][5968], mgl-pax

<a id="x-28AUTOLOAD-3A-40BASICS-20MGL-PAX-3ASECTION-29"></a>

## 2 Basics

<a id="x-28AUTOLOAD-3AAUTOLOAD-20MGL-PAX-3AMACRO-29"></a>

- [macro] **AUTOLOAD** *NAME ASDF-SYSTEM-NAME &KEY (LAMBDA-LIST NIL) (DOCSTRING NIL)*

    Define a stub function with `NAME` to load
    `ASDF-SYSTEM-NAME` and return `NAME`. The arguments are not evaluated.
    If `NAME` has a [function definition][eea4] and it is
    not [`FUNCTION-AUTOLOAD-P`][57ad], then do nothing and return `NIL`.
    
    The stub is not defined at [compile time][27c6], which matches
    the required semantics of [`DEFUN`][f472]. `NAME` is [`DECLAIM`][ebea]ed with [`FTYPE`][05c1]
    `FUNCTION`([`0`][119e] [`1`][81f7]) and [`NOTINLINE`][9514].
    
    - The stub is defined with `DOCSTRING` if specified, else with a
      generic docstring that says what system it autoloads.
    
    - For introspective purposes only, the stub's arglist is set to
      `LAMBDA-LIST` if specified and it's supported on the
      platform (currently only SBCL). The arglist is shown by e.g.
      [SLIME autodoc][d78c] and returned by `DREF:ARGLIST`.
    
    Consistency checks:
    
    - The autoloaded system is expected to redefine `NAME`. If it doesn't,
      then an error will be signalled. If `NAME` is redefined but not with
      [`DEFUN/AUTOLOADED`][3b15], then a warning is signalled.
    
    - When the `AUTOLOAD` form is macroexpanded in the process of ASDF
      compilation or load of an [`AUTOLOAD-SYSTEM`][cd2d], a warning is emitted if
      `ASDF-SYSTEM-NAME` is not among the declared
      [`SYSTEM-AUTOLOADED-SYSTEMS`][8429] of that system.

<a id="x-28AUTOLOAD-3AFUNCTION-AUTOLOAD-P-20FUNCTION-29"></a>

- [function] **FUNCTION-AUTOLOAD-P** *NAME*

    See if `NAME`'s function definition is an autoloader function
    established by [`AUTOLOAD`][7da0].

<a id="x-28AUTOLOAD-3ADEFUN-2FAUTOLOADED-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFUN/AUTOLOADED** *NAME LAMBDA-LIST &BODY BODY*

    Like [`DEFUN`][f472], but silence redefinition warnings. Also, warn if `NAME`
    does not denote a function or it was never [`FUNCTION-AUTOLOAD-P`][57ad].

<a id="x-28AUTOLOAD-3ADEFVAR-2FAUTOLOADED-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFVAR/AUTOLOADED** *VAR &OPTIONAL (VAL NIL) (DOC NIL)*

    Like [`DEFVAR`][7334], but works with the global binding on Lisps that
    support it (currently Allegro, CCL, ECL, SBCL). This is to
    handle the case when a system that uses `DEFVAR` with a default value
    is autoloaded while that variable is locally bound:
    
    ```common-lisp
    ;; Some base system only foreshadows *X*.
    (declaim (special *x*))
    (let ((*x* 1))
      ;; Imagine that the system that defines *X* is autoloaded here.
      (defvar/autoloaded *x* 2)
      *x*)
    => 1
    ```

<a id="x-28AUTOLOAD-3A-40ASDF-INTEGRATION-20MGL-PAX-3ASECTION-29"></a>

## 3 ASDF Integration

<a id="x-28AUTOLOAD-3AAUTOLOAD-SYSTEM-20CLASS-29"></a>

- [class] **AUTOLOAD-SYSTEM** *ASDF/SYSTEM:SYSTEM*

    Inheriting from this class in your `ASDF:DEFSYSTEM`
    form enables the features documented in the reader methods. Consider
    the following example.
    
    ```
    (asdf:defsystem "my-system"
      :defsystem-depends-on ("autoload")
      :class "autoload:autoload-system"
      :autoloaded-systems ("dyndep")
      :record-autoloads ("autoloads.lisp" :package #:my-pkg)
      :components ((:file "package")
                   (:file "autoloads")
                   ...))
    ```
    
    With the above,
    
    - It is an error if an [`AUTOLOAD`][7da0] refers to a
      system other than `dyndep`.
    
    - `(`[`RECORD-SYSTEM-AUTOLOADS`][dceb] `"my-system")` will update
      `autoloads.lisp`.
    
    - `(``ASDF:TEST-SYSTEM` `"my-system")` [checks][4afe] that `autoload.lisp` is up-to-date.

<a id="x-28AUTOLOAD-3ASYSTEM-AUTOLOADED-SYSTEMS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29"></a>

- [reader] **SYSTEM-AUTOLOADED-SYSTEMS** *[AUTOLOAD-SYSTEM][cd2d] (:AUTOLOADED-SYSTEMS = NIL)*

    Return the list of the names of systems declared
    to be autoloaded directly by this system. The names are
    canonicalized with `ASDF:COERCE-NAME`. In [`AUTOLOAD-SYSTEM`][cd2d]s,
    [`AUTOLOAD`][7da0] checks that the `ASDF:SYSTEM` to be loaded is
    among those declared.

<a id="x-28AUTOLOAD-3ASYSTEM-RECORD-AUTOLOADS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29"></a>

- [reader] **SYSTEM-RECORD-AUTOLOADS** *[AUTOLOAD-SYSTEM][cd2d] (:RECORD-AUTOLOADS = NIL)*

    This specifies where the automatically extracted
    autoload forms shall be written by [`RECORD-SYSTEM-AUTOLOADS`][dceb].

<a id="x-28AUTOLOAD-3ASYSTEM-TEST-AUTOLOADS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29"></a>

- [reader] **SYSTEM-TEST-AUTOLOADS** *[AUTOLOAD-SYSTEM][cd2d] (:TEST-AUTOLOADS = T)*

    Specifies whether [`CHECK-SYSTEM-AUTOLOADS`][4afe] shall be
    invoked on `ASDF:TEST-OP`.

<a id="x-28AUTOLOAD-3AAUTOLOADED-SYSTEMS-20FUNCTION-29"></a>

- [function] **AUTOLOADED-SYSTEMS** *SYSTEM &KEY (FOLLOW-AUTOLOADED T) INSTALLER*

    Return the list of the names of systems that may be autoloaded by
    `SYSTEM` or any of its normal dependencies (the transitive closure of
    its `:DEPENDS-ON`). This works even if `SYSTEM` is not an
    [`AUTOLOAD-SYSTEM`][cd2d].
    
    - If `FOLLOW-AUTOLOADED`, look further for autoloaded systems among
      the normal and autoloaded dependencies of any autoloaded systems
      found. If an autoloaded system is not installed (i.e.
      `ASDF:FIND-SYSTEM` fails), then that system is not followed.
    
    - If `INSTALLER` is non-`NIL`, it is called when a system encounteres a
      system that is not installed. This is an autoloaded system if
      normal ASDF dependencies are installed as is the case with e.g.
      [Quicklisp][ae25]. `INSTALLER` is passed a single argument, the name of the
      system to be installed, and it may or may not install the system.
    
        The following example, makes sure that all normal and autoloaded
        dependencies (direct or indirect) of `my-system` are installed:
    
            (autoloaded-systems "my-system" :installer #'ql:quickload)

<a id="x-28AUTOLOAD-3A-40GENERATING-AUTOLOADS-20MGL-PAX-3ASECTION-29"></a>

### 3.1 Generating Autoloads

<a id="x-28AUTOLOAD-3AAUTOLOADS-20FUNCTION-29"></a>

- [function] **AUTOLOADS** *SYSTEM &KEY (LAMBDA-LISTS T) (DOCSTRINGS T) EXPORTS*

    Return a list of forms that set up autoloading for definitions such
    as [`DEFUN/AUTOLOADED`][3b15] in [autoloaded direct dependencies][8429] of `SYSTEM`. For `DEFUN/AUTOLOADED`, this is
    an [`AUTOLOAD`][7da0] form; for [`DEFVAR/AUTOLOADED`][453a], this is a
    [`DECLAIM`][ebea] [`SPECIAL`][0bd4].
    
    - If `LAMBDA-LISTS`, then the autoload forms will pass the `LAMBDA-LIST`
      argument of the corresponding `DEFUN/AUTOLOADED` to `AUTOLOAD`.
    
    - If `DOCSTRINGS`, then the docstrings extracted from `DEFUN/AUTOLOADED`
      or `DEFVAR/AUTOLOADED` will be associated with the definition.
    
    - If `EXPORTS`, then emit [`EXPORT`][0c4f] forms for symbolic names that are
      exported from their [home package][407c].
    
    Note that this is an expensive operation, as it reloads the direct
    dependencies one by one with `ASDF:LOAD-SYSTEM` `:FORCE` and records the
    association with the system and the autoloaded definitions such as
    `DEFUN/AUTOLOADED`.

<a id="x-28AUTOLOAD-3AWRITE-AUTOLOADS-20FUNCTION-29"></a>

- [function] **WRITE-AUTOLOADS** *FORMS STREAM &KEY PACKAGE*

    Write the autoload `FORMS` to `STREAM` that can be [`LOAD`][b5ec]ed. When
    `PACKAGE`, emit an [`IN-PACKAGE`][125e] form with its name, and print the forms
    with [`*PACKAGE*`][5ed1] bound to it.

<a id="x-28AUTOLOAD-3ARECORD-SYSTEM-AUTOLOADS-20FUNCTION-29"></a>

- [function] **RECORD-SYSTEM-AUTOLOADS** *SYSTEM*

    Write the [`AUTOLOADS`][1e20] of `SYSTEM` to the file in its
    [`:RECORD-AUTOLOADS`][f945], which may be a
    [pathname designator][3914] or a list of the form
    
        (pathname &key (lambda-lists t) (docstrings t) package exports)
    
    See [`AUTOLOADS`][7da0] and [`WRITE-AUTOLOADS`][3140] for the description
    of these arguments. `PATHNAME`([`0`][0317] [`1`][6671]) is relative to
    `ASDF:SYSTEM-SOURCE-DIRECTORY` of `SYSTEM` and is [`OPEN`][6547]ed with `:IF-EXISTS`
    `:SUPERSEDE`.

<a id="x-28AUTOLOAD-3ACHECK-SYSTEM-AUTOLOADS-20FUNCTION-29"></a>

- [function] **CHECK-SYSTEM-AUTOLOADS** *SYSTEM &KEY (ERRORP T)*

    In the [`AUTOLOAD-SYSTEM`][cd2d] `SYSTEM`, check that there is a
    [`:RECORD-AUTOLOADS`][f945] and the file generated
    by [`RECORD-SYSTEM-AUTOLOADS`][dceb] is up-to-date. If `ERRORP`, then signal an
    error if it is not.
    
    This compares the current [`AUTOLOADS`][1e20] to those in the file with [`EQUAL`][3fb5]
    and is thus sensitive to the order of definitions.
    
    This function is called automatically by `ASDF:TEST-OP` on a
    `AUTOLOAD-SYSTEM` from a `:BEFORE` method.

  [0317]: http://www.lispworks.com/documentation/HyperSpec/Body/t_pn.htm "PATHNAME (MGL-PAX:CLHS CLASS)"
  [05c1]: http://www.lispworks.com/documentation/HyperSpec/Body/d_ftype.htm "FTYPE (MGL-PAX:CLHS DECLARATION)"
  [0bd4]: http://www.lispworks.com/documentation/HyperSpec/Body/d_specia.htm "SPECIAL (MGL-PAX:CLHS DECLARATION)"
  [0c4f]: http://www.lispworks.com/documentation/HyperSpec/Body/f_export.htm "EXPORT (MGL-PAX:CLHS FUNCTION)"
  [0c5c]: #x-28AUTOLOAD-3A-40ASDF-INTEGRATION-20MGL-PAX-3ASECTION-29 "ASDF Integration"
  [119e]: http://www.lispworks.com/documentation/HyperSpec/Body/t_fn.htm "FUNCTION (MGL-PAX:CLHS CLASS)"
  [125e]: http://www.lispworks.com/documentation/HyperSpec/Body/m_in_pkg.htm "IN-PACKAGE (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [1e20]: #x-28AUTOLOAD-3AAUTOLOADS-20FUNCTION-29 "AUTOLOAD:AUTOLOADS FUNCTION"
  [27c6]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_c.htm#compile_time "\"compile time\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [3140]: #x-28AUTOLOAD-3AWRITE-AUTOLOADS-20FUNCTION-29 "AUTOLOAD:WRITE-AUTOLOADS FUNCTION"
  [3914]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_p.htm#pathname_designator "\"pathname designator\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [3b15]: #x-28AUTOLOAD-3ADEFUN-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFUN/AUTOLOADED MGL-PAX:MACRO"
  [3fb5]: http://www.lispworks.com/documentation/HyperSpec/Body/f_equal.htm "EQUAL (MGL-PAX:CLHS FUNCTION)"
  [407c]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_h.htm#home_package "\"home package\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [453a]: #x-28AUTOLOAD-3ADEFVAR-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFVAR/AUTOLOADED MGL-PAX:MACRO"
  [48d3]: #x-28AUTOLOAD-3A-40GENERATING-AUTOLOADS-20MGL-PAX-3ASECTION-29 "Generating Autoloads"
  [4afe]: #x-28AUTOLOAD-3ACHECK-SYSTEM-AUTOLOADS-20FUNCTION-29 "AUTOLOAD:CHECK-SYSTEM-AUTOLOADS FUNCTION"
  [57ad]: #x-28AUTOLOAD-3AFUNCTION-AUTOLOAD-P-20FUNCTION-29 "AUTOLOAD:FUNCTION-AUTOLOAD-P FUNCTION"
  [5968]: #x-28-22autoload-22-20ASDF-2FSYSTEM-3ASYSTEM-29 "\"autoload\" ASDF/SYSTEM:SYSTEM"
  [5ed1]: http://www.lispworks.com/documentation/HyperSpec/Body/v_pkg.htm "*PACKAGE* (MGL-PAX:CLHS VARIABLE)"
  [6547]: http://www.lispworks.com/documentation/HyperSpec/Body/f_open.htm "OPEN (MGL-PAX:CLHS FUNCTION)"
  [6671]: http://www.lispworks.com/documentation/HyperSpec/Body/f_pn.htm "PATHNAME (MGL-PAX:CLHS FUNCTION)"
  [6caf]: #x-28AUTOLOAD-3A-40AUTOLOAD-MANUAL-20MGL-PAX-3ASECTION-29 "Autoload Manual"
  [7334]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defpar.htm "DEFVAR (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [7da0]: #x-28AUTOLOAD-3AAUTOLOAD-20MGL-PAX-3AMACRO-29 "AUTOLOAD:AUTOLOAD MGL-PAX:MACRO"
  [81f7]: http://www.lispworks.com/documentation/HyperSpec/Body/s_fn.htm "FUNCTION (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [8429]: #x-28AUTOLOAD-3ASYSTEM-AUTOLOADED-SYSTEMS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29 "AUTOLOAD:SYSTEM-AUTOLOADED-SYSTEMS (MGL-PAX:READER AUTOLOAD:AUTOLOAD-SYSTEM)"
  [9514]: http://www.lispworks.com/documentation/HyperSpec/Body/d_inline.htm "NOTINLINE (MGL-PAX:CLHS DECLARATION)"
  [ae25]: https://www.quicklisp.org/ "Quicklisp"
  [b5ec]: http://www.lispworks.com/documentation/HyperSpec/Body/f_load.htm "LOAD (MGL-PAX:CLHS FUNCTION)"
  [cd2d]: #x-28AUTOLOAD-3AAUTOLOAD-SYSTEM-20CLASS-29 "AUTOLOAD:AUTOLOAD-SYSTEM CLASS"
  [d60b]: #x-28AUTOLOAD-3A-40LINKS-AND-SYSTEMS-20MGL-PAX-3ASECTION-29 "Links and Systems"
  [d78c]: https://slime.common-lisp.dev/doc/html/slime_002dautodoc_002dmode.html#slime_002dautodoc_002dmode "SLIME autodoc"
  [dceb]: #x-28AUTOLOAD-3ARECORD-SYSTEM-AUTOLOADS-20FUNCTION-29 "AUTOLOAD:RECORD-SYSTEM-AUTOLOADS FUNCTION"
  [ebea]: http://www.lispworks.com/documentation/HyperSpec/Body/m_declai.htm "DECLAIM (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [eea4]: http://www.lispworks.com/documentation/HyperSpec/Body/f_fdefin.htm "FDEFINITION (MGL-PAX:CLHS FUNCTION)"
  [f472]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defun.htm "DEFUN (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [f945]: #x-28AUTOLOAD-3ASYSTEM-RECORD-AUTOLOADS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29 "AUTOLOAD:SYSTEM-RECORD-AUTOLOADS (MGL-PAX:READER AUTOLOAD:AUTOLOAD-SYSTEM)"
  [fa90]: #x-28AUTOLOAD-3A-40BASICS-20MGL-PAX-3ASECTION-29 "Basics"

* * *
###### \[generated by [MGL-PAX](https://github.com/melisgl/mgl-pax)\]
