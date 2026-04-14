---
Feature Name: "percent-array-literal-interpolation"
Start Date: 2026-02-25
RFC PR: "https://github.com/crystal-lang/rfcs/pull/21"
Issue:
---

## Summary

Add a variant of the existing percent array literal (`%w`) with interpolation support, indicated by an upper-case `%W`.

## Motivation

Creating string arrays with the `%w` literal syntax is convenient, but limited because string values must be static.
Introducing dynamic values requires mutating the array afterwards which adds more complexity.
A literal syntax with support for interpolation offers more convenience.

A particular use case is for process command arrays with `Process.run` and similar methods (see [#14773 (comment)]).

[#14773 (comment)]: https://github.com/crystal-lang/crystal/issues/14773#issuecomment-3890019306

## Guide-level explanation

The percent literal `%W` indicates a literal notation of a string array with individual values separated by whitespace.
It has the same properties as the lowercase `%w` literal except that it does support interpolation and escape sequences.

Upper and lower case indicating interpolation support is analogue to the percent string literals `%q` and `%Q`.

```cr
path = "foo.cr"
Process.run %W[crystal tool format #{path}]
# equivalent:
Process.run ["crystal", "tool", "format", path]
```

```cr
paths = %w[foo.cr bar.cr]
Process.run %W[crystal tool format #{*paths}]
# equivalent:
Process.run ["crystal", "tool", "format", *paths]
```

The basic properties are identical to `%w`:

```cr
%W[foo bar baz]  # => ["foo", "bar", "baz"]
%W[foo\nbar baz] # => ["foo\\nbar", "baz"]
%W[foo[bar] baz] # => ["foo[bar]", "baz"]

# escapes
%W[foo\ bar baz] # => ["foo bar", "baz"]
%W[foo 'bar baz'] # => ["foo", "'bar", "baz'"]
%W[foo "bar baz"] # => ["foo", "\"bar", "baz\""]
```

Interpolation syntax works similar to interpolation in string literals.
The interpolated values gets stringified and inserted into the current array element.
An array element can consist of an combination of interpolations and static components.

```cr
%W[foo #{"bar"} baz]            # => ["foo", "bar", "baz"]
%W[foo #{1 + 1} baz]            # => ["foo", "2", "baz"]
%W[foo #{"bar"}baz#{"bab"} qux] # => ["foo", "barbazbab", "qux"]
%W[foo _#{"bar"}_ baz]          # => ["foo", "_bar_", "baz"]
%W[foo #{"bar baz"} qux]        # => ["foo", "bar baz", "qux"]
```

Interpolation syntax also supports splat expansion which inserts multiple elements into the array at the respective position.
Splat interpolation does not support static prefix or suffix strings, i.e. it must be surrounded by whitespace or be anchored at the begin or end of the literal.

```cr
%W[foo #{*%w[bar baz]} qux] # => ["foo", "bar", "baz", "qux"]
```

## Reference-level explanation

`%W` literals parse into `ArrayLiteral` instances, just like `%w` literals.
Elements with interpolation are of type `StringInterpolation` or `Splat`, static strings are of type `StringLiteral`.

This example shows the respective equivalent (partial) parsing results:

```cr
%W[foo #{1 + 1} baz]
["foo", "#{1 + 1}", "baz"] of ::String

%W[foo #{"bar baz"} qux]
["foo", "#{"bar baz"}", "qux"] of ::String

%W[foo #{*%w[bar baz]} qux]
["foo", *%w[bar baz], "qux"] of ::String
```

When string interpolations only contain string literals, they can be merged together,
just like in string literal interpolation.

```cr
%W[#{"foo"}] # == %W[foo]
```

## Drawbacks

Adding slightly more complexity to the syntax. But we're only combining already existing features (array literals, string interpolation and splats) so there are no new concepts.

## Rationale and alternatives

- Crystal inherited the percent array literal syntax from Ruby which has exactly this `%W` variant with interpolation support. Adding it to Crystal seems like a logical consequence for enhancing the existing syntax features.

## Prior art

- Ruby supports `%W` in addition to `%w` array literals ([Ruby %W]).

[Ruby %W]: https://docs.ruby-lang.org/en/4.0/syntax/literals_rdoc.html#label-25w+and+-25W-3A+String-Array+Literals

## Unresolved questions

- Details and edge cases of the splat syntax

## Future possibilities

- Ruby also supports `%I` in addition to `%i` for symbol array literals ([Ruby %I]).
  We could consider porting that to Crystal as well. But it seems much less useful than string arrays, and outside the scope of this RFC.

[Ruby %I]: https://docs.ruby-lang.org/en/4.0/syntax/literals_rdoc.html#label-25i+and+-25I-3A+Symbol-Array+Literals
