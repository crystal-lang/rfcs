- Feature Name: `heap_escape_analysis`
- Start Date: 2024-02-06
- RFC PR: [crystal-lang/rfcs#4](https://github.com/crystal-lang/rfcs/pull/4)
- Issue: -

# Summary

Add an optimization pass to the compiler to detect places where a class instantiation could happen on the stack rather than the GC HEAP.

# Motivation

Crystal always allocates class instances into the garbage collected HEAP, even in situations when a variable is only ever accessed locally. This can increase pressure on the GC that needs to allocate then do a collection to reclaim the memory.

Allocating in the HEAP is much slower than allocating on the stack. The GC is also a potential contention point in a multithreaded environment. Having less allocations when possible would improve performance.

# Guide-level explanation

The escape analysis optimization to the semantic pass: if a variable doesn’t outlive the method it is defined in, and its instance size isn’t too large to be allocated on the stack, the compiler can decide allocate it on the HEAP.

A variable can’t outlive a method when the reference:

- isn’t returned by the method;
- isn’t passed to a method that would capture it (i.e. the argument outlive the method).

The pass automatically decides where to allocate local variables.

To detect more situations more easily, the pass should run after any code inlining passes (e.g. blocks). 

## Lifetime

The following list details the cases when a local variable (including method arguments) is considered captured.

- It is a Reference or an Union with a Reference;
- It is passed to a method that captures that argument (transitive property);
- It is assigned to a local variable that will be captured;
- It is assigned to a global variable;
- It is assigned to a class variable;
- It is assigned to an instance variable;
- It is returned, unless it was an argument of this method;
- A pointer to the variable is taken (`pointerof`) —unless the pointer itself isn't captured?;
- It is passed to an FFI method (e.g. LibC).

# Reference-level explanation

The implementation details are left to actual implementors.

# Drawbacks

Some objects would now be allocated on the stack, which are GC roots that must be scanned conservatively and can't scan precisely. This may have negatively impact GC performance when we implement semi-conservative marking (conservative marking of GC roots _yet_ precise marking of HEAP allocated objects).

# Rationale and alternatives

Developers shouldn't have to worry about where a class is instanciated. The optimization would optimize anything from stdlib, shards or user code, all the while developers would use the objects normally.

Alternatively, developers can already change a `class` into a `struct` but the semantics will change (pass by copy, must pass pointers) is unsafe (no protection against dangling pointers) and limited to the types the developer has actual control upon, as we can't change a type from stdlib or a shard.

There is also pending work to add mechanisms to manually allocate class instances on the stack (see crystal-lang/crystal#13481). The advantage is that it gives control to developers, the drawback is that it puts the burden to the developer to use the mechanism, and it can be unsafe because a method may capture a reference (dangling pointer) which Crystal won't protect against.

> [!NOTE]
The HEAP escape analysis is a best effort and may not detect subtle situations as safe; it may not replace manual stack allocations as decided by the developer.

# Prior art

Java has escape analysis since JAVA SE 6. It seems to be decided at runtime and allows partial HEAP escape (the variable is reallocated to the HEAP on escape).

Go developers don’t decide where variables are allocated: whenever possible Go will allocate variables to the stack, but will allocate them to the GC HEAP if the variable may outlive the function or when the variable is too big to be allocated on the stack.

Wikipedia has an [Escape analysis article](https://en.wikipedia.org/wiki/Escape_analysis), mentioning Java and Scheme.

# Unresolved questions


If the escape analysis is too costly, maybe the optimization may only be enabled when an optimization level is selected? That would avoid negatively impacting development builds.

# Future possibilities

The same capture analysis could be used to help protect against dangling pointers in general.

It may also push for the compiler to inline methods annotated with `@[AlwaysInline]` by itself, instead of passing the hint to LLVM that will, or will not, inline the annotated methods.
