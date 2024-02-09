- Feature Name: `math-combinatoric-library`
- Start Date: 2024-02-09
- RFC PR: [crystal-lang/rfcs#0005](https://github.com/crystal-lang/rfcs/pull/0005)
- Issue: -

# Summary

Add combinatoric and permutations methods to the standard library which works on integers.

# Motivation

Crystal has an already exsisting methods for doing combinations and permutations but those work on some form of collection which for larger sizes makes them very computanional heavy and high memory usage.
In the scientific world is there many uses of getting to know the size of combinations or permutations but not the individual combinations or permutations.
These methods could also have an `Int` implementation which doesnt use any form of collections to reduce on the calculations and memory usage required.
There are already exsisting libraries which impliments this logic but most of them are unmaintained.

The expected outcome out of this is that Crystal will have a stronger standard library for working with scientific purposes.
But also when working with just sizes of permutations and combinations will have drasticly faster executions.

# Guide-level explanation

When you just want the size of a combination or permutations so are the `BigInt#combination` or `BigInt#permutation` methods way more efficent when working on arrays.
They work using a mathematical formula based on factorial of numbers.

To use the methods will you have to include the `BigInt` libaries using `require "big"`.
Deffine a number then you can use the method on that number with how many combinations you want to use.

```crystal
require "big"

number : BigInt = 5
number.combinations(3)
# => 10

number.combinations(2)
# => 10
```

In the examples above can the number be reasoned about having 5 items and wanting to know how many ways those 5 items can be put in groups of 3 or 2. 
The reason why those 2 examples becomes the same can be reasoned out of 2 perspectives:

- Say you would want to add 5 new features to Crystal but you are only allowed to add 3.
- That would be the same as resoning that you would want to get groups of 2 features that doesnt get added.

Intrested in learning more: https://en.wikipedia.org/wiki/Combination

Another example:

```crystal
require "big"

number : BigInt = 20
number.combinations(2)
# => 190

number_2 : BigInt = 10
number_2.combinations(2)
# => 45
```

Error handeling examples:

```crystal
require "big"

number : BigInt = 5
number.combinations(-4)
# ArgummentError: combinations can't be done on negativ integers

number2 : BigInt = -5
number2.combinations(2)
# ArgummentError: combinations can't be done on negativ integers
```

As for permutations does that work simiralliy with the use `BigInt` libaries using `require "big"`.

```Crystal
require "big"

number : BigInt = 5
number.permutations(4)
# => 120
```

Combinations and permutations share a lot with each other.
The key difference between combinations and permutations is that permutations care about the order.
Take the last example with new features, say instead you have to make a list of the 3 features you would like to see in the language and the first feature is the one you want to see the most to be implemented.
Then the order matters you put them in the list.

Permutations doesnt have the same pattern as combinations with `5.combinations(3)` is the same as `5.combinations(2)`.
Instead for permutations so are `n.combinations(n)` always equal `n.combinations(n - 1)` (as long as n is a posstive number and not zero).

```crystal
require "big"

number : BigInt = 5
number.combinations(5)
# => 120

number.combinations(4)
# => 120
```

This is because say you have a list of the 4 features in order you most want to see in the languages.
Adding one more feature to the list would not add another combinations since there is only 1 feature left of choosing.

# Reference-level explanation

Since both of these methods quickly reach large numbers so do they both have to be implemented under `BigInt`.
They could either be written manualy using the mathematical formula togehter with `BigInt#factorial` or using a more optimzied version.
The mathematical formula for combinations: C(n,k) = (n!) / (k! * (n - k)!)
The mathematical formula for permutations: P(n,k) = n! / k!
The `!` is factorial.

Another alternative is to use: https://www.gnu.org/software/gsl/

# Drawbacks

Dependent on which apparoch is used so would the mathematical formula mostly add more maintaince burden.
The gsl library would add another library which has to be activly made sure to keep combatible to and in that way also add maintaince burden.

# Rationale and alternatives

The impact of not doing this would mostly mean that these features remains library exclusive, it could have certain benefits to that since the standard library would likely not be able to store all possible methods.
Although currently there is no real math library which has everything you have to combine a set of libraries if you would like to get a large amount of mathematical methods in various areas.
Alternativly is that users implements this logic by themselves which could mean unoptimized methods or repatativ method implementation.
In worst case a user could implement this using arrays (together with the built-in methods), which for large models would be very slow.

# Prior art

In quite a few languages does these methods comes in form of libraries, there could be many reasons to this including the fact that some languages wants to keep the standard library smal.

Although, python added a `math.comb` and `math.perm` method in 3.8.
This could be due to the fact being more math "focused" then others, but the methods have been appricated for users which have had to use those types of methods.

# Unresolved questions

Should Crystal lang add these combinatoric methods or should they remain to be gatherd through libraries?

# Future possibilities

I cant think of anything.
