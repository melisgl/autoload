<a id="x-28AUTOLOAD-3A-40AUTOLOAD-MANUAL-20MGL-PAX-3ASECTION-29"></a>

# Autoload Manual

## Table of Contents

- [1 Links and Systems][d60b]
- [2 Introduction][471f]
- [3 Basics][fa90]
    - [3.1 Loading Systems][ddfa]
    - [3.2 Conditions][f43d]
    - [3.3 Functions][4b04]
    - [3.4 Classes][38fe]
    - [3.5 Variables][f490]
    - [3.6 Packages][643f]
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
    - *Depends on:* closer-mop, mgl-pax-bootstrap

<a id="x-28-22autoload-doc-22-20ASDF-2FSYSTEM-3ASYSTEM-29"></a>

- [system] **"autoload-doc"**

    - _Description:_ Parts of the Autoload library that depend on
        `mgl-pax` are in this system to avoid the circular
        dependencies that would arise because `mgl-pax`
        depends on [`autoload`][5968]. Note that
        `mgl-pax/navigate` and `mgl-pax/document` depend on this system, which renders most of this an
        implementation detail.
    - *Depends on:* [autoload][5968], dref, mgl-pax, named-readtables, pythonic-string-reader

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
(defun/auto foo (x)
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

This is implemented by loading the [`:AUTO-DEPENDS-ON`][9b08] of `my-lib` and
recording [`DEFUN/AUTO`][a825]s. [`EXTRACT-LOADDEFS`][dd7e] is a low-level utility used
by [`RECORD-LOADDEFS`][e90c], which writes its results to the
system's [`:AUTO-LOADDEFS`][0724], `"loaddefs.lisp"` in the above example.
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
(map nil #'asdf:load-system (autodeps "my-lib"))
```


<a id="x-28AUTOLOAD-3A-40BASICS-20MGL-PAX-3ASECTION-29"></a>

## 3 Basics

<a id="x-28AUTOLOAD-3A-40AUTOLOAD-20MGL-PAX-3AGLOSSARY-TERM-29"></a>

- [glossary-term] **autoload**

    An autoload definition defines a stub that, when used, triggers
    loading of an `ASDF:SYSTEM`. See [`AUTOLOAD`][7da0] and [`AUTOLOAD-CLASS`][9d6b].

<a id="x-28AUTOLOAD-3A-40LOADDEF-20MGL-PAX-3AGLOSSARY-TERM-29"></a>

- [glossary-term] **loaddef**

    A loaddef is either an [autoload][c7d6] or some other Lisp form that
    foreshadows a definition without setting up autoloading of an
    `ASDF:SYSTEM`. See [`DEFVAR/AUTO`][3cff] and [`DEFPACKAGE/AUTO`][aa0e].

<a id="x-28AUTOLOAD-3A-40AUTO-20MGL-PAX-3AGLOSSARY-TERM-29"></a>

- [glossary-term] **auto**

    An auto definition, such as [`DEFUN/AUTO`][a825], [`DEFGENERIC/AUTO`][5b87],
    [`DEFCLASS/AUTO`][ee20], [`DEFPACKAGE/AUTO`][aa0e], marks the definition for
    [Automatically Generating Loaddefs][c1d4] and signals an [`AUTOLOAD-WARNING`][da95] if there was no
    corresponding [loaddef][e4a5].

<a id="x-28AUTOLOAD-3A-40LOADING-SYSTEMS-20MGL-PAX-3ASECTION-29"></a>

### 3.1 Loading Systems

When an [autoload][c7d6] definition is used, it triggers the loading of
`ASDF:SYSTEM`s. Unlike normal ASDF dependencies (declared in
`:DEPENDS-ON`), autoload dependencies
(may be declared in [`:AUTO-DEPENDS-ON`][9b08]) are allowed to be circular.
The rules for loading are as follows.

1. It is an [`AUTOLOAD-ERROR`][a515] if loading is triggered during [compile
   time][27c6] or during a [`LOAD`][b5ec] of either a [source file][e8f2] or a
   [compiled file][53ee]. This is to prevent infinite autoload
   recursion.

2. It is an `AUTOLOAD-ERROR` if the system does not exist.

3. The system is loaded under [`WITH-COMPILATION-UNIT`][6166] `:OVERRIDE` `T` and
   [`WITH-STANDARD-IO-SYNTAX`][39df] but with [`*PRINT-READABLY*`][8aca] `NIL`. Other
   non-portable measures may be taken to standardize the dynamic
   environment. Errors signalled during the load are not handled or
   resignalled by the Autoload library.

4. It is an `AUTOLOAD-ERROR` if the definition established by the
   [autoload][c7d6] is not redefined as a non-autoload definition or
   deleted by the loaded system.

    For [`AUTOLOAD`][7da0], this means that the autoload function stub must
     be redefined as a normal function (e.g. by [`DEFUN`][f472], [`DEFUN/AUTO`][a825])
     or made [`FMAKUNBOUND`][609c]. For [`AUTOLOAD-CLASS`][9d6b], the class stub must be
     redefined with [`DEFCLASS`][ead6], [`DEFCLASS/AUTO`][ee20] or deleted with `(SETF
     (FIND-CLASS ...) NIL)`.


<a id="x-28AUTOLOAD-3A-40CONDITIONS-20MGL-PAX-3ASECTION-29"></a>

### 3.2 Conditions

<a id="x-28AUTOLOAD-3AAUTOLOAD-ERROR-20CONDITION-29"></a>

- [condition] **AUTOLOAD-ERROR** *[ERROR][d162]*

    Signalled for some failures during [Loading Systems][ddfa].

<a id="x-28AUTOLOAD-3AAUTOLOAD-WARNING-20CONDITION-29"></a>

- [condition] **AUTOLOAD-WARNING** *[SIMPLE-WARNING][fc62]*

    See [`AUTOLOAD`][7da0], [auto][a159]s and [`:AUTO-DEPENDS-ON`][9b08] for when
    this is signalled.

<a id="x-28AUTOLOAD-3A-40FUNCTIONS-20MGL-PAX-3ASECTION-29"></a>

### 3.3 Functions

<a id="x-28AUTOLOAD-3AAUTOLOAD-20MGL-PAX-3AMACRO-29"></a>

- [macro] **AUTOLOAD** *NAME SYSTEM-NAME &KEY (ARGLIST NIL) DOCSTRING*

    Define a stub function with `NAME` that loads `SYSTEM-NAME`, expecting
    it to redefine the function, and then calls the newly loaded
    definition. Return `NAME`. The arguments are not evaluated. If `NAME`
    has an [`FDEFINITION`][eea4] and it is not [`AUTOLOAD-FBOUND-P`][8dd7], then do
    nothing and return `NIL`.
    
    The stub first [loads `SYSTEM-NAME`][ddfa], then it [`APPLY`][d811]s
    the function `NAME` to the arguments originally provided to the stub.
    
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
    
    - `DOCSTRING`, if non-`NIL`, will be the stub's docstring. If `NIL`, then
      a generic docstring that says what system it autoloads will be
      used.
    
    When `AUTOLOAD` is macroexpanded during the compilation or loading of
    an [`AUTOLOAD-SYSTEM`][cd2d], it signals an `AUTOLOAD-WARNING` if `SYSTEM-NAME` is
    not among those declared in [`:AUTO-DEPENDS-ON`][9b08].

<a id="x-28AUTOLOAD-3AAUTOLOAD-FBOUND-P-20FUNCTION-29"></a>

- [function] **AUTOLOAD-FBOUND-P** *NAME*

    See if `NAME`'s function definition is an autoload stub established
    by [`AUTOLOAD`][7da0].

<a id="x-28AUTOLOAD-3ADEFUN-2FAUTO-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFUN/AUTO** *NAME LAMBDA-LIST &BODY BODY*

    Like [`DEFUN`][f472], but mark the function for [Automatically Generating Loaddefs][c1d4] and
    silence redefinition warnings. See [`EXTRACT-LOADDEFS`][dd7e] for the
    corresponding [loaddef][e4a5].
    
    Also, warn if `NAME` has never been [`AUTOLOAD-FBOUND-P`][8dd7].
    
    `NAME` may be of the form (`DEFINER` `NAME`). In that case, instead of
    `DEFUN`, `DEFINER` is used.

<a id="x-28AUTOLOAD-3ADEFGENERIC-2FAUTO-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFGENERIC/AUTO** *NAME LAMBDA-LIST &BODY BODY*

    A shorthand for `(` [`DEFUN/AUTO`][a825] `(DEFGENERIC NAME) ...)`.

<a id="x-28AUTOLOAD-3A-40CLASSES-20MGL-PAX-3ASECTION-29"></a>

### 3.4 Classes

<a id="x-28AUTOLOAD-3AAUTOLOAD-CLASS-20MGL-PAX-3AMACRO-29"></a>

- [macro] **AUTOLOAD-CLASS** *CLASS-NAME SYSTEM-NAME &KEY DOCSTRING*

    Define a dummy class with `CLASS-NAME` and arrange for `SYSTEM-NAME` to
    be [loaded][ddfa] when it or any of its subclasses are
    [instantiated][dddd]. Return the class object. The
    arguments are not evaluated. If `CLASS-NAME` [denotes][51fe] a [`CLASS`][1f37] and it is not [`AUTOLOAD-CLASS-P`][37fc], then do nothing and
    return `NIL`.
    
    - `DOCSTRING`, if non-`NIL`, will be the stub's docstring. If `NIL`, then
      a generic docstring that says what system it autoloads will be
      used.
    
    The dummy class is defined at [compile time][27c6] too to
    approximate the semantics of [`DEFCLASS`][ead6]. The dummy class is a
    [`STANDARD-CLASS`][c77f] with no superclasses or slots. These are visible
    through introspection e.g. via `CLOSER-MOP:CLASS-DIRECT-SUPERCLASSES`.
    Introspection does not trigger autoloading.
    
    When `AUTOLOAD-CLASS` is macroexpanded during the compilation or
    loading of an [`AUTOLOAD-SYSTEM`][cd2d], it signals an [`AUTOLOAD-WARNING`][da95] if
    `SYSTEM-NAME` is not among those declared in [`:AUTO-DEPENDS-ON`][9b08].
    
    Note that [`INITIALIZE-INSTANCE`][1466] `:AROUND` methods specialized on a
    subclass of `CLASS-NAME` may run twice in the context of the
    `MAKE-INSTANCE` that triggers autoloading.

<a id="x-28AUTOLOAD-3AAUTOLOAD-CLASS-P-20FUNCTION-29"></a>

- [function] **AUTOLOAD-CLASS-P** *CLASS-DESIGNATOR*

    See if the class denoted by `CLASS-DESIGNATOR` was declared as an
    [`AUTOLOAD-CLASS`][9d6b] and was not redefined or deleted since. Subclasses do
    not inherit this property.

<a id="x-28AUTOLOAD-3ADEFCLASS-2FAUTO-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFCLASS/AUTO** *NAME DIRECT-SUPERCLASSES DIRECT-SLOTS &REST OPTIONS*

    Like [`DEFCLASS`][ead6], but mark the class for [Automatically Generating Loaddefs][c1d4]. See
    [`EXTRACT-LOADDEFS`][dd7e] for the corresponding [loaddef][e4a5].
    
    Also, warn if `NAME` has never been [`AUTOLOAD-CLASS-P`][37fc].
    
    `NAME` may be of the form (`DEFINER` `NAME`). In that case, instead of
    `DEFCLASS`, `DEFINER` is used.

<a id="x-28AUTOLOAD-3A-40VARIABLES-20MGL-PAX-3ASECTION-29"></a>

### 3.5 Variables

<a id="x-28AUTOLOAD-3ADEFVAR-2FAUTO-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFVAR/AUTO** *VAR &OPTIONAL (VAL NIL) DOC*

    Like [`DEFVAR`][7334], but mark the variable for [Automatically Generating Loaddefs][c1d4]. See
    [`EXTRACT-LOADDEFS`][dd7e] for the corresponding [loaddef][e4a5].
    
    Also, this works with the *global* binding on Lisps that support
    it (currently Allegro, CCL, ECL, SBCL). This is to handle the case
    when a system that uses `DEFVAR` with a default value is autoloaded
    while that variable is locally bound:
    
    ```common-lisp
    ;; Some base system only foreshadows *X*.
    (declaim (special *x*))
    (let ((*x* 1))
      ;; Imagine that the system that defines *X* is autoloaded here.
      (defvar/auto *x* 2)
      *x*)
    => 1
    ```
    
    In case the global binding has been set between the [corresponding
    loaddef][dd7e] and the first evaluation of this form,
    `VAL` is evaluated for side effect.
    
    `DEFVAR/AUTO` warns if `VAR` does not have a loaddef in
    [`:AUTO-LOADDEFS`][0724].
    
    `VAR` may be of the form (`DEFINER` `VAR`). In that case, instead of
    `DEFVAR`, `DEFINER` is used. Note that [`DEFPARAMETER`][570e] is not a suitable
    `DEFINER`, as it doesn't follow `DEFVAR` semantics.

<a id="x-28AUTOLOAD-3A-40PACKAGES-20MGL-PAX-3ASECTION-29"></a>

### 3.6 Packages

<a id="x-28AUTOLOAD-3ADEFPACKAGE-2FAUTO-20MGL-PAX-3AMACRO-29"></a>

- [macro] **DEFPACKAGE/AUTO** *NAME &REST OPTIONS*

    Like [`DEFPACKAGE`][9b43], but mark the package for [Automatically Generating Loaddefs][c1d4] and
    extend the existing definition additively. See [`EXTRACT-LOADDEFS`][dd7e] for
    the corresponding [loaddef][e4a5]s.
    
    The additivity means that instead of replacing the package
    definition or signalling errors on redefinition, it expands into
    individual package-altering operations such as [`SHADOW`][d0c4], [`USE-PACKAGE`][2264]
    and [`EXPORT`][0c4f]. This allows the package state to be built incrementally,
    but the `(DEFINER NAME)` syntax is not supported. `DEFPACKAGE/AUTO`
    may be used on the same package multiple times.
    
    In addition, `DEFPACKAGE/AUTO` deviates from `DEFPACKAGE` in the
    following ways.
    
    - The default `:USE` list is empty.
    
    - `:SIZE` is not supported.
    
    - Implementation-specific extensions such as `:LOCAL-NICKNAMES` are
      not supported. Use `ADD-PACKAGE-LOCAL-NICKNAME` after the
      `DEFPACKAGE/AUTO`.
    
    Alternatively, one may use, for example, `DEFPACKAGE` or
    `UIOP:DEFINE-PACKAGE` and arrange for [Automatically Generating Loaddefs][c1d4] for the
    package by listing it in `:PACKAGES` of [`:AUTO-LOADDEFS`][0724].

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
    [`DEFPACKAGE/AUTO`][aa0e] in `dyndep` or [`:AUTO-LOADDEFS`][0724] specifies
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
    `ASDF:COERCE-NAME`. It is an [`AUTOLOAD-WARNING`][da95] if an [autoload][c7d6]
    refers to a system not listed here. This is also used by
    [`EXTRACT-LOADDEFS`][dd7e] and affects the checks performed by the [`AUTOLOAD`][7da0]
    macro.

<a id="x-28AUTOLOAD-3ASYSTEM-AUTO-LOADDEFS-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29"></a>

- [reader] **SYSTEM-AUTO-LOADDEFS** *[AUTOLOAD-SYSTEM][cd2d] (:AUTO-LOADDEFS = NIL)*

    When non-`NIL`, this specifies arguments for
    [Automatically Generating Loaddefs][c1d4]. It may be a single pathname designator or a
    list of the form
    
        (loaddefs-file &key (process-arglist t) (process-docstring t)
                            packages (test t))
    
    - `LOADDEFS-FILE` designates the pathname where [`RECORD-LOADDEFS`][e90c] writes the [extracted loaddefs][dd7e].
      The pathname is relative to `ASDF:SYSTEM-SOURCE-DIRECTORY` of
      `SYSTEM` and is [`OPEN`][6547]ed with `:IF-EXISTS` `:SUPERSEDE`.
    
    - `PROCESS-ARGLIST`, `PROCESS-DOCSTRING` and `PACKAGES`
      are passed on by `RECORD-LOADDEFS` to `EXTRACT-LOADDEFS`.
    
    - If `TEST`, then [`CHECK-LOADDEFS`][451b] is run by `ASDF:TEST-SYSTEM`.
    
    Conditions signalled while ASDF is compiling or loading the file
    given have a [`RECORD-LOADDEFS`][3d01] restart.

<a id="x-28AUTOLOAD-3AAUTODEPS-20FUNCTION-29"></a>

- [function] **AUTODEPS** *SYSTEM &KEY (CROSS-AUTOLOADED T) INSTALLER*

    Return the list of the names of systems that may be autoloaded by
    `SYSTEM` or any of its direct or indirect dependencies. This
    recursively visits systems in the dependency tree, traversing both
    normal (`:DEPENDS-ON`) and autoloaded ([`:AUTO-DEPENDS-ON`][9b08]) dependencies.
    It works even if `SYSTEM` is not an [`AUTOLOAD-SYSTEM`][cd2d].
    
    - `CROSS-AUTOLOADED` controls whether systems only reachable from
      `SYSTEM` via intermediate autoloaded dependencies are visited. Thus,
      if `CROSS-AUTOLOADED` is `NIL`, then the returned list is the first
      boundary of autoloaded systems.
    
    - If `INSTALLER` is non-`NIL`, it is called when an autoloaded system
      that is not installed (i.e. `ASDF:FIND-SYSTEM` fails) is visited.
      `INSTALLER` is passed a single argument, the name of the system to
      be installed. It may or may not install the system.
    
    If an autoloaded system is not installed (i.e. `ASDF:FIND-SYSTEM`
    fails, even after `INSTALLER` had a chance), then its dependencies are
    unknown and cannot be traversed. Note that autoloaded systems that
    are not installed are still visited and included in the returned
    list.
    
    The following example makes sure that all autoloaded dependencies
    (direct or indirect) of `my-system` are installed:
    
        (autodeps "my-system" :installer #'ql:quickload)

<a id="x-28AUTOLOAD-3A-40AUTOMATIC-LOADDEFS-20MGL-PAX-3ASECTION-29"></a>

### 4.1 Automatically Generating Loaddefs

<a id="x-28AUTOLOAD-3AEXTRACT-LOADDEFS-20FUNCTION-29"></a>

- [function] **EXTRACT-LOADDEFS** *SYSTEM &KEY (PROCESS-ARGLIST T) (PROCESS-DOCSTRING T) PACKAGES*

    Return a list of [loaddef][e4a5] forms that set up autoloading
    for definitions such as [`DEFUN/AUTO`][a825] in [`:AUTO-DEPENDS-ON`][9b08] of
    `SYSTEM`.
    
    There is rarely a need to call this function directly, as
    [`RECORD-LOADDEFS`][e90c] and [`CHECK-LOADDEFS`][451b] provide
    [ASDF Integration][0c5c].
    
    Note that this is an expensive operation, as it loads or reloads the
    direct dependencies one by one with `ASDF:LOAD-SYSTEM` `:FORCE` `T` and
    records the association with the system and the autoloaded
    definitions such as `DEFUN/AUTO`.
    
    - For function definitions such as `DEFUN/AUTO`, an [`AUTOLOAD`][7da0] [loaddef][e4a5]
    is emitted.
    
        If `PROCESS-ARGLIST` is `T`, then the autoload forms will pass the
        `ARGLIST` argument of the corresponding `DEFUN/AUTO` to `AUTOLOAD`. If
        it is `NIL`, then `ARGLIST` will not be passed to `AUTOLOAD`.
    
    - For class definitions such as [`DEFCLASS/AUTO`][ee20], an [`AUTOLOAD-CLASS`][9d6b]
    [loaddef][e4a5] is emitted.
    
    - For [`DEFVAR/AUTO`][3cff], the emitted [loaddef][e4a5] declaims the variable
    special and maybe sets its initial value and docstring.
    
        If the initial value form in `DEFVAR/AUTO` is detected as a simple
        constant form, then it is evaluated and its value is assigned to
        the variable as in [`DEFVAR`][7334]. Simple constant forms are strings,
        numbers, characters, keywords, constants in the CL package, and
        [`QUOTE`][f5d0]d nested lists containing any of the previous or any symbol
        from the `CL` package.
    
    - For [`DEFPACKAGE/AUTO`][aa0e] and the provided `PACKAGES`,
    individual package-altering [loaddef][e4a5]s are emitted.
    
        As in the expansion of `DEFPACKAGE/AUTO` itself, these
        operations are additive. To handle circular dependencies, first
        all packages are created, then their state is reconstructed in
        phases following [`DEFPACKAGE`][9b43].
    
        Any reference to non-existent packages (e.g. in `:USE`) or symbols
        in non-existent packages (e.g. `:IMPORT-FROM`) is silently
        skipped.
    
    - If `PROCESS-DOCSTRING`, then the docstrings extracted from [auto][a159]
      definitions will be associated with the definition.
    
    Note that if a function is not defined with `DEFUN/AUTO`, then
    `EXTRACT-LOADDEFS` will not detect it. For such functions, `AUTOLOAD`
    forms must be written manually. Similar considerations apply to
    variables and packages.

<a id="x-28AUTOLOAD-3AWRITE-LOADDEFS-20FUNCTION-29"></a>

- [function] **WRITE-LOADDEFS** *LOADDEFS STREAM*

    Write `LOADDEFS` to `STREAM` so they can be [`LOAD`][b5ec]ed or included in an
    `ASDF:DEFSYSTEM`.

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
    
    - If there is an [`:AUTO-LOADDEFS`][0724], check that the file generated by
      [`RECORD-LOADDEFS`][e90c] is up-to-date.
    
    - Check that all manual (non-generated) autoload declarations with
      [`AUTOLOAD`][7da0]s in `SYSTEM` are resolved (the corresponding function or
      variable is defined) by loading [`:AUTO-DEPENDS-ON`][9b08].
    
    If `ERRORP`, then signal an error if a check fails or the loaddefs
    file cannot be read. If [`:AUTO-LOADDEFS`][0724] is specified, then the
    [`RECORD-LOADDEFS`][3d01] restart is provided.
    
    If `ERRORP` is `NIL`, then instead of signalling an error, return `NIL`.
    
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
  [1466]: http://www.lispworks.com/documentation/HyperSpec/Body/f_init_i.htm "INITIALIZE-INSTANCE (MGL-PAX:CLHS GENERIC-FUNCTION)"
  [1f37]: http://www.lispworks.com/documentation/HyperSpec/Body/t_class.htm "CLASS (MGL-PAX:CLHS CLASS)"
  [2264]: http://www.lispworks.com/documentation/HyperSpec/Body/f_use_pk.htm "USE-PACKAGE (MGL-PAX:CLHS FUNCTION)"
  [27c6]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_c.htm#compile_time "\"compile time\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [37fc]: #x-28AUTOLOAD-3AAUTOLOAD-CLASS-P-20FUNCTION-29 "AUTOLOAD:AUTOLOAD-CLASS-P FUNCTION"
  [38fe]: #x-28AUTOLOAD-3A-40CLASSES-20MGL-PAX-3ASECTION-29 "Classes"
  [39df]: http://www.lispworks.com/documentation/HyperSpec/Body/m_w_std_.htm "WITH-STANDARD-IO-SYNTAX (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [3cff]: #x-28AUTOLOAD-3ADEFVAR-2FAUTO-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFVAR/AUTO MGL-PAX:MACRO"
  [3d01]: #x-28AUTOLOAD-3ARECORD-LOADDEFS-20RESTART-29 "AUTOLOAD:RECORD-LOADDEFS RESTART"
  [451b]: #x-28AUTOLOAD-3ACHECK-LOADDEFS-20FUNCTION-29 "AUTOLOAD:CHECK-LOADDEFS FUNCTION"
  [471f]: #x-28AUTOLOAD-3A-40INTRODUCTION-20MGL-PAX-3ASECTION-29 "Introduction"
  [4b04]: #x-28AUTOLOAD-3A-40FUNCTIONS-20MGL-PAX-3ASECTION-29 "Functions"
  [51fe]: http://www.lispworks.com/documentation/HyperSpec/Body/f_find_c.htm "FIND-CLASS (MGL-PAX:CLHS FUNCTION)"
  [53ee]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_c.htm#compiled_file "\"compiled file\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [570e]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defpar.htm "DEFPARAMETER (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [5968]: #x-28-22autoload-22-20ASDF-2FSYSTEM-3ASYSTEM-29 "\"autoload\" ASDF/SYSTEM:SYSTEM"
  [5b87]: #x-28AUTOLOAD-3ADEFGENERIC-2FAUTO-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFGENERIC/AUTO MGL-PAX:MACRO"
  [609c]: http://www.lispworks.com/documentation/HyperSpec/Body/f_fmakun.htm "FMAKUNBOUND (MGL-PAX:CLHS FUNCTION)"
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
  [9b08]: #x-28AUTOLOAD-3ASYSTEM-AUTO-DEPENDS-ON-20-28MGL-PAX-3AREADER-20AUTOLOAD-3AAUTOLOAD-SYSTEM-29-29 "AUTOLOAD:SYSTEM-AUTO-DEPENDS-ON (MGL-PAX:READER AUTOLOAD:AUTOLOAD-SYSTEM)"
  [9b43]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defpkg.htm "DEFPACKAGE (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [9d6b]: #x-28AUTOLOAD-3AAUTOLOAD-CLASS-20MGL-PAX-3AMACRO-29 "AUTOLOAD:AUTOLOAD-CLASS MGL-PAX:MACRO"
  [a159]: #x-28AUTOLOAD-3A-40AUTO-20MGL-PAX-3AGLOSSARY-TERM-29 "auto"
  [a515]: #x-28AUTOLOAD-3AAUTOLOAD-ERROR-20CONDITION-29 "AUTOLOAD:AUTOLOAD-ERROR CONDITION"
  [a825]: #x-28AUTOLOAD-3ADEFUN-2FAUTO-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFUN/AUTO MGL-PAX:MACRO"
  [aa0e]: #x-28AUTOLOAD-3ADEFPACKAGE-2FAUTO-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFPACKAGE/AUTO MGL-PAX:MACRO"
  [ae25]: https://www.quicklisp.org/ "Quicklisp"
  [b5ec]: http://www.lispworks.com/documentation/HyperSpec/Body/f_load.htm "LOAD (MGL-PAX:CLHS FUNCTION)"
  [c1d4]: #x-28AUTOLOAD-3A-40AUTOMATIC-LOADDEFS-20MGL-PAX-3ASECTION-29 "Automatically Generating Loaddefs"
  [c77f]: http://www.lispworks.com/documentation/HyperSpec/Body/t_std_cl.htm "STANDARD-CLASS (MGL-PAX:CLHS CLASS)"
  [c7d6]: #x-28AUTOLOAD-3A-40AUTOLOAD-20MGL-PAX-3AGLOSSARY-TERM-29 "autoload"
  [cd2d]: #x-28AUTOLOAD-3AAUTOLOAD-SYSTEM-20CLASS-29 "AUTOLOAD:AUTOLOAD-SYSTEM CLASS"
  [d0c4]: http://www.lispworks.com/documentation/HyperSpec/Body/f_shadow.htm "SHADOW (MGL-PAX:CLHS FUNCTION)"
  [d162]: http://www.lispworks.com/documentation/HyperSpec/Body/e_error.htm "ERROR (MGL-PAX:CLHS CONDITION)"
  [d60b]: #x-28AUTOLOAD-3A-40LINKS-AND-SYSTEMS-20MGL-PAX-3ASECTION-29 "Links and Systems"
  [d78c]: https://slime.common-lisp.dev/doc/html/slime_002dautodoc_002dmode.html#slime_002dautodoc_002dmode "SLIME autodoc"
  [d811]: http://www.lispworks.com/documentation/HyperSpec/Body/f_apply.htm "APPLY (MGL-PAX:CLHS FUNCTION)"
  [da95]: #x-28AUTOLOAD-3AAUTOLOAD-WARNING-20CONDITION-29 "AUTOLOAD:AUTOLOAD-WARNING CONDITION"
  [dd7e]: #x-28AUTOLOAD-3AEXTRACT-LOADDEFS-20FUNCTION-29 "AUTOLOAD:EXTRACT-LOADDEFS FUNCTION"
  [dddd]: http://www.lispworks.com/documentation/HyperSpec/Body/f_mk_ins.htm "MAKE-INSTANCE (MGL-PAX:CLHS GENERIC-FUNCTION)"
  [ddfa]: #x-28AUTOLOAD-3A-40LOADING-SYSTEMS-20MGL-PAX-3ASECTION-29 "Loading Systems"
  [e4a5]: #x-28AUTOLOAD-3A-40LOADDEF-20MGL-PAX-3AGLOSSARY-TERM-29 "loaddef"
  [e8f2]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_s.htm#source_file "\"source file\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [e90c]: #x-28AUTOLOAD-3ARECORD-LOADDEFS-20FUNCTION-29 "AUTOLOAD:RECORD-LOADDEFS FUNCTION"
  [ea6a]: http://www.lispworks.com/documentation/HyperSpec/Body/26_glo_c.htm#condition_handler "\"condition handler\" (MGL-PAX:CLHS MGL-PAX:GLOSSARY-TERM)"
  [ead6]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defcla.htm "DEFCLASS (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [ebea]: http://www.lispworks.com/documentation/HyperSpec/Body/m_declai.htm "DECLAIM (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [ee20]: #x-28AUTOLOAD-3ADEFCLASS-2FAUTO-20MGL-PAX-3AMACRO-29 "AUTOLOAD:DEFCLASS/AUTO MGL-PAX:MACRO"
  [eea4]: http://www.lispworks.com/documentation/HyperSpec/Body/f_fdefin.htm "FDEFINITION (MGL-PAX:CLHS FUNCTION)"
  [f43d]: #x-28AUTOLOAD-3A-40CONDITIONS-20MGL-PAX-3ASECTION-29 "Conditions"
  [f472]: http://www.lispworks.com/documentation/HyperSpec/Body/m_defun.htm "DEFUN (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [f490]: #x-28AUTOLOAD-3A-40VARIABLES-20MGL-PAX-3ASECTION-29 "Variables"
  [f5d0]: http://www.lispworks.com/documentation/HyperSpec/Body/s_quote.htm "QUOTE (MGL-PAX:CLHS MGL-PAX:MACRO)"
  [fa90]: #x-28AUTOLOAD-3A-40BASICS-20MGL-PAX-3ASECTION-29 "Basics"
  [fc62]: http://www.lispworks.com/documentation/HyperSpec/Body/e_smp_wa.htm "SIMPLE-WARNING (MGL-PAX:CLHS CONDITION)"

* * *
###### \[generated by [MGL-PAX](https://github.com/melisgl/mgl-pax)\]
