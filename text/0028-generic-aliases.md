---
Feature Name: "generic-aliases"
Start Date: 2026-05-23
RFC PR: "https://github.com/crystal-lang/rfcs/pull/28"
Issue: "https://github.com/crystal-lang/crystal/issues/2803"
Implementation PR: "https://github.com/crystal-lang/crystal/pull/16955"
---

## Summary

Allow `alias` declarations to take type parameters, so an alias body can refer to those parameters and resolve to a different concrete type at each use site:

```crystal
alias Maybe(T)        = T | Nil
alias StringKeyed(V)  = Hash(String, V)
alias Pair(K, V)      = Tuple(K, V)
```

A generic alias is usable everywhere a regular type is: as a type restriction, in type declarations, in generic instantiations, in metaclass expressions, and as the restriction of a `forall T` method.

## Motivation

Aliases today are purely substitutional with no parameters. To express a parameterised shape — a nullable wrapper, a string-keyed map, a labelled pair — the alias body must hard-code its element type, so every variant of the shape needs its own alias:

```crystal
alias MaybeInt32  = Int32 | Nil
alias MaybeString = String | Nil
alias MaybeUser   = User | Nil
```

This is the central case raised in [#2803](https://github.com/crystal-lang/crystal/issues/2803). It also shows up wherever a project ports a generic shape from another language or stdlib idiom (`Optional<T>`, `Result<T, E>`, `Map<K, V>`-style wrappers) — without generic aliases, the standard workaround is to introduce an empty subclass or module, which carries dispatch and runtime cost that an alias would not.

Generic aliases are purely a naming feature. They produce no runtime artefacts, no new types, and no new dispatch — at every use site they substitute their body, exactly as non-generic aliases do today. The motivation is therefore expressiveness and call-site ergonomics, not new semantics.

The expected outcome: any place a user would today write `Hash(String, V)` they can instead write `StringKeyed(V)` — including when `V` is itself an unresolved free variable bound by a surrounding `forall V`.

## Guide-level explanation

A generic alias is an `alias` declaration with one or more type parameters in parentheses after the name. The parameters are in scope inside the body and stand for whatever types are supplied at the use site:

```crystal
alias Maybe(T)       = T | Nil
alias StringKeyed(V) = Hash(String, V)
alias Pair(K, V)     = Tuple(K, V)
```

Using a generic alias looks like using any other generic type — the alias name is followed by type arguments in parentheses, and arguments are substituted into the body positionally:

```crystal
x : Maybe(Int32)         = 1                # resolves to Int32 | Nil
y = StringKeyed(Int32).new                  # resolves to Hash(String, Int32)
p = Pair(Symbol, String).new(:hello, "hi")  # resolves to Tuple(Symbol, String)
```

The alias is transparent at the use site. The compiler produces exactly the same program as if the user had written the substituted form directly. There is no `Maybe` type at runtime, no method-dispatch difference, and no class hierarchy distinction between `Maybe(Int32)` and `Int32 | Nil` — they are the same type.



### Wrong arity

Passing the wrong number of type arguments to a generic alias produces a clear compile-time error pointing at the alias use:

```crystal
alias Pair(K, V) = Tuple(K, V)

Pair(Int32) # Error: wrong number of type vars for Pair (given 1, expected 2)
```


### How to think about it

Mentally, a generic alias is a _function from type arguments to a type_. At every use site the compiler evaluates that function and the rest of the program proceeds as if the user had written the result. Nothing about the runtime model of Crystal changes; this is purely a way to factor out repetition in type-level expressions.

## Reference-level explanation

### Syntax

`alias` declarations gain an optional parenthesised list of type parameters after the name:

```
alias_decl ::= "alias" const_path type_param_list? "=" type_expr
type_param_list ::= "(" IDENT ("," IDENT)* ")"
```

`alias Foo = ...` keeps its current meaning. `alias Foo(T) = ...` introduces `T` as a type parameter bound only inside the body.

Splat parameters (`alias Foo(*T) = ...`) are explicitly rejected at parse time. They do not yet have well-defined semantics, and the position is reserved for a follow-up RFC.

### Semantics

A generic alias is a type-level template. The parameters are formally free variables of the alias body. Resolving the alias name with arguments produces the body with parameters substituted positionally; the result is then resolved exactly as if the user had written it literally.

```crystal
alias Maybe(T)       = T | Nil
alias StringKeyed(V) = Hash(String, V)
alias Pair(K, V)     = Tuple(K, V)

Maybe(Int32)               == Int32 | Nil                # => true
StringKeyed(User)          == Hash(String, User)         # => true
Pair(Symbol, Maybe(Int32)) == Tuple(Symbol, Int32 | Nil) # => true
```

No new type is introduced; in particular, `Maybe(Int32)` and `Int32 | Nil` are the _same_ type for every purpose the compiler cares about (`is_a?`, `==`, virtual dispatch, generic instantiation cache keys).

#### Use sites

A generic alias resolves wherever a type can be written:

1. **As a metaclass expression.** `Maybe(Int32)` evaluates to the metaclass `(Int32 | Nil).class`.
2. **As a restriction or type declaration.** `: Pair(K, V)` in an argument restriction, type declaration, or `@x : Maybe(Int32)` instance var declaration. Matching proceeds against the substituted type.
3. **Inside generic instantiations.** `Hash(String, Maybe(V))` resolves to `Hash(String, V | Nil)`.
4. **Inside `forall T` restrictions.** When the alias body itself contains a free variable bound by the surrounding `forall`, the matcher expands the alias before unification.

#### Recursive aliases


A generic alias that recursively references itself with the same type parameters expands like any other recursive alias. A generic alias that references itself with _different_ type parameters expands the substitution at each use; if no fixed point exists, the compiler reports a "recursive alias can't be expanded" error at the use site, mirroring the existing behaviour for non-generic aliases that can't be resolved.

#### Arity checking

Calling a generic alias with the wrong number of type arguments is a compile-time error, reported at the use site with reference to the alias declaration:

```
wrong number of type vars for Pair (given 1, expected 2)
```

A non-generic alias used with type arguments (`Maybe(Int32)` where `Maybe` was declared without parameters) is also an error, with the same wording.

### How it composes with existing features

- **Restrictions.** A generic alias appearing in a restriction expands inside the matcher _before_ the existing restriction algorithm runs. The matcher sees only the substituted form, so `def f(x : Maybe(T)) forall T` behaves identically to `def f(x : T | Nil) forall T`.

- **Generic instantiations.** A generic alias passed as a type argument to another generic (`Array(Maybe(Int32))`) is substituted first, then the outer generic is instantiated with the result.

- **`typeof`.** Already substitutes through aliases; generic aliases just extend that substitution to take arguments.

- **`is_a?` / `as` / `responds_to?`.** Operate on the substituted type. `x.is_a?(Maybe(Int32))` is equivalent to `x.is_a?(Int32 | Nil)`.

- **`{% ... %}` macros.** A generic alias is a `TypeNode` like any other. `Maybe(Int32).resolve` returns the resolved type of the substituted body. Macros that walk type expressions see the alias name and its arguments, not the expanded body, until they call `.resolve`.

- **Documentation.** A generic alias is documented as `Maybe(T)` with `T` as a free type parameter, exactly as a generic class would be.


## Drawbacks

- **More syntax to learn.** Today `alias` is a one-shape declaration; this adds a second shape. The notation is the same one already used for generic classes, so the cost is modest, but it is non-zero.

- **Conflation risk.** Generic classes (`class Foo(T)`) and generic aliases (`alias Foo(T) = ...`) look superficially similar at the use site but have very different semantics — one introduces a new type, the other substitutes. A user could in principle adopt an alias where a class would have been more appropriate (e.g. wanting nominal distinctness), or vice versa.

- **Error-message surface.** Errors that arise from substitution inside the alias body need to be attributable to both the alias declaration and the use site. Lower-quality diagnostics here would be a regression for readability.

- **Recursive expansion edge cases.** Recursive non-generic aliases already have well-known sharp edges; permitting recursion through type parameters expands the space of expressions that can fail to resolve. The error case must remain a clean compile-time error, not a stack overflow or hang.

## Rationale and alternatives

- **Just use a class or module.** Today's workaround is `class Maybe(T) < (T | Nil); end` (which doesn't compile because you can't inherit a union), or a wrapper class with delegation. The first doesn't work; the second introduces runtime overhead and breaks reference equality with the underlying value. A purely substitutional generic alias is the only way to give the shape a name without changing the runtime model.

- **Macro-based alternative.** A `macro maybe(t)` could generate `\\{{t}} | Nil`, but it isn't usable in restrictions, doesn't compose inside generic instantiations the same way, doesn't participate in `forall` unification, and its diagnostics are poor. Generic aliases are first-class in the type system in all of those positions.

- **Defer until a richer "type alias" story.** Some languages distinguish between "transparent" aliases (substitution) and "opaque" aliases (nominally distinct newtypes). This RFC proposes only the transparent variant — it is the smaller change and it matches what `alias` already does. A future RFC could add an opaque variant under a different keyword without conflicting with this design.

- **Splat type parameters.** Deliberately deferred. The semantics around `alias Foo(*T) = Tuple(*T)` versus `alias Foo(*T) = ...` interacting with `forall` are non-obvious and warrant their own design. Rejecting splats at parse time keeps the door open.

The impact of _not_ doing this is a continuing pattern of either copy-pasted aliases or unnecessary wrapper classes. Both make API surfaces noisier and harder to maintain.

## Prior art

- **Rust.** `type Maybe<T> = Option<T>;` is supported and uses essentially identical semantics: transparent substitution, full participation in trait bounds and `where` clauses.

- **Scala 3.** `type Maybe[T] = T | Null` is supported, transparent at use sites, and interacts with implicit search and type inference exactly as if the body had been written directly.

- **TypeScript.** `type Maybe<T> = T | null` is the canonical introduction to TypeScript type aliases — generic aliases are the primary use case for `type` declarations in TS, and the substitutional model is exactly what users expect.

- **Haskell.** `type Maybe a = ...` (type synonyms) are transparent and support multiple parameters. Haskell additionally distinguishes `type` (transparent) from `newtype` (opaque) — the present RFC corresponds to `type`.

- **Crystal itself.** The non-generic `alias Foo = SomeType` form has the right shape; this RFC extends it along the dimension users already understand from `class Foo(T)`.

Across these languages, transparent generic type aliases have been low-friction additions: they slot into the rest of the type system without surprising interactions, and once available are quickly adopted in idiomatic API design.

## Unresolved questions

- **Variadic type parameters.** Whether `alias Foo(*T) = ...` should mean "splat into a tuple body" or something more general. Punted to a follow-up RFC.

- **Constraints on type parameters.** Whether `alias Foo(T : Number) = ...` should be supported. Generic classes don't constrain their parameters this way today either, so the cleanest answer is "not in this RFC, and only if generic classes get the same affordance."

- **Type-level computation in the body.** Whether the body of a generic alias should be allowed to contain macro expressions over its type parameters (`{% ... %}` operating on `T`). Out of scope here.

## Future possibilities

- **Opaque newtypes.** A future `newtype Foo(T) = ...` (or similar keyword) introducing a nominally-distinct type with the same shape would compose naturally with the transparent variant proposed here.

- **Variadic parameters.** Once the semantics are clear, lifting the parse-time restriction to allow `alias Foo(*T) = ...`.

- **Default arguments.** `alias Maybe(T = Nil) = T | Nil` and similar defaults would mirror what generic classes might one day support.

- **Module-level aliases.** Generic aliases inside generic modules referring to the module's own type parameters compose well with this design and need no extra work, but it is worth confirming as the implementation lands.
