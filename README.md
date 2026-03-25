<a id="x-28AUTOLOAD-3A-40AUTOLOAD-MANUAL-20MGL-PAX-3ASECTION-29"></a>

# Autoload Manual

## Table of Contents

- [1 Links and Systems][d60b]
- [2 Introduction][471f]
- [3 Basics][fa90]
    - [3.1 Functions][4b04]
    - [3.2 Variables][f490]
    - [3.3 Package][643f]
- [4 ASDF Integration][0c5c]
    - [4.1 Generating Autoloads][48d3]

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
    - *Depends on:* [autoload][5968], mgl-pax, named-readtables, pythonic-string-reader

<a id="x-28AUTOLOAD-3A-40INTRODUCTION-20MGL-PAX-3ASECTION-29"></a>

## 2 Introduction

Libraries often choose to limit dependencies, even if it means
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
     (apply 'name args)))
```

Suppose we have a library called `my-lib` that autoloads `my-lib/full`.
In `my-lib`, we could use [`AUTOLOAD`][7da0] as

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

and [generate autoloads][48d3] through the
[ASDF Integration][0c5c]:

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

This is implemented by loading the `:AUTOLOADED-SYSTEMS` of `my-lib`
and recording [`DEFUN/AUTOLOADED`][3b15]s. [`AUTOLOADS`][1e20] is a low-level utility
used by [`RECORD-SYSTEM-AUTOLOADS`][dceb] that writes its results to the
system's `:RECORD-AUTOLOADS`, `"autoloads.lisp"` in the above example.
So, all we need to do is to call it regenarate the autoloads file:

```
(record-system-autoloads "my-lib")
```

To prevent the autoloads file from getting out of sync with the
definitions, `ASDF:TEST-SYSTEM` calls [`CHECK-SYSTEM-AUTOLOADS`][4afe] by
default.

ASDF and by extension [Quicklisp][ae25] don't know about the declared
`:AUTOLOADED-SYSTEMS`, so `(``QL:QUICKLOAD` `"my-lib")` does not install
the autoloaded dependencies. This can be done with

```
(autoloaded-systems "my-lib" :installer #'ql:quickload)
```


<a id="x-28AUTOLOAD-3A-40BASICS-20MGL-PAX-3ASECTION-29"></a>

## 3 Basics

<a id="x-28AUTOLOAD-3AAUTOLOAD-WARNING-20CONDITION-29"></a>

- [condition] **AUTOLOAD-WARNING** *[SIMPLE-WARNING][fc62]*

    Signalled when inconsistencies are detected by e.g.
    [`AUTOLOAD`][7da0] and [`DEFVAR/AUTOLOADED`][453a].

<a id="x-28AUTOLOAD-3A-40FUNCTIONS-20MGL-PAX-3ASECTION-29"></a>

### 3.1 Functions

<a id="x-28AUTOLOAD-3AAUTOLOAD-20MGL-PAX-3AMACRO-29"></a>

- [macro] **AUTOLOAD** *NAME ASDF-SYSTEM-NAME &KEY (ARGLIST NIL) (DOCSTRING NIL) (EXPLICITP T)*

    Define a stub function with `NAME` to load
    `ASDF-SYSTEM-NAME` and return `NAME`. The arguments are not evaluated.
    If `NAME` has a [function definition][eea4] and it is not
    [`FUNCTION-AUTOLOAD-P`][57ad], then do nothing and return `NIL`.
    
    The stub is not defined at [compile time][27c6], which matches the
    required semantics of [`DEFUN`][f472]. `NAME` is [`DECLAIM`][ebea]ed with [`FTYPE`][05c1] `FUNCTION`([`0`][119e] [`1`][81f7])
    and [`NOTINLINE`][9514].
    
    - `ARGLIST` will be installed as the stub's arglist if specified and
      it's supported on the platform (currently only SBCL). If `ARGLIST`
      is a string, then the effective value of `ARGLIST` is then read from
      it. If the read fails, an [`AUTOLOAD-WARNING`][da95] is signalled and
      processing continues as if `ARGLIST` had not been provided.
    
        Arglists are for interactive purposes only. For example, they
        are shown by [SLIME autodoc][d78c] and returned by `DREF:ARGLIST`.
    
    - `DOCSTRING`, if specified, will be the stub's docstring. If not
      specified, a generic docstring that says what system it autoloads
      will be used.
    
    - `EXPLICITP` `T` indicates that `ASDF-SYSTEM-NAME` will redefine `NAME` by
      one of [`DEFUN/AUTOLOADED`][3b15], [`DEFGENERIC/AUTOLOADED`][8b6e] or
      [`DEFINE-AUTOLOADED-FUNCTION`][24b9]. `EXPLICITP` `NIL` indicates that the
      redefinition will use another mechanism (e.g. a `DEFUN`, as a
      [`DEFCLASS`][ead6] accessor, or even a `(`[`SETF`][a138] `FDEFINITION``)`).
    
    Thus, the system `ASDF-SYSTEM-NAME` is expected to redefine the
    function `NAME`. After loading it, the following checks are made.
    
    - It is an error if `NAME` is not redefined at all.
    
    - It is an `AUTOLOAD-WARNING` if `NAME` is redefined with another
      [`AUTOLOAD`][7da0].
    
    - It is an `AUTOLOAD-WARNING` if the promise of `EXPLICITP` is broken,
      as it indicates confusion whether [Generating Autoloads][48d3] should be
      done automatically or not.
    
    Also, see [`SYSTEM-AUTOLOADED-SYSTEMS`][8429] for
    further consistency checking.

<a id="x-28AUTOLOAD-3AFUNCTION-AUTOLOAD-P-20FUNCTION-29"></a>

- [function] **FUNCTION-AUTOLOAD-P** *NAME*

    See if `NAME`'s function definition is an autoloader function
    established by [`AUTOLOAD`][7da0].

<a id="x-28AUTOLOAD-3ADEFUN-2FAUTOLOADED-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFUN/AUTOLOADED** *NAME LAMBDA-LIST &BODY BODY*

    Like [`DEFUN`][f472], but mark the function for automatically
    [Generating Autoloads][48d3] and silence redefinition warnings. Also, warn
    if `NAME` has never been [`FUNCTION-AUTOLOAD-P`][57ad].

<a id="x-28AUTOLOAD-3ADEFGENERIC-2FAUTOLOADED-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFGENERIC/AUTOLOADED** *NAME LAMBDA-LIST &BODY BODY*

    Like [`DEFUN/AUTOLOADED`][3b15], but define `NAME` with [`DEFGENERIC`][c7f7].

<a id="x-28AUTOLOAD-3ADEFINE-AUTOLOADED-FUNCTION-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFINE-AUTOLOADED-FUNCTION** *DEFINER NAME LAMBDA-LIST &BODY BODY*

    Like [`DEFUN/AUTOLOADED`][3b15], but establish a function binding for `NAME`
    with `DEFINER`. For example, the autoloaded counterpart to `UIOP:DEFUN*`
    can be defined as
    
        (defmacro defun*/autoloaded (name lambda-list &body body)
          `(define-autoloaded-function uiop:defun* ,name ,lambda-list ,@body))

<a id="x-28AUTOLOAD-3A-40VARIABLES-20MGL-PAX-3ASECTION-29"></a>

### 3.2 Variables

<a id="x-28AUTOLOAD-3ADECLARE-VARIABLE-AUTOLOAD-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DECLARE-VARIABLE-AUTOLOAD** *VAR &KEY (INIT NIL) DOCSTRING*

    Define `VAR` with [`DEFVAR`][7334] and mark it as [`VARIABLE-AUTOLOAD-P`][1dd6].
    
    - Depending on whether `INIT` is specified, `(DEFVAR <VAR>
      <init>)` or `(DEFVAR <VAR>)` is executed.
    
    - If `DOCSTRING` is non-`NIL`, then the [`DOCUMENTATION`][c5ae] of `VAR` as a
      `VARIABLE` is set to it.
    
    Note that on accessing `VAR`, nothing is autoloaded.
    `DECLARE-VARIABLE-AUTOLOAD` is solely to allow [`DEFVAR/AUTOLOADED`][453a] to
    perform some checking.

<a id="x-28AUTOLOAD-3AVARIABLE-AUTOLOAD-P-20FUNCTION-29"></a>

- [function] **VARIABLE-AUTOLOAD-P** *NAME*

    See if `NAME` has been declared with [`DECLARE-VARIABLE-AUTOLOAD`][c5d0] and
    not defined with [`DEFVAR/AUTOLOADED`][453a] since.

<a id="x-28AUTOLOAD-3ADEFVAR-2FAUTOLOADED-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFVAR/AUTOLOADED** *VAR &OPTIONAL (VAL NIL) DOC*

    Like [`DEFVAR`][7334], but mark the variable for automatically
    [Generating Autoloads][48d3].
    
    Also, this works with the *global* binding on Lisps that support
    it (currently Allegro, CCL, ECL, SBCL). This is to handle the case
    when a system that uses `DEFVAR` with a default value is autoloaded
    while that variable is locally bound:
    
    ```common-lisp
    ;; Some base system only foreshadows *X*.
    (declaim (special *x*))
    (let ((*x* 1))
      ;; Imagine that the system that defines *X* is autoloaded here.
      (defvar/autoloaded *x* 2)
      *x*)
    => 1
    ```
    
    `DEFVAR/AUTOLOADED` warns if `VAR` has never been [`VARIABLE-AUTOLOAD-P`][1dd6].

<a id="x-28AUTOLOAD-3A-40PACKAGES-20MGL-PAX-3ASECTION-29"></a>

### 3.3 Package

<a id="x-28AUTOLOAD-3ADEFPACKAGE-2FAUTOLOADED-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFPACKAGE/AUTOLOADED** *NAME &REST OPTIONS*

    Like [`DEFPACKAGE`][9b43], but mark the package for [Generating Autoloads][48d3]
    automatically and extend the existing definition additively.
    
    The additivity means that instead of replacing the package
    definition or signaling errors on redefinition, it expands into
    individual package-altering operations such as [`SHADOW`][d0c4], [`USE-PACKAGE`][2264]
    and [`EXPORT`][0c4f]. This allows the package state to be built incrementally.
    `DEFPACKAGE/AUTOLOADED` may be used on the same package multiple
    times.
    
    In addition, `DEFPACKAGE/AUTOLOADED` deviates from `DEFPACKAGE` in the
    following ways.
    
    - The default `:USE` list is empty.
    
    - `:SIZE` is not supported.
    
    - Implementation-specific extensions such as `:LOCAL-NICKNAMES` are
      not supported. Use `ADD-PACKAGE-LOCAL-NICKNAMES` after the
      `DEFPACKAGE/AUTOLOADED`.
    
    Alternatively, one may use, for example, `DEFPACKAGE` or
    `UIOP:DEFINE-PACKAGE` and arrange for [Generating Autoloads][48d3] for the
    package by listing it in `:PACKAGES` of
    [`SYSTEM-RECORD-AUTOLOADS`][f945].

<a id="x-28AUTOLOAD-3A-40ASDF-INTEGRATION-20MGL-PAX-3ASECTION-29"></a>

## 4 ASDF Integration

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
      :record-autoloads "autoloads.lisp"
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
    
    If the package definitions are also generated with
    `RECORD-SYSTEM-AUTOLOADS` (e.g. because there is a
    [`DEFPACKAGE/AUTOLOADED`][990a] in `dyndep` or `:RECORD-AUTOLOADS` specifies
    `:PACKAGES`), then we can do without the `package.lisp` file:
    
    ```
    (asdf:defsystem "my-system"
      :defsystem-depends-on ("autoload")
      :class "autoload:autoload-system"
      :autoloaded-systems ("dyndep")
      :record-autoloads ("autoloads.lisp" :packages #:my-pkg)
      :components ((:file "autoloads")
                   ...))
    ```

<a id="x-28AUTOLOAD-3ASYSTEM-AUTOLOADED-SYSTEMS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29"></a>

- [reader] **SYSTEM-AUTOLOADED-SYSTEMS** *[AUTOLOAD-SYSTEM][cd2d] (:AUTOLOADED-SYSTEMS = NIL)*

    Return the list of the names of systems declared
    to be autoloaded directly by this system. The names are
    canonicalized with `ASDF:COERCE-NAME`. In [`AUTOLOAD-SYSTEM`][cd2d]s,
    [`AUTOLOAD`][7da0] signals an error if the `ASDF:SYSTEM` to be loaded
    is among those declared here.

<a id="x-28AUTOLOAD-3ASYSTEM-RECORD-AUTOLOADS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29"></a>

- [reader] **SYSTEM-RECORD-AUTOLOADS** *[AUTOLOAD-SYSTEM][cd2d] (:RECORD-AUTOLOADS = NIL)*

    This specifies where the automatically extracted
    autoload forms shall be written by [`RECORD-SYSTEM-AUTOLOADS`][dceb].
    Conditions signalled while ASDF is compiling or loading the file
    given have a `RECORD-SYSTEM-AUTOLOADS` restart.

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

### 4.1 Generating Autoloads

<a id="x-28AUTOLOAD-3AAUTOLOADS-20FUNCTION-29"></a>

- [function] **AUTOLOADS** *SYSTEM &KEY (PROCESS-ARGLIST T) (PROCESS-DOCSTRING T) PACKAGES*

    Return a list of forms that set up autoloading for definitions such
    as [`DEFUN/AUTOLOADED`][3b15] in [autoloaded direct dependencies][8429] of `SYSTEM`.
    
    Note that this is an expensive operation, as it loads or reloads the
    direct dependencies one by one with `ASDF:LOAD-SYSTEM` `:FORCE` `T` and
    records the association with the system and the autoloaded
    definitions such as `DEFUN/AUTOLOADED`.
    
    - For function definitions such as `DEFUN/AUTOLOADED`, an
      [`AUTOLOAD`][7da0] form is emitted.
    
    If `PROCESS-ARGLIST` is `T`, then the autoload forms will pass the
       `ARGLIST` argument of the corresponding `DEFUN/AUTOLOADED` to
       `AUTOLOAD`. If it is `NIL`, then `ARGLIST` will not be passed to
       `AUTOLOAD`.
    
    - For [`DEFVAR/AUTOLOADED`][453a], a [`DECLARE-VARIABLE-AUTOLOAD`][c5d0] is emitted.
    
    If the initial value form in `DEFVAR/AUTOLOADED` is detected as a
       simple constant form, then it is passed as `INIT` to
       `DECLARE-VARIABLE-AUTOLOAD`. Simple constant forms are strings,
       numbers, characters, keywords, constants in the CL package, and
       [`QUOTE`][f5d0]d nested lists containing any of the previous or any symbol
       from the CL.
    
    - For [`DEFPACKAGE/AUTOLOADED`][990a] and the provided `PACKAGES`, individual
      package-altering operations are emitted.
    
        As in the expansion of `DEFPACKAGE/AUTOLOADED` itself, these
        operations are additive. To handle circular dependencies, first
        all packages are created, then their state is reconstructed in
        phases following [`DEFPACKAGE`][9b43].
    
    - If `PROCESS-DOCSTRING`, then the docstrings extracted from
      `DEFUN/AUTOLOADED` or `DEFVAR/AUTOLOADED` will be associated with the
      definition.
    
    Note that if a function is not defined with `DEFUN/AUTOLOADED` or its
    kin in [Basics][fa90], then `AUTOLOADS` will not detect it. For such
    functions, [`AUTOLOAD`][7da0]s must be written manually. Similar
    considerations apply to variables and packages.

<a id="x-28AUTOLOAD-3AWRITE-AUTOLOADS-20FUNCTION-29"></a>

- [function] **WRITE-AUTOLOADS** *FORMS STREAM*

    Write the autoload `FORMS` to `STREAM` that can be [`LOAD`][b5ec]ed or included
    in an `ASDF:DEFSYSTEM`.

<a id="x-28AUTOLOAD-3ARECORD-SYSTEM-AUTOLOADS-20FUNCTION-29"></a>

- [function] **RECORD-SYSTEM-AUTOLOADS** *SYSTEM*

    Write the [`AUTOLOADS`][1e20] of `SYSTEM` to the file in its
    [`:RECORD-AUTOLOADS`][f945], which may be a [pathname designator][3914] or a
    list of the form
    
        (pathname &key (process-arglist t) (process-docstring t) packages)
    
    See [`AUTOLOADS`][1e20] and [`WRITE-AUTOLOADS`][3140] for the description of
    these arguments. `PATHNAME`([`0`][0317] [`1`][6671]) is relative to
    `ASDF:SYSTEM-SOURCE-DIRECTORY` of `SYSTEM` and is [`OPEN`][6547]ed with `:IF-EXISTS`
    `:SUPERSEDE`.
    
    As `AUTOLOADS` loads the direct autoloaded dependencies, compiler
    warnings (e.g. about undefined specials and functions) may occur
    that go away once the generated autoloads are in place. The easiest
    way to trigger this is to call `RECORD-SYSTEM-AUTOLOADS` before these
    dependencies have been loaded. In this case, temporarily emptying
    the autoloads file and fixing these warnings is recommended.

<a id="x-28AUTOLOAD-3ACHECK-SYSTEM-AUTOLOADS-20FUNCTION-29"></a>

- [function] **CHECK-SYSTEM-AUTOLOADS** *SYSTEM &KEY (ERRORP T)*

    In the [`AUTOLOAD-SYSTEM`][cd2d] `SYSTEM`, check that there is a
    [`:RECORD-AUTOLOADS`][f945] and the file generated
    by [`RECORD-SYSTEM-AUTOLOADS`][dceb] is up-to-date.
    
    If `ERRORP`, then signal an error if it is not or the file cannot be
    read. `RECORD-SYSTEM-AUTOLOADS` restart is provided.
    
    This compares the current [`AUTOLOADS`][1e20] to those in the file with [`EQUAL`][3fb5]
    and is thus sensitive to the order of definitions.
    
    This function is called automatically by `ASDF:TEST-OP` on a
    `AUTOLOAD-SYSTEM` method if [`SYSTEM-TEST-AUTOLOADS`][3ab0].

<a id="x-28AUTOLOAD-3AAUTOLOAD-CL-SOURCE-FILE-20CLASS-29"></a>

- [class] **AUTOLOAD-CL-SOURCE-FILE** *ASDF/LISP-ACTION:CL-SOURCE-FILE*

    The `:DEFAULT-COMPONENT-CLASS` of [`AUTOLOAD-SYSTEM`][cd2d].
    The [`SYSTEM-AUTOLOADED-SYSTEMS`][8429] and
    [`SYSTEM-RECORD-AUTOLOADS`][f945] features rely
    on source file belonging to this class. When combining autoload with
    another ASDF extension that has own `ASDF:CL-SOURCE-FILE` subclass,
    define a new class that inherits from both and use that as
    `:DEFAULT-COMPONENT-CLASS`.

  [0317]: http://www.lispworks.com/documentation/HyperSpec/Body/t_pn.htm "PATHNAME (MGL-PAX:CLHS CLASS)"
  [05c1]: http://www.lispworks.com/documentation/HyperSpec/Body/d_ftype.htm "FTYPE (MGL-PAX:CLHS DECLARATION)"
  [0c4f]: http://www.lispworks.com/documentation/HyperSpec/Body/f_export.htm "EXPORT (MGL-PAX:CLHS FUNCTION)"
  [0c5c]: #x-28AUTOLOAD-3A-40ASDF-INTEGRATION-20MGL-PAX-3ASECTION-29 "ASDF Integration"
  [119e]: http://www.lispworks.com/documentation/HyperSpec/Body/t_fn.htm "FUNCTION (MGL-PAX:CLHS CLASS)"
  [1dd6]: #x-28AUTOLOAD-3AVARIABLE-AUTOLOAD-P-20FUNCTION-29 "AUTOLOAD:VARIABLE-AUTOLOAD-P FUNCTION"
  [1e20]: #x-28AUTOLOAD-3AAUTOLOADS-20FUNCTION-29 "AUTOLOAD:AUTOLOADS FUNCTION"
  [2264]: http://www.lispworks.com/documentation/HyperSpec/Body/f_use_pk.htm "USE-PACKAGE (MGL-PAX:CLHS FUNCTION)"
  [24b9]: #x-28AUTOLOAD-3ADEFINE-AUTOLOADED-FUNCTION-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFINE-AUTOLOADED-FUNCTION MGL-PAX:MACRO"
  [27c6]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_c.htm#compile_time "\"compile time\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [3140]: #x-28AUTOLOAD-3AWRITE-AUTOLOADS-20FUNCTION-29 "AUTOLOAD:WRITE-AUTOLOADS FUNCTION"
  [3914]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_p.htm#pathname_designator "\"pathname designator\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [3ab0]: #x-28AUTOLOAD-3ASYSTEM-TEST-AUTOLOADS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29 "AUTOLOAD:SYSTEM-TEST-AUTOLOADS (MGL-PAX:READER AUTOLOAD:AUTOLOAD-SYSTEM)"
  [3b15]: #x-28AUTOLOAD-3ADEFUN-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFUN/AUTOLOADED MGL-PAX:MACRO"
  [3fb5]: http://www.lispworks.com/documentation/HyperSpec/Body/f_equal.htm "EQUAL (MGL-PAX:CLHS FUNCTION)"
  [453a]: #x-28AUTOLOAD-3ADEFVAR-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFVAR/AUTOLOADED MGL-PAX:MACRO"
  [471f]: #x-28AUTOLOAD-3A-40INTRODUCTION-20MGL-PAX-3ASECTION-29 "Introduction"
  [48d3]: #x-28AUTOLOAD-3A-40GENERATING-AUTOLOADS-20MGL-PAX-3ASECTION-29 "Generating Autoloads"
  [4afe]: #x-28AUTOLOAD-3ACHECK-SYSTEM-AUTOLOADS-20FUNCTION-29 "AUTOLOAD:CHECK-SYSTEM-AUTOLOADS FUNCTION"
  [4b04]: #x-28AUTOLOAD-3A-40FUNCTIONS-20MGL-PAX-3ASECTION-29 "Functions"
  [57ad]: #x-28AUTOLOAD-3AFUNCTION-AUTOLOAD-P-20FUNCTION-29 "AUTOLOAD:FUNCTION-AUTOLOAD-P FUNCTION"
  [5968]: #x-28-22autoload-22-20ASDF-2FSYSTEM-3ASYSTEM-29 "\"autoload\" ASDF/SYSTEM:SYSTEM"
  [643f]: #x-28AUTOLOAD-3A-40PACKAGES-20MGL-PAX-3ASECTION-29 "Package"
  [6547]: http://www.lispworks.com/documentation/HyperSpec/Body/f_open.htm "OPEN (MGL-PAX:CLHS FUNCTION)"
  [6671]: http://www.lispworks.com/documentation/HyperSpec/Body/f_pn.htm "PATHNAME (MGL-PAX:CLHS FUNCTION)"
  [6caf]: #x-28AUTOLOAD-3A-40AUTOLOAD-MANUAL-20MGL-PAX-3ASECTION-29 "Autoload Manual"
  [7334]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defpar.htm "DEFVAR (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [7da0]: #x-28AUTOLOAD-3AAUTOLOAD-20MGL-PAX-3AMACRO-29 "AUTOLOAD:AUTOLOAD MGL-PAX:MACRO"
  [81f7]: http://www.lispworks.com/documentation/HyperSpec/Body/s_fn.htm "FUNCTION (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [8429]: #x-28AUTOLOAD-3ASYSTEM-AUTOLOADED-SYSTEMS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29 "AUTOLOAD:SYSTEM-AUTOLOADED-SYSTEMS (MGL-PAX:READER AUTOLOAD:AUTOLOAD-SYSTEM)"
  [8b6e]: #x-28AUTOLOAD-3ADEFGENERIC-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFGENERIC/AUTOLOADED MGL-PAX:MACRO"
  [9514]: http://www.lispworks.com/documentation/HyperSpec/Body/d_inline.htm "NOTINLINE (MGL-PAX:CLHS DECLARATION)"
  [990a]: #x-28AUTOLOAD-3ADEFPACKAGE-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFPACKAGE/AUTOLOADED MGL-PAX:MACRO"
  [9b43]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defpkg.htm "DEFPACKAGE (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [a138]: http://www.lispworks.com/documentation/HyperSpec/Body/m_setf_.htm "SETF (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [ae25]: https://www.quicklisp.org/ "Quicklisp"
  [b5ec]: http://www.lispworks.com/documentation/HyperSpec/Body/f_load.htm "LOAD (MGL-PAX:CLHS FUNCTION)"
  [c5ae]: http://www.lispworks.com/documentation/HyperSpec/Body/f_docume.htm "DOCUMENTATION (MGL-PAX:CLHS GENERIC-FUNCTION)"
  [c5d0]: #x-28AUTOLOAD-3ADECLARE-VARIABLE-AUTOLOAD-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DECLARE-VARIABLE-AUTOLOAD MGL-PAX:MACRO"
  [c7f7]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defgen.htm "DEFGENERIC (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [cd2d]: #x-28AUTOLOAD-3AAUTOLOAD-SYSTEM-20CLASS-29 "AUTOLOAD:AUTOLOAD-SYSTEM CLASS"
  [d0c4]: http://www.lispworks.com/documentation/HyperSpec/Body/f_shadow.htm "SHADOW (MGL-PAX:CLHS FUNCTION)"
  [d60b]: #x-28AUTOLOAD-3A-40LINKS-AND-SYSTEMS-20MGL-PAX-3ASECTION-29 "Links and Systems"
  [d78c]: https://slime.common-lisp.dev/doc/html/slime_002dautodoc_002dmode.html#slime_002dautodoc_002dmode "SLIME autodoc"
  [da95]: #x-28AUTOLOAD-3AAUTOLOAD-WARNING-20CONDITION-29 "AUTOLOAD:AUTOLOAD-WARNING CONDITION"
  [dceb]: #x-28AUTOLOAD-3ARECORD-SYSTEM-AUTOLOADS-20FUNCTION-29 "AUTOLOAD:RECORD-SYSTEM-AUTOLOADS FUNCTION"
  [ead6]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defcla.htm "DEFCLASS (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [ebea]: http://www.lispworks.com/documentation/HyperSpec/Body/m_declai.htm "DECLAIM (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [eea4]: http://www.lispworks.com/documentation/HyperSpec/Body/f_fdefin.htm "FDEFINITION (MGL-PAX:CLHS FUNCTION)"
  [f472]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defun.htm "DEFUN (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [f490]: #x-28AUTOLOAD-3A-40VARIABLES-20MGL-PAX-3ASECTION-29 "Variables"
  [f5d0]: http://www.lispworks.com/documentation/HyperSpec/Body/s_quote.htm "QUOTE (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [f945]: #x-28AUTOLOAD-3ASYSTEM-RECORD-AUTOLOADS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29 "AUTOLOAD:SYSTEM-RECORD-AUTOLOADS (MGL-PAX:READER AUTOLOAD:AUTOLOAD-SYSTEM)"
  [fa90]: #x-28AUTOLOAD-3A-40BASICS-20MGL-PAX-3ASECTION-29 "Basics"
  [fc62]: http://www.lispworks.com/documentation/HyperSpec/Body/e_smp_wa.htm "SIMPLE-WARNING (MGL-PAX:CLHS CONDITION)"

* * *
###### \[generated by [MGL-PAX](https://github.com/melisgl/mgl-pax)\]
