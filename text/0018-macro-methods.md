---
Feature Name: macro-methods
Start Date: 2025-12-22
RFC PR: "https://github.com/crystal-lang/rfcs/pull/18"
Issue: "https://github.com/crystal-lang/crystal/issues/8835"
---

# Summary

User-defined macro methods (`macro def`) allow reusable logic within macros, reducing code duplication in macro-heavy codebases. Unlike regular macros which generate code, macro methods operate purely within the macro expansion context and return AST nodes.

# Motivation

Currently, Crystal macros can become repetitive when similar logic is needed across multiple macro definitions.
There's no way to extract common compile-time computations into reusable functions.
This leads to:

- Code duplication across macro definitions
- Difficulty maintaining complex macro logic
- No ability to compose compile-time operations

Macro methods solve this by allowing developers to define reusable functions that operate on AST nodes during macro expansion, similar to their runtime counterparts.

# Guide-level explanation

## Defining Macro Methods

A macro method is defined using `macro def` instead of `macro`:

```crystal
macro def format_name(name : StringLiteral) : StringLiteral
  name.underscore.upcase
end
```

Key differences from regular macros:

1. The body is pure macro expressions, evaluated directly; no need for macro control characters within it `{{ }}` or `{% %}`
2. Parameters and return types can specify expected AST node types
3. The last expression is returned as an AST node

## Calling Macro Methods

Macro methods are called from within macro expansion contexts (`{{ }}` or `{% %}`):

```crystal
macro generate_constant(name)
  CONST_{{ format_name(name) }} = "value"
end

generate_constant("myName")  # Generates: CONST_MY_NAME = "value"
```

## Type-Scoped Macro Methods

Macro methods can be defined within types and called with that type as receiver:

```crystal
class Foo
  macro def helper(items : ArrayLiteral) : ArrayLiteral
    items.map { |x| x.stringify }
  end
end

macro generate
  {{ Foo.helper([1, 2, 3]) }}  # => ["1", "2", "3"]
end
```

## Type Restrictions

Type restrictions use AST node type names:

```crystal
macro def process(value : StringLiteral | SymbolLiteral) : StringLiteral
  value.id.stringify
end
```

Any AST node type can be used such as `StringLiteral`, `NumberLiteral`, `ArrayLiteral`, etc.
`ASTNode` or no restriction may be used to to accept any type.

## Blocks

Macro methods support blocks via `&block`, or just `&` if it only yields and does not interact with the block parameter:

```crystal
macro def with_wrapper(&)
  "before " + yield + " after"
end

{{ with_wrapper { "content" } }}  # => "before content after"
```

## Visibility

Private macro methods cannot be called with an explicit receiver:

```crystal
class Foo
  private macro def internal_helper(x : StringLiteral) : StringLiteral
    x.upcase
  end

  macro generate
    {{ internal_helper("hello") }}  # OK
  end
end

{{ Foo.internal_helper("hello") }}  # Error: private macro method
```

# Reference-level explanation

## AST Representation

Macro methods use a dedicated `MacroDef` AST node, separate from `Macro`:

- `Macro` - Regular macros; body contains `MacroLiteral`/`MacroExpression` nodes
- `MacroDef` - Macro methods; body contains pure Crystal expressions

Both inherit from a common `MacroBase` abstract class sharing common properties: `name`, `args`, `body`, `visibility`, `doc`, `splat_index`, `double_splat`, `block_arg`.

`MacroDef` additionally has a `return_type` property.

## Execution Model

1. When the macro interpreter encounters a call within `{{ }}` or `{% %}`:
   - If the call has no receiver, search the current scope and program for matching `MacroDef`
   - If the call has a type receiver, search that type for matching `MacroDef`

2. When a matching macro method is found:
   - Validate argument types against parameter restrictions
   - Create a new interpreter scope with parameters bound to argument values
   - Execute the body as macro expressions
   - Validate the result against the return type restriction
   - Return the resulting AST node

## Coexistence with Regular Macros

A type can define both `macro foo` and `macro def foo`. They are called in different contexts:

```crystal
class Foo
  macro foo
    "from regular macro"
  end

  macro def foo : StringLiteral
    "from macro method"
  end
end

Foo.foo              # Calls regular macro (generates code)
{{ Foo.foo }}        # Calls macro method (returns AST node)
```

This works because:
- Regular macro lookup only considers `Macro` instances
- Macro method lookup only considers `MacroDef` instances

Additionally, it's currently possible for a class method to override a macro within a type, 
so allowing both types of macro to co-exist felt more consistent than raising an error or something.

## Type Validation

Type restrictions are validated at call time:

```crystal
macro def double(x : NumberLiteral) : NumberLiteral
  x * 2
end

{{ double("hello") }}  # Error: expected NumberLiteral, got StringLiteral
```

Validation uses compile-time type checking (`macro_is_a?`), which respects AST node inheritance.

# Drawbacks

- Adds another construct to learn alongside regular macros
- Users may be unclear when to use `macro` vs `macro def`
- Type restrictions only validate AST node types, not runtime types

# Rationale and alternatives

## Why a new `macro def` syntax?

The `macro def` syntax clearly distinguishes macro methods from regular macros:
- `macro` = generates code at compile time
- `macro def` = returns a value at macro expansion time
- `def` = same function as a `macro def`, but at runtime

Alternative considered: A flag on existing `Macro` (e.g., `@[MacroMethod]`). This was rejected because the body semantics differ significantly - macro methods don't use `{{ }}` for interpolation.
There also was talk about some sort of `macro class`, or some kind of `#expand` method within the existing macro API, but I felt `macro def` to be the best solution.
Both from how they are used, to how they can be documented and such as well.

## Why not extend the built-in macro methods?

Built-in methods like `stringify` are implemented in the compiler. User-defined macro methods allow the ecosystem to develop reusable macro utilities without compiler changes.

## Impact of not doing this

Without macro methods, complex macro libraries will continue to have duplicated logic, making them harder to maintain and evolve.

# Prior art

## Rust

Rust's procedural macros (`proc_macro`) operate on token streams and can define helper functions. However, they're more complex, requiring separate crate compilation. Crystal's macro methods are simpler - they're defined inline and operate on AST nodes directly.

## Nim

Nim has `template` (similar to Crystal's `macro`) and `macro` (which operates on AST nodes). Crystal's macro methods are comparable to Nim's `macro` in that both work with AST representations.

## Elixir

Elixir macros can call regular functions during expansion. Crystal's approach is more explicit - macro methods are clearly marked as operating at compile time.

# Unresolved questions

- Should macro methods support overloading based on type restrictions?
- Should there be a way to define macro methods that work across multiple types (like extension methods)?

# Future possibilities

- **Macro method imports**: Import macro methods from other files/shards without importing the containing type
