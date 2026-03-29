<a id="x-28AUTOLOAD-3A-40AUTOLOAD-MANUAL-20MGL-PAX-3ASECTION-29"></a>

# Autoload Manual

## Table of Contents

- [1 Links and Systems][d60b]
- [2 Introduction][471f]
- [3 Basics][fa90]
    - [3.1 Functions][4b04]
    - [3.2 Variables][f490]
    - [3.3 Packages][643f]
    - [3.4 Conditions][f43d]
- [4 ASDF Integration][0c5c]
    - [4.1 Automatically Generating Loaddefs][c1d4]

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
    - _Homepage:_ [https://github.com/melisgl/autoload](https://github.com/melisgl/autoload)
    - _Bug tracker:_ [https://github.com/melisgl/autoload/issues](https://github.com/melisgl/autoload/issues)
    - _Source control:_ [GIT](https://github.com/melisgl/autoload.git)

<a id="x-28-22autoload-doc-22-20ASDF-2FSYSTEM-3ASYSTEM-29"></a>

- [system] **"autoload-doc"**

    - _Description:_ Parts of [`autoload`][5968] that depend on
        `mgl-pax`. Since `mgl-pax` depends on
        [`autoload`][7da0], these parts get a separate system to break the
        circularity. Note that `mgl-pax/navigate` and
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
     (apply ',name args)))
```

Suppose we have a library called `my-lib` that autoloads
`my-lib/full`. In `my-lib`, we could use [`AUTOLOAD`][7da0] as

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

However, manually keeping the loaddefs (e.g. the `AUTOLOAD` form
above) in sync with the definitions is fragile, so instead we mark
autoloaded functions in the `my-lib/full` system:

```
(defun/autoloaded foo (x)
  "doc"
  (1+ x))
```

and [generate loaddefs][c1d4] through the
[ASDF Integration][0c5c]:

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

This is implemented by loading the `:AUTO-DEPENDS-ON` of `my-lib` and
recording [`DEFUN/AUTOLOADED`][3b15]s. [`EXTRACT-LOADDEFS`][dd7e] is a low-level utility
used by [`RECORD-LOADDEFS`][e90c], which writes its results to
the system's [`:AUTO-LOADDEFS`][0724], `"loaddefs.lisp"` in the above example.
So, all we need to do is call it to regenerate the loaddefs file:

```
(record-loaddefs "my-lib")
```

To prevent the loaddefs file from getting out of sync with the
definitions, `ASDF:TEST-SYSTEM` calls [`CHECK-LOADDEFS`][451b] by default.

ASDF, and by extension [Quicklisp][ae25], don't know about the declared
[`:AUTO-DEPENDS-ON`][9b08], so `(QL:QUICKLOAD "my-lib")` does not install the
autoloaded dependencies. This can be done with

```
(autodeps "my-lib" :installer #'ql:quickload)
```

If all the autoloaded dependencies are installed, one can eagerly
load them to ensure that autoloading is not triggered later (e.g.
in deployment):

```
(mapcar #'asdf:load-system (autodeps "my-lib"))
```


<a id="x-28AUTOLOAD-3A-40BASICS-20MGL-PAX-3ASECTION-29"></a>

## 3 Basics

<a id="x-28AUTOLOAD-3A-40FUNCTIONS-20MGL-PAX-3ASECTION-29"></a>

### 3.1 Functions

<a id="x-28AUTOLOAD-3AAUTOLOAD-20MGL-PAX-3AMACRO-29"></a>

- [macro] **AUTOLOAD** *NAME SYSTEM-NAME &KEY (ARGLIST NIL) (DOCSTRING NIL)*

    Define a stub function with `NAME` that loads `SYSTEM-NAME`, expecting
    it to redefine the function, and then calls the newly loaded
    definition. Return `NAME`. The arguments are not evaluated. If `NAME`
    has an [`FDEFINITION`][eea4] and it is not [`AUTOLOAD-FBOUND-P`][8dd7], then do
    nothing and return `NIL`.
    
    The stub does the following.
    
    1. It signals an [`AUTOLOAD-ERROR`][a515] if `SYSTEM-NAME` does not exist.
    
    2. It loads `SYSTEM-NAME` under [`WITH-COMPILATION-UNIT`][6166] `:OVERRIDE` `T` and
       [`WITH-STANDARD-IO-SYNTAX`][39df] but with [`*PRINT-READABLY*`][8aca] `NIL`. Other
       non-portable measures may be taken to standardize the dynamic
       environment.
    
    3. It checks that the function with `NAME` has been redefined as a
       normal function (that's not `AUTOLOAD-FBOUND-P`), else it signals
       an `AUTOLOAD-ERROR`.
    
    4. It calls the function `NAME` passing on the stub's own arguments.
    
    The stub is not defined at [compile time][27c6], which matches the
    required semantics of [`DEFUN`][f472]. `NAME` is [`DECLAIM`][ebea]ed with [`FTYPE`][05c1] `FUNCTION`([`0`][119e] [`1`][81f7])
    and [`NOTINLINE`][9514].
    
    - `ARGLIST` will be installed as the stub's arglist if specified and
      it's supported on the platform (currently only SBCL). If `ARGLIST`
      is a string, the effective value of `ARGLIST` is read from it. If
      the read fails, an [`AUTOLOAD-WARNING`][da95] is signalled and processing
      continues as if `ARGLIST` had not been provided.
    
        Arglists are for interactive purposes only. For example, they
        are shown by [SLIME autodoc][d78c] and returned by `DREF:ARGLIST`.
    
    - `DOCSTRING`, if specified, will be the stub's docstring. If not
      specified, a generic docstring that says what system it autoloads
      will be used.
    
    When `AUTOLOAD` is macroexpanded during the compilation or loading of
    an [`AUTOLOAD-SYSTEM`][cd2d], it signals an `AUTOLOAD-WARNING` if `SYSTEM-NAME` is
    not among those declared in [`:AUTO-DEPENDS-ON`][9b08].

<a id="x-28AUTOLOAD-3AAUTOLOAD-FBOUND-P-20FUNCTION-29"></a>

- [function] **AUTOLOAD-FBOUND-P** *NAME*

    See if `NAME`'s function definition is an autoloader function
    established by [`AUTOLOAD`][7da0].

<a id="x-28AUTOLOAD-3ADEFUN-2FAUTOLOADED-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFUN/AUTOLOADED** *NAME LAMBDA-LIST &BODY BODY*

    Like [`DEFUN`][f472], but mark the function for [Automatically Generating Loaddefs][c1d4] and
    silence redefinition warnings. Also, warn if `NAME` has never been
    [`AUTOLOAD-FBOUND-P`][8dd7].

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

<a id="x-28AUTOLOAD-3ADEFVAR-2FAUTOLOADED-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFVAR/AUTOLOADED** *VAR &OPTIONAL (VAL NIL) DOC*

    Like [`DEFVAR`][7334], but mark the variable for [Automatically Generating Loaddefs][c1d4].
    
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
    
    `DEFVAR/AUTOLOADED` warns if `VAR` does not have a loaddef in
    [`:AUTO-LOADDEFS`][0724].

<a id="x-28AUTOLOAD-3A-40PACKAGES-20MGL-PAX-3ASECTION-29"></a>

### 3.3 Packages

<a id="x-28AUTOLOAD-3ADEFPACKAGE-2FAUTOLOADED-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFPACKAGE/AUTOLOADED** *NAME &REST OPTIONS*

    Like [`DEFPACKAGE`][9b43], but mark the package for [Automatically Generating Loaddefs][c1d4] and
    extend the existing definition additively.
    
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
    `UIOP:DEFINE-PACKAGE` and arrange for [Automatically Generating Loaddefs][c1d4] for the
    package by listing it in `:PACKAGES` of [`:AUTO-LOADDEFS`][0724].

<a id="x-28AUTOLOAD-3A-40CONDITIONS-20MGL-PAX-3ASECTION-29"></a>

### 3.4 Conditions

<a id="x-28AUTOLOAD-3AAUTOLOAD-ERROR-20CONDITION-29"></a>

- [condition] **AUTOLOAD-ERROR** *[ERROR][d162]*

    Signalled by the stub defined by [`AUTOLOAD`][7da0] if
    autoloading fails.

<a id="x-28AUTOLOAD-3AAUTOLOAD-WARNING-20CONDITION-29"></a>

- [condition] **AUTOLOAD-WARNING** *[SIMPLE-WARNING][fc62]*

    Signalled when inconsistencies are detected by e.g.
    [`AUTOLOAD`][7da0] and [`DEFVAR/AUTOLOADED`][453a].

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
      :auto-depends-on ("dyndep")
      :auto-loaddefs "loaddefs.lisp"
      :components ((:file "package")
                   (:file "loaddefs")
                   ...))
    ```
    
    With the above,
    
    - It is an error if an [`AUTOLOAD`][7da0] refers to a system other than
      `dyndep`.
    
    - `(`[`RECORD-LOADDEFS`][e90c] `"my-system")` will update
      `loaddefs.lisp`.
    
    - `(ASDF:TEST-SYSTEM "my-system")` [checks][451b] that
      `loaddefs.lisp` is up-to-date.
    
    If the package definitions are also generated with
    [`RECORD-LOADDEFS`][e90c] (e.g. because there is a
    [`DEFPACKAGE/AUTOLOADED`][990a] in `dyndep` or `:AUTO-LOADDEFS` specifies
    `:PACKAGES`), then we can do without the `package.lisp` file:
    
    ```
    (asdf:defsystem "my-system"
      :defsystem-depends-on ("autoload")
      :class "autoload:autoload-system"
      :auto-depends-on ("dyndep")
      :auto-loaddefs ("loaddefs.lisp" :packages #:my-pkg)
      :components ((:file "loaddefs")
                   ...))
    ```

<a id="x-28AUTOLOAD-3AAUTOLOAD-CL-SOURCE-FILE-20CLASS-29"></a>

- [class] **AUTOLOAD-CL-SOURCE-FILE** *ASDF/LISP-ACTION:CL-SOURCE-FILE*

    The `:DEFAULT-COMPONENT-CLASS` of [`AUTOLOAD-SYSTEM`][cd2d].
    [ASDF Integration][0c5c] relies on source files belonging to this class. When
    combining autoload with another ASDF extension that has its own
    `ASDF:CL-SOURCE-FILE` subclass, define a new class that inherits from
    both, and use that as `:DEFAULT-COMPONENT-CLASS`.

<a id="x-28AUTOLOAD-3ASYSTEM-AUTO-DEPENDS-ON-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29"></a>

- [reader] **SYSTEM-AUTO-DEPENDS-ON** *[AUTOLOAD-SYSTEM][cd2d] (:AUTO-DEPENDS-ON = NIL)*

    This is the list of the names of systems that this
    system may autoload. The names are canonicalized with
    `ASDF:COERCE-NAME`. This is used by [`EXTRACT-LOADDEFS`][dd7e] and affects
    the checks performed by the [`AUTOLOAD`][7da0] macro.

<a id="x-28AUTOLOAD-3ASYSTEM-AUTO-LOADDEFS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29"></a>

- [reader] **SYSTEM-AUTO-LOADDEFS** *[AUTOLOAD-SYSTEM][cd2d] (:AUTO-LOADDEFS = NIL)*

    When non-`NIL`, this specifies parameters for
    [`RECORD-LOADDEFS`][e90c] and whether [`CHECK-LOADDEFS`][451b] shall be
    run by `ASDF:TEST-SYSTEM`. It may be a single pathname designator or
    a list of the form
    
        (loaddefs-file &key (process-arglist t) (process-docstring t)
                       packages test)
    
    - `LOADDEFS-FILE` designates the pathname where `RECORD-LOADDEFS`
      writes the [extracted loaddefs][dd7e]. The pathname
      is relative to `ASDF:SYSTEM-SOURCE-DIRECTORY` of `SYSTEM` and is
      [`OPEN`][6547]ed with `:IF-EXISTS` `:SUPERSEDE`.
    
    - `PROCESS-ARGLIST`, `PROCESS-DOCSTRING` and [`PACKAGES`][1d5a] are passed on by
      `RECORD-LOADDEFS` to `EXTRACT-LOADDEFS`.
    
    - If `TEST`, then `CHECK-LOADDEFS` is run by `ASDF:TEST-SYSTEM`.
    
    Conditions signalled while ASDF is compiling or loading the file
    given have a [`RECORD-LOADDEFS`][3d01] restart.

<a id="x-28AUTOLOAD-3AAUTODEPS-20FUNCTION-29"></a>

- [function] **AUTODEPS** *SYSTEM &KEY (FOLLOW-AUTOLOADED T) INSTALLER*

    Return the list of the names of systems that may be autoloaded by
    `SYSTEM` or any of its normal dependencies (the transitive closure of
    its `:DEPENDS-ON`). This works even if `SYSTEM` is not an
    [`AUTOLOAD-SYSTEM`][cd2d].
    
    - If `FOLLOW-AUTOLOADED`, look further for autoloaded systems among
      the normal and autoloaded dependencies of any autoloaded systems
      found. If an autoloaded system is not installed (i.e.
      `ASDF:FIND-SYSTEM` fails), then that system is not followed.
    
    - If `INSTALLER` is non-`NIL`, it is called when an uninstalled system
      is encountered. This is an autoloaded system if normal ASDF
      dependencies are installed, as is the case with e.g. [Quicklisp][ae25].
      `INSTALLER` is passed a single argument, the name of the system to
      be installed, and it may or may not install the system.
    
    The following example makes sure that all normal and autoloaded
    dependencies (direct or indirect) of `my-system` are installed:
    
        (autodeps "my-system" :installer #'ql:quickload)

<a id="x-28AUTOLOAD-3A-40AUTOMATIC-LOADDEFS-20MGL-PAX-3ASECTION-29"></a>

### 4.1 Automatically Generating Loaddefs

<a id="x-28AUTOLOAD-3AEXTRACT-LOADDEFS-20FUNCTION-29"></a>

- [function] **EXTRACT-LOADDEFS** *SYSTEM &KEY (PROCESS-ARGLIST T) (PROCESS-DOCSTRING T) PACKAGES*

    Return a list of so-called loaddef forms that set up autoloading
    for definitions such as [`DEFUN/AUTOLOADED`][3b15] in [`:AUTO-DEPENDS-ON`][9b08] of
    `SYSTEM`.
    
    There is rarely a need to call this function directly, as
    [`RECORD-LOADDEFS`][e90c] and [`CHECK-LOADDEFS`][451b] provide
    [ASDF Integration][0c5c].
    
    Note that this is an expensive operation, as it loads or reloads the
    direct dependencies one by one with `ASDF:LOAD-SYSTEM` `:FORCE` `T` and
    records the association with the system and the autoloaded
    definitions such as `DEFUN/AUTOLOADED`.
    
    - For function definitions such as `DEFUN/AUTOLOADED`, an [`AUTOLOAD`][7da0]
      form is emitted.
    
        If `PROCESS-ARGLIST` is `T`, then the autoload forms will pass the
        `ARGLIST` argument of the corresponding `DEFUN/AUTOLOADED` to
        `AUTOLOAD`. If it is `NIL`, then `ARGLIST` will not be passed to
        `AUTOLOAD`.
    
    - For [`DEFVAR/AUTOLOADED`][453a], the emitted loaddefs declaim the variable
      special and maybe set its initial value and docstring.
    
        If the initial value form in `DEFVAR/AUTOLOADED` is detected as a
        simple constant form, then it is evaluated and its value is
        assigned to the variable as in [`DEFVAR`][7334]. Simple constant forms are
        strings, numbers, characters, keywords, constants in the CL
        package, and [`QUOTE`][f5d0]d nested lists containing any of the previous
        or any symbol from the `CL` package.
    
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
    kin in [Basics][fa90], then `EXTRACT-LOADDEFS` will not detect it. For such
    functions, `AUTOLOAD` forms must be written manually. Similar
    considerations apply to variables and packages.

<a id="x-28AUTOLOAD-3AWRITE-LOADDEFS-20FUNCTION-29"></a>

- [function] **WRITE-LOADDEFS** *FORMS STREAM*

    Write the autoload `FORMS` to `STREAM` so they can be [`LOAD`][b5ec]ed or
    included in an `ASDF:DEFSYSTEM`.

<a id="x-28AUTOLOAD-3ARECORD-LOADDEFS-20FUNCTION-29"></a>

- [function] **RECORD-LOADDEFS** *SYSTEM*

    [`EXTRACT-LOADDEFS`][dd7e] from `SYSTEM` and [`WRITE-LOADDEFS`][6d25]. The arguments of
    these functions are taken from `SYSTEM`'s [`:AUTO-LOADDEFS`][0724].
    
    As `EXTRACT-LOADDEFS` loads the direct autoloaded dependencies,
    compiler warnings (e.g. about undefined specials and functions) may
    occur that go away once the generated loaddefs are in place. The
    easiest way to trigger this is to call `RECORD-LOADDEFS` before these
    dependencies have been loaded. In this case, temporarily emptying
    the loaddefs file and fixing these warnings is recommended.
    
    `RECORD-LOADDEFS` may also be used as a [condition handler][ea6a], in
    which case it invokes the [`RECORD-LOADDEFS`][3d01] restart.

<a id="x-28AUTOLOAD-3ACHECK-LOADDEFS-20FUNCTION-29"></a>

- [function] **CHECK-LOADDEFS** *SYSTEM &KEY (ERRORP T)*

    In the [`AUTOLOAD-SYSTEM`][cd2d] `SYSTEM`, check that both recorded and manual
    autoload declarations are correct.
    
    - If there is a [`:AUTO-LOADDEFS`][0724], then the file generated by
      [`RECORD-LOADDEFS`][e90c] is up-to-date.
    
    - All manual (non-generated) autoload declarations with [`AUTOLOAD`][7da0]s in
      `SYSTEM` are resolved (the corresponding function or variable is
      defined) by loading [`:AUTO-DEPENDS-ON`][9b08].
    
    If `ERRORP`, then signal an error if the check fails or the file
    cannot be read. The [`RECORD-LOADDEFS`][3d01] restart is provided.
    
    This function is called automatically by `ASDF:TEST-OP` on an
    `AUTOLOAD-SYSTEM` method if [`:AUTO-LOADDEFS`][0724] has `:TEST` `T`.

<a id="x-28AUTOLOAD-3ARECORD-LOADDEFS-20RESTART-29"></a>

- [restart] **RECORD-LOADDEFS**

    Provided by [`CHECK-LOADDEFS`][451b] and also when the compilation of the
    loaddefs file declared in [`:AUTO-LOADDEFS`][0724] fails. The function
    [`RECORD-LOADDEFS`][e90c] can be used as a condition handler to invoke this
    restart.

  [05c1]: http://www.lispworks.com/documentation/HyperSpec/Body/d_ftype.htm "FTYPE (MGL-PAX:CLHS DECLARATION)"
  [0724]: #x-28AUTOLOAD-3ASYSTEM-AUTO-LOADDEFS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29 "AUTOLOAD:SYSTEM-AUTO-LOADDEFS (MGL-PAX:READER AUTOLOAD:AUTOLOAD-SYSTEM)"
  [0c4f]: http://www.lispworks.com/documentation/HyperSpec/Body/f_export.htm "EXPORT (MGL-PAX:CLHS FUNCTION)"
  [0c5c]: #x-28AUTOLOAD-3A-40ASDF-INTEGRATION-20MGL-PAX-3ASECTION-29 "ASDF Integration"
  [119e]: http://www.lispworks.com/documentation/HyperSpec/Body/t_fn.htm "FUNCTION (MGL-PAX:CLHS CLASS)"
  [1d5a]: http://www.lispworks.com/documentation/HyperSpec/Body/t_pkg.htm "PACKAGE (MGL-PAX:CLHS CLASS)"
  [2264]: http://www.lispworks.com/documentation/HyperSpec/Body/f_use_pk.htm "USE-PACKAGE (MGL-PAX:CLHS FUNCTION)"
  [27c6]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_c.htm#compile_time "\"compile time\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [39df]: http://www.lispworks.com/documentation/HyperSpec/Body/m_w_std_.htm "WITH-STANDARD-IO-SYNTAX (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [3b15]: #x-28AUTOLOAD-3ADEFUN-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFUN/AUTOLOADED MGL-PAX:MACRO"
  [3d01]: #x-28AUTOLOAD-3ARECORD-LOADDEFS-20RESTART-29 "AUTOLOAD:RECORD-LOADDEFS RESTART"
  [451b]: #x-28AUTOLOAD-3ACHECK-LOADDEFS-20FUNCTION-29 "AUTOLOAD:CHECK-LOADDEFS FUNCTION"
  [453a]: #x-28AUTOLOAD-3ADEFVAR-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFVAR/AUTOLOADED MGL-PAX:MACRO"
  [471f]: #x-28AUTOLOAD-3A-40INTRODUCTION-20MGL-PAX-3ASECTION-29 "Introduction"
  [4b04]: #x-28AUTOLOAD-3A-40FUNCTIONS-20MGL-PAX-3ASECTION-29 "Functions"
  [5968]: #x-28-22autoload-22-20ASDF-2FSYSTEM-3ASYSTEM-29 "\"autoload\" ASDF/SYSTEM:SYSTEM"
  [6166]: http://www.lispworks.com/documentation/HyperSpec/Body/m_w_comp.htm "WITH-COMPILATION-UNIT (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [643f]: #x-28AUTOLOAD-3A-40PACKAGES-20MGL-PAX-3ASECTION-29 "Packages"
  [6547]: http://www.lispworks.com/documentation/HyperSpec/Body/f_open.htm "OPEN (MGL-PAX:CLHS FUNCTION)"
  [6caf]: #x-28AUTOLOAD-3A-40AUTOLOAD-MANUAL-20MGL-PAX-3ASECTION-29 "Autoload Manual"
  [6d25]: #x-28AUTOLOAD-3AWRITE-LOADDEFS-20FUNCTION-29 "AUTOLOAD:WRITE-LOADDEFS FUNCTION"
  [7334]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defpar.htm "DEFVAR (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [7da0]: #x-28AUTOLOAD-3AAUTOLOAD-20MGL-PAX-3AMACRO-29 "AUTOLOAD:AUTOLOAD MGL-PAX:MACRO"
  [81f7]: http://www.lispworks.com/documentation/HyperSpec/Body/s_fn.htm "FUNCTION (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [8aca]: http://www.lispworks.com/documentation/HyperSpec/Body/v_pr_rda.htm "*PRINT-READABLY* (MGL-PAX:CLHS VARIABLE)"
  [8dd7]: #x-28AUTOLOAD-3AAUTOLOAD-FBOUND-P-20FUNCTION-29 "AUTOLOAD:AUTOLOAD-FBOUND-P FUNCTION"
  [9514]: http://www.lispworks.com/documentation/HyperSpec/Body/d_inline.htm "NOTINLINE (MGL-PAX:CLHS DECLARATION)"
  [990a]: #x-28AUTOLOAD-3ADEFPACKAGE-2FAUTOLOADED-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFPACKAGE/AUTOLOADED MGL-PAX:MACRO"
  [9b08]: #x-28AUTOLOAD-3ASYSTEM-AUTO-DEPENDS-ON-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29 "AUTOLOAD:SYSTEM-AUTO-DEPENDS-ON (MGL-PAX:READER AUTOLOAD:AUTOLOAD-SYSTEM)"
  [9b43]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defpkg.htm "DEFPACKAGE (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [a515]: #x-28AUTOLOAD-3AAUTOLOAD-ERROR-20CONDITION-29 "AUTOLOAD:AUTOLOAD-ERROR CONDITION"
  [ae25]: https://www.quicklisp.org/ "Quicklisp"
  [b5ec]: http://www.lispworks.com/documentation/HyperSpec/Body/f_load.htm "LOAD (MGL-PAX:CLHS FUNCTION)"
  [c1d4]: #x-28AUTOLOAD-3A-40AUTOMATIC-LOADDEFS-20MGL-PAX-3ASECTION-29 "Automatically Generating Loaddefs"
  [c7f7]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defgen.htm "DEFGENERIC (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [cd2d]: #x-28AUTOLOAD-3AAUTOLOAD-SYSTEM-20CLASS-29 "AUTOLOAD:AUTOLOAD-SYSTEM CLASS"
  [d0c4]: http://www.lispworks.com/documentation/HyperSpec/Body/f_shadow.htm "SHADOW (MGL-PAX:CLHS FUNCTION)"
  [d162]: http://www.lispworks.com/documentation/HyperSpec/Body/e_error.htm "ERROR (MGL-PAX:CLHS CONDITION)"
  [d60b]: #x-28AUTOLOAD-3A-40LINKS-AND-SYSTEMS-20MGL-PAX-3ASECTION-29 "Links and Systems"
  [d78c]: https://slime.common-lisp.dev/doc/html/slime_002dautodoc_002dmode.html#slime_002dautodoc_002dmode "SLIME autodoc"
  [da95]: #x-28AUTOLOAD-3AAUTOLOAD-WARNING-20CONDITION-29 "AUTOLOAD:AUTOLOAD-WARNING CONDITION"
  [dd7e]: #x-28AUTOLOAD-3AEXTRACT-LOADDEFS-20FUNCTION-29 "AUTOLOAD:EXTRACT-LOADDEFS FUNCTION"
  [e90c]: #x-28AUTOLOAD-3ARECORD-LOADDEFS-20FUNCTION-29 "AUTOLOAD:RECORD-LOADDEFS FUNCTION"
  [ea6a]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_c.htm#condition_handler "\"condition handler\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [ebea]: http://www.lispworks.com/documentation/HyperSpec/Body/m_declai.htm "DECLAIM (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [eea4]: http://www.lispworks.com/documentation/HyperSpec/Body/f_fdefin.htm "FDEFINITION (MGL-PAX:CLHS FUNCTION)"
  [f43d]: #x-28AUTOLOAD-3A-40CONDITIONS-20MGL-PAX-3ASECTION-29 "Conditions"
  [f472]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defun.htm "DEFUN (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [f490]: #x-28AUTOLOAD-3A-40VARIABLES-20MGL-PAX-3ASECTION-29 "Variables"
  [f5d0]: http://www.lispworks.com/documentation/HyperSpec/Body/s_quote.htm "QUOTE (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [fa90]: #x-28AUTOLOAD-3A-40BASICS-20MGL-PAX-3ASECTION-29 "Basics"
  [fc62]: http://www.lispworks.com/documentation/HyperSpec/Body/e_smp_wa.htm "SIMPLE-WARNING (MGL-PAX:CLHS CONDITION)"

* * *
###### \[generated by [MGL-PAX](https://github.com/melisgl/mgl-pax)\]
