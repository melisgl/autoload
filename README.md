<a id="x-28AUTOLOAD-3A-40AUTOLOAD-MANUAL-20MGL-PAX-3ASECTION-29"></a>

# Autoload Manual

## Table of Contents

- [1 Links and Systems][d60b]
- [2 API][706f]
- [3 ASDF Integration][0c5c]

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
    - _Description:_ Bare-bones autoloading facility. See
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
        `mgl-pax`. This is split off `autoload` because `mgl-pax-bootstrap` depends
        on `autoload`. Note that `mgl-pax/navigate` and
        `mgl-pax/document` depend on this system, which
        renders most of this an implementation detail.
    - *Depends on:* [autoload][5968], mgl-pax

<a id="x-28AUTOLOAD-3A-40API-20MGL-PAX-3ASECTION-29"></a>

## 2 API

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

    Inherit from this class in your `ASDF:DEFSYSTEM` form
    to be able to specify the list of systems autoloaded by the system
    being defined, against which [`AUTOLOAD`][7da0]s are then
    checked.
    
    ```
    (asdf:defsystem "some-system"
      :defsystem-depends-on ("autoload")
      :class "autoload:autoload-system"
      :autoloaded-systems ("other-system"))
    ```

<a id="x-28AUTOLOAD-3ASYSTEM-AUTOLOADED-SYSTEMS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29"></a>

- [reader] **SYSTEM-AUTOLOADED-SYSTEMS** *[AUTOLOAD-SYSTEM][cd2d] (:AUTOLOADED-SYSTEMS = NIL)*

    Return the list of the names of systems autoloaded
    directly by this system. The names are canonicalized with
    `ASDF:COERCE-NAME`.

<a id="x-28AUTOLOAD-3AAUTOLOADED-SYSTEMS-20FUNCTION-29"></a>

- [function] **AUTOLOADED-SYSTEMS** *SYSTEM &KEY (FOLLOW-AUTOLOADED T)*

    Return the list of the names of systems that may be autoloaded by
    `SYSTEM` or any of its normal dependencies (the transitive closure of
    its `:DEPENDS-ON`). This works even if `SYSTEM` is not an
    [`AUTOLOAD-SYSTEM`][cd2d].
    
    If `FOLLOW-AUTOLOADED`, look further for autoloaded systems among the
    normal and autoloaded dependencies of any autoloaded systems found.
    If an autoloaded system is not installed (i.e. `ASDF:FIND-SYSTEM`
    fails), then that system is not followed.

  [05c1]: http://www.lispworks.com/documentation/HyperSpec/Body/d_ftype.htm "FTYPE (MGL-PAX:CLHS DECLARATION)"
  [0c5c]: #x-28AUTOLOAD-3A-40ASDF-INTEGRATION-20MGL-PAX-3ASECTION-29 "ASDF Integration"
  [119e]: http://www.lispworks.com/documentation/HyperSpec/Body/t_fn.htm "FUNCTION (MGL-PAX:CLHS CLASS)"
  [27c6]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_c.htm#compile_time "\"compile time\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [3b15]: #x-28AUTOLOAD-3ADEFUN-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFUN/AUTOLOADED MGL-PAX:MACRO"
  [57ad]: #x-28AUTOLOAD-3AFUNCTION-AUTOLOAD-P-20FUNCTION-29 "AUTOLOAD:FUNCTION-AUTOLOAD-P FUNCTION"
  [5968]: #x-28-22autoload-22-20ASDF-2FSYSTEM-3ASYSTEM-29 "\"autoload\" ASDF/SYSTEM:SYSTEM"
  [6caf]: #x-28AUTOLOAD-3A-40AUTOLOAD-MANUAL-20MGL-PAX-3ASECTION-29 "Autoload Manual"
  [706f]: #x-28AUTOLOAD-3A-40API-20MGL-PAX-3ASECTION-29 "API"
  [7334]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defpar.htm "DEFVAR (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [7da0]: #x-28AUTOLOAD-3AAUTOLOAD-20MGL-PAX-3AMACRO-29 "AUTOLOAD:AUTOLOAD MGL-PAX:MACRO"
  [81f7]: http://www.lispworks.com/documentation/HyperSpec/Body/s_fn.htm "FUNCTION (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [8429]: #x-28AUTOLOAD-3ASYSTEM-AUTOLOADED-SYSTEMS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29 "AUTOLOAD:SYSTEM-AUTOLOADED-SYSTEMS (MGL-PAX:READER AUTOLOAD:AUTOLOAD-SYSTEM)"
  [9514]: http://www.lispworks.com/documentation/HyperSpec/Body/d_inline.htm "NOTINLINE (MGL-PAX:CLHS DECLARATION)"
  [cd2d]: #x-28AUTOLOAD-3AAUTOLOAD-SYSTEM-20CLASS-29 "AUTOLOAD:AUTOLOAD-SYSTEM CLASS"
  [d60b]: #x-28AUTOLOAD-3A-40LINKS-AND-SYSTEMS-20MGL-PAX-3ASECTION-29 "Links and Systems"
  [d78c]: https://slime.common-lisp.dev/doc/html/slime_002dautodoc_002dmode.html#slime_002dautodoc_002dmode "SLIME autodoc"
  [ebea]: http://www.lispworks.com/documentation/HyperSpec/Body/m_declai.htm "DECLAIM (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [eea4]: http://www.lispworks.com/documentation/HyperSpec/Body/f_fdefin.htm "FDEFINITION (MGL-PAX:CLHS FUNCTION)"
  [f472]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defun.htm "DEFUN (MGL-PAX:CLHS MGL-PAX:MACRO)"

* * *
###### \[generated by [MGL-PAX](https://github.com/melisgl/mgl-pax)\]
