---
Feature Name: math-combinatoric-library
Start Date: 2024-02-09
RFC PR: "https://github.com/crystal-lang/rfcs/pull/0005"
Issue:
---

# Summary

Add combinatorics and permutation methods to the standard library which works on integers.

# Motivation

Crystal has already existing methods for doing combinations and permutations but those work on some form of collection which for larger sizes makes them very computational heavy and high memory usage.
In the scientific world is there many uses for getting to know the size of combinations or permutations but not the individual combinations or permutations.
These methods could also have an `Int` implementation which doesn't use any form of collections to reduce the calculations and memory usage required.
There are already existing libraries that implement this logic but most of them are unmaintained.

The expected outcome of this is that Crystal will have a stronger standard library for working with scientific purposes.
But also when working with just sizes of permutations and combinations will have drastically faster executions.

# Guide-level explanation

When you just want the size of a combination or permutations, the `BigInt#combination` or `BigInt#permutation` methods are way more efficient when working on arrays.
They work using a mathematical formula based on the factorial of numbers.

To use the methods will you have to include the `BigInt` libraries using `require "big"`.
Define a number then you can use the method on that number with how many combinations you want to use.

```crystal
require "big"

number = BigInt.new(5)
number.combinations(3)
# => 10

number.combinations(2)
# => 10
```

In the examples above can the number be reasoned about having 5 items and wanting to know how many ways those 5 items can be put in groups of 3 or 2.
The reason why those 2 examples become the same can be reasoned out from 2 perspectives:

- Say you would want to add 5 new features to Crystal but you are only allowed to add 3.
- That would be the same as reasoning that you would want to get groups of 2 features that don't get added.

Interested in learning more: https://en.wikipedia.org/wiki/Combination

Another example:

```crystal
require "big"

number = BigInt.new(20)
number.combinations(2)
# => 190

number_2 = BigInt.new(10)
number_2.combinations(2)
# => 45
```

Error handling examples:

```crystal
require "big"

number = BigInt.new(5)
number.combinations(-4)
# ArgumentError: combinations can't be done on negative integers

number_2 BigInt.new(-5)
number_2.combinations(2)
# ArgumentError: combinations can't be done on negative integers
```

As for permutations does that work similarly with the use `BigInt` libraries using `require "big"`.

```Crystal
require "big"

number = BigInt.new(5)
number.permutations(4)
# => 120
```

Combinations and permutations share a lot.
The key difference between combinations and permutations is that permutations care about the order.
Take the last example with new features, say instead you have to list the 3 features you would like to see in the language and the first feature is the one you want to see the most to be implemented.
Then the order matters you put them in the list.

Permutations don't have the same pattern as combinations with `5.permutations(3)` is the same as `5.permutations(2)`.
Instead for permutations so are `n.permutations(n)` always equal `n.permutations(n - 1)` (as long as n is a positive number and not zero).


```crystal
require "big"

number = BigInt.new(5)
number.permutations(5)
# => 120

number.permutations(4)
# => 120
```

This is because say you have a list of the 4 features in order you most want to see in the language.
Adding one more feature to the list would not add another permutation since there is only 1 feature left to choose.

# Reference-level explanation

Since both of these methods quickly reach large numbers, they both have to be implemented under `BigInt`.
They could either be written manually using the mathematical formula together with `BigInt#factorial` or using a more optimized version.
The mathematical formula for combinations: C(n,k) = (n!) / (k! * (n - k)!)
The mathematical formula for permutations: P(n,k) = n! / k!
The `!` is factorial.

Another alternative is to use: https://www.gnu.org/software/gsl/

# Drawbacks

Depending on which approach is used so would the mathematical formula mostly adds more maintenance burden.
The gsl library would add another library which has to be actively made sure to remain compatible and in that way also add maintenance burden.


# Rationale and alternatives

The impact of not doing this would mostly mean that these features remain library exclusive, it could have certain benefits to that since the standard library would likely not be able to store all possible methods.
Currently, there is no real math library that has everything you have to combine a set of libraries if you would like to get a large amount of mathematical methods in various areas.
Alternatively, users implement this logic by themselves which could mean unoptimized methods or repetitive method implementation.
In the worst case, a user could implement this using arrays (together with the built-in methods), which for large models would be very slow.

# Prior art

In quite a few languages these methods come in the form of libraries, there could be many reasons for this including the fact that some languages want to keep the standard library small.

Although, python added a `math.comb` and `math.perm` method in 3.8.
This could be because it is more math "focused" than others, but the methods have been appreciated by users who have had to use those types of methods.

There are also a couple of libraries in Crystal which implements these methods like: https://github.com/ruivieira/crystal-gsl, https://github.com/ouracademy/statistical-analysis 

# Unresolved questions

Should Crystal-lang add these combinatoric methods or should they remain to be gathered through libraries?

# Future possibilities

I can't think of anything.
