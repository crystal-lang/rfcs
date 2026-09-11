---
Feature Name: "module-prepend"
Start Date: 2026-05-23
RFC PR: "https://github.com/crystal-lang/rfcs/pull/29"
Issue: "https://github.com/crystal-lang/crystal/issues/10504"
Implementation PR: "https://github.com/crystal-lang/crystal/pull/16953"
---

## Summary

Add `prepend` as a class/module/struct body keyword, analogous to `include` and `extend`, that inserts a module _ahead_ of the enclosing type in method lookup. Methods in a prepended module override the type's own methods of the same name and can delegate to them with `super`.

```crystal
class Base
  def foo; puts "Base"; end
end

module Tracer
  def foo
    puts "Tracer"
    super
  end
end

class Service < Base
  prepend Tracer
  def foo; puts "Service"; super; end
end

Service.new.foo
# Tracer
# Service
# Base
```

## Motivation

Crystal has no way to package a method wrapper as a reusable artifact. `include` places a module _behind_ the host in method lookup, so a mixin can never run around a method the host defines itself. `previous_def` wraps a method in place, but only by reopening the class and hand-writing a redefinition at every host.

The demand is concrete, and it comes from the people building instrumentation. [crystal-lang/crystal#10504](https://github.com/crystal-lang/crystal/issues/10504) has been open since 2021 with core-team support ("could eliminate the need for `previous_def`" — @asterite) and backing from @wyhaines, whose [opentelemetry-instrumentation.cr](https://github.com/wyhaines/opentelemetry-instrumentation.cr) shows what the workaround looks like today: it reopens `HTTP::Server`, redefines `handle_client` around `previous_def`, and wraps the whole thing in `macro finished` "to ensure that all other classes have been loaded prior to loading the instrumentation" — because `previous_def` only sees definitions compiled before it. The [datadog shard](https://github.com/jgaskins/datadog) doesn't attempt automatic instrumentation at all; users wrap each call site by hand.

`previous_def` is simple and remains the right tool for a one-off patch. What it structurally cannot do, and what `prepend` adds:

- **Reusable wrappers.** A retry/timing/tracing wrapper built on `previous_def` must be copied into a class-reopening per host and per method. A prepended module is written once; a host opts in with one line, and `macro prepended` lets the module set up per-host state at that moment.
- **Order independence.** `previous_def` requires the original definition to be compiled first — hence the `macro finished` contortions above, which every instrumentation author must rediscover. `prepend` builds the lookup chain from declarations; require order is irrelevant.
- **Mixins that wrap host methods.** An included module can only supply methods the host _doesn't_ define. There is currently no way for a mixin to run around a method the host does define — e.g. a `Memoize` or `Audited` module wrapping the host's own implementation via `super`. `prepend` makes that expressible at all.
- **Visible composition.** Stacked `previous_def` patches live wherever the reopenings happen to be, ordered by require order. Stacked prepends are listed in the host's body, in declared order, and removing one is removing one line.

Ruby went through exactly this evolution: before `Module#prepend` (Ruby 2.0) the ecosystem wrapped methods with `alias_method_chain`, and Rails deprecated it in 5.0 and removed it in 5.1 once prepend existed. Crystal's `previous_def` is a cleaner version of the same in-place idiom — and shares its ceiling: the wrapper is not a module, so it cannot be shared, shipped, or composed declaratively.

## Guide-level explanation

`prepend Mod` is the third way (after `include` and `extend`) to mix a module into a type. Where `include` adds the module _after_ the host in method lookup, `prepend` adds it _before_: the prepended module's methods are found first, and the host's methods are reachable through `super`.

The full lookup order is:

```
prepended modules (most recently prepended first)
self
included modules / parent classes (regular ancestors, as today)
```

```crystal
module Included
  def foo; "Included(#{super})"; end
end

module Prepended
  def foo; "Prepended(#{super})"; end
end

class Base
  def foo; "Base"; end
end

class Service < Base
  prepend Prepended
  include Included
  def foo; "Service(#{super})"; end
end

Service.new.foo # => "Prepended(Service(Included(Base)))"
```

Resolution order: `Prepended → Service → Included → Base`. Two points worth noting:

- `super` inside `Prepended#foo` continues the chain at `Service` — a prepended method knows it is wrapping.
- `super` inside `Service#foo` does _not_ re-enter the prepended modules; it walks the regular ancestors as today. The host is unaware it is wrapped, so existing `super` behaviour is unchanged.

Multiple prepends nest: each new `prepend` goes to the head of the chain, so the most recently prepended module is outermost, and each wrapper's `super` reaches the next one in.

A module can react to being prepended with `macro prepended`, which fires once per host with `@type` bound to the host — exactly parallel to `macro included` / `macro extended`. This lets a wrapper establish per-host state (class vars, generated helpers) when it's wired in.

Compile-time errors mirror `include`: prepending a non-module, prepending `self`, and cyclic prepends are all rejected. Prepending the same module twice is a no-op.

## Reference-level explanation

### Syntax

`prepend` is recognised as a body-level statement everywhere `include` and `extend` are. The grammar parallels `include` (`prepend_stmt ::= "prepend" type_expr`). It is reserved only in statement position; method-call use (`array.prepend(x)`) is unaffected.

### Semantics

Each `ModuleType` gains a `prepended_modules` list alongside its existing `parents`. `prepend Mod` inserts `Mod` at the head of that list. Method resolution for a receiver of static type `T` walks:

1. `T.prepended_modules`, head-first
2. `T`'s own methods
3. `T.parents`, as today

Steps 2 and 3 are unmodified. `super` resolves to the next definition after the current one in this chain — so `super` in `prepended_modules[i]` tries `prepended_modules[i+1]`, then `T`, then `T.parents`; `super` in `T` itself resolves only to `T.parents` and never re-enters the prepended modules. This asymmetry matches Ruby and keeps the host's `super` meaning unchanged.

`Type#ancestors` retains its current meaning (regular ancestors only), which is what makes `super`-from-host trivially correct. The macro-visible `TypeNode#ancestors` returns the full chain with prepended modules at the head, matching Ruby's `Module#ancestors`.

`macro prepended` is added via the existing `Hook` plumbing with a new `Prepended` kind.

`prepend GenericMod(T)` follows the same resolution rules as `include GenericMod(T)`. Prepending into a generic module is allowed: the prepended module sits ahead of the generic module in the lookup chain of every type that includes it.

### Errors

- **Cyclic prepend:** processing `prepend Mod` walks `Mod`'s regular and prepended ancestors; if the enclosing type appears, the declaration is rejected.
- **Non-module argument** and **`prepend self`** are rejected, as for `include`.
- **Duplicate prepend** is a no-op.

### AST

A new `Crystal::Prepend < ASTNode` mirrors `Include`, with the standard visitor, formatter, and `to_s` plumbing. No existing node's semantics change.

## Drawbacks

- **Action-at-a-distance.** A prepended module changes what a host's method does without the host's definition mentioning it — that is the point, but it can surprise a reader (this was the one objection raised on #10504). Mitigation: `prepend Mod` must appear literally in the host's body, so the wrapping is always one grep away, unlike a `previous_def` patch in an arbitrary file.
- **A second mechanism resembling `include`.** The difference only shows once a `super` is in play; documentation must make it concrete.
- **Keyword reservation.** Top-level `def prepend` would break. Method-call use sites (`array.prepend(x)`) continue to work.
- **The `super` asymmetry** (host's `super` skips the wrappers) is correct but non-obvious and needs a canonical example in the language reference.

## Rationale and alternatives

- **`previous_def` (status quo).** Covers in-place wrapping well; cannot produce a reusable wrapper, is require-order dependent, and gives a mixin no way to wrap host methods. See Motivation.
- **Proxies / delegators.** Change object identity (`is_a?`), break code expecting the underlying type, and need every method forwarded.
- **Macro-rewriting methods.** Functional but high-friction: each wrapper needs its own macro, and source locations suffer.
- **Dedicated "around"/decorator syntax.** Solves the same problem but invents a new sub-language; `prepend` reuses the module + `super` vocabulary users already know.

The proposed design is the smallest change that closes the gap: one keyword, one list per type, one targeted extension to `super` resolution — reusing the `include` machinery throughout.

## Prior art

- **Ruby.** `Module#prepend` (Ruby 2.0) is the direct model; the semantics above match it, including the host-`super` asymmetry and the `prepended` hook. It displaced `alias_method_chain` (deprecated Rails 5.0, removed 5.1) and after a decade in the wild is used most heavily by instrumentation and library-integration tools (Rails, AppSignal, Datadog).
- **Python decorators / AOP "around" advice** are the same pattern at method granularity; `prepend` is the module-level analogue.
- **Crystal `include`/`extend`.** The mechanics — body keyword, ancestor-chain entry, macro hook — are directly parallel, which is what keeps the implementation small.

## Unresolved questions

- **Keyword reservation scope.** Reserved everywhere (parallel to `include`, as proposed) or only inside type bodies, leaving top-level `def prepend` legal?
- **Macro API shape.** Should a separate `TypeNode#prepended` expose just the prepended chain, in addition to the full `TypeNode#ancestors`?

## Future possibilities

- Interaction with a future `final` method modifier (can a final method be wrapped?).
- With `prepend` available, `previous_def`-based monkey-patching in instrumentation shards can migrate to declarative modules, and stdlib types could grow documented extension points.
