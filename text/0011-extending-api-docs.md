- Feature Name: extending-api-docs
- Start Date: 2024-11-14
- RFC PR: [crystal-lang/rfcs#11](https://github.com/crystal-lang/rfcs/pull/11)
- Issue: [crystal-lang/crystal#6721](https://github.com/crystal-lang/crystal/issues/6721)

# Summary

We propose the addition of a `:showdoc:` directive that will allow to document normally undocumented types and methods.

# Motivation

Currently, API documentation is not generated for private/protected methods/objects or C lib binding objects.
This was originally done as these (typically) should not be used, however, this is not always the case.
When inheriting from a class that has a protected method that is intended to be implemented, it is useful
to know that method exists, and what parameters / types it has, without needing to refer to the source code.

Another use case is for libraries such as [raylib.cr](https://github.com/sol-vin/raylib-cr), where developing a
"Crystal" interface to them using classes and structs would be prohibitive, and currently requires diving
into the source code in order to figure out what methods are available.

# Guide-level explanation

The `:showdoc:` directive can be added to private or protected objects, as well as C lib binding objects, to have them show up in API documentation.
By default, these are hidden and should only be shown if they're explicitly intended to be used.

In this example, when generating API documentation, `Foo.foo` will be included even though it is a private method.

```crystal
module Foo
  # :showdoc:
  #
  # Here is some documentation for `Foo.foo`
  private def self.foo
  end
end
```

This also works for C lib, struct, enum, etc; everything in the `FooLib` namespace will be included in doc generation.

```crystal
# :showdoc:
#
# Writing documentation for code is really important and useful,
# not just for others but also your future self.
lib FooLib
  fun my_function(value : Int32) : Int32

  enum FooEnum
    Member1
    Member1
    Member3
  end

  struct FooStruct
    var_1 : Int32
    var_2 : Int32
  end
end
```

If a namespace has the `:nodoc:` directive, then the `:showdoc:` directive will have no effect on anything in its namespace.

```crystal
# :nodoc:
struct MyStruct
  # :showdoc:
  #
  # This will not show up in API docs
  struct MyStructChild
  end
end
```

# Reference-level explanation

- The parser will need to be updated to support doc comments for C lib binding objects and the `:showdoc:` directive
- The documentation generator will need to be updated to support C lib binding objects and private/protected objects
- If an object has a `:showdoc:` directive and its parent namespace is shown, then it should be shown too

TBD

# Drawbacks

TBD

# Rationale and alternatives

The other design that has been considered is having flags on the documentation generator itself that enable showing of private / protected objects and C lib objects in the API documentation. We chose not to go with this design as it required flags to be added at generation time, and only generated all or none (no granularity in what is shown).

This cannot be done in a library instead as it requires updates to the parser itself. This proposal makes Crystal code easier to understand, as it increases the amount and quality of API documentation.

# Prior art

There is a [PR](https://github.com/crystal-lang/crystal/pull/14816) implementing a similar feature, however it uses the generation-time flag method mentioned above, instead of the `:showdoc:` directive.

## Ruby / YARD

Ruby (via YARD) has global flags for showing protected and private methods when generating documentation. By default they are hidden.
Each project can have a `.docopts` file that specifies the options to use when building the docs, making it so specifying the flags every time is unnecessary.
Example of protected method: https://rubydoc.info/gems/yard/0.9.37/YARD/Handlers/Ruby/MixinHandler#process_mixin-instance_method

Rubys FFI generates normal classes so there's no distinction for them when generating API documentation. Example: https://rubydoc.info/gems/raylib-bindings/Raylib/Vector2

## Rust

Rust documents all public types by default. There is a flag for adding private types to the API docs, see the discussion [here](https://github.com/rust-lang/cargo/issues/1520).

## Elixir

Elixir documents FFI bindings, see https://hexdocs.pm/rayex/Rayex.Core.html#begin_drawing/0.

It does not have a method for documenting private methods, see https://hexdocs.pm/elixir/1.12/writing-documentation.html#documentation-code-comments.
> Because private functions cannot be accessed externally, Elixir will warn if a private function has a @doc attribute and will discard its content.

# Unresolved questions

TBD

# Future possibilities

TBD
