---
Feature Name: target_annotation
Start Date: 2026-02-17
RFC PR: "https://github.com/crystal-lang/rfcs/pull/0020"
Issue: "https://github.com/crystal-lang/crystal/issues/16570"
Implementation PR: "https://github.com/crystal-lang/crystal/pull/16571"
---

## Summary

Introduces a new `@[Target]` annotation that allows setting codegen options for individual methods.
This enables programs to include code paths that use advanced CPU instructions (such as SIMD extensions) and select compatible implementations at runtime.


## Motivation

For performance-critical routines, it is important to be able to use advanced CPU features.
Yet it's not always feasible to build dedicated executables for each specific feature combination.
Instead, programs should be able to include multiple code paths and select the appropriate one at runtime based on CPU feature detection.

The current compiler refuses to generate instructions that are not supported by the exact target architecture configuration.
That means every compilation can target exactly one configuration which can either be generic and miss out on advanced features or depend on advanced features and reduce portability.
This prohibits legitimate use cases for having optional code paths, depending on feature support at runtime.

You thus need to tell LLVM to enable CPU features scoped to specific functions only, which sounds reasonable. Annotations also sound good.


## Guide-level explanation

With this feature, CPU features can be scoped to specific function only.

For example, a generic baseline implementation as fallback, plus one or more optimized implementations using specialized instructions.
A runtime check selects the appropriate implementation.

```cr
@[Target(features: "+sve,+sve2")]
def foo_sve2
end

def foo_portable
end

if cpu_supports_sve?
  foo_sve2
else
  foo_portable
end
```


## Reference-level explanation

The `@[Target]` annotation can be applied to a `def` of `fun` definition to enable
specific code generation features.

It supports these parameters:

- `feature`: Select specific platform architecture features. See https://llvm.org/doxygen/classllvm_1_1SubtargetFeatures.html
  ```cr
  @[Target(features: "+avx2")]
  def foo_avx2
  end
  ```
- `cpu`: Select a specific CPU type.
  ```cr
  @[Target(cpu: "apple-m1")]
  def foo_m1
  end
  ```
- `debug`: Disable debug metadata.
  ```cr
  @[Target(debug: false)]
  def foo_debug
  end
  ```
- `optimize`: Select optimization strategy.
  ```cr
  @[Target(optimize: :size)]
  def foo_size
  end
  ```

Feature and CPU selections only accept values valid for the current target platform architecture.
That means their definition may typically need guard clauses.

```cr
{% if flag?(:aarch64) %}
  @[Target(features: "+avx2")]
  def foo_avx2
  end
{% end %}
```

When a method has been compiled with a feature and that feature is not supported on the platform at runtime, calling this method is undefined behaviour.

Method with `@[Target]` feature annotation may not be inlined into an incompatible context.


## Drawbacks

- Increased complexity in code generation and target feature management.
- Risk that binaries may crash at runtime when this feature is handled unsafely.


## Rationale and alternatives

An alternative would be to build individual libraries with specific codegen options,
and link them together into an executable.

This is technically already possible, but complex and unergonomic.


## Prior art

Several modern systems languages provide mechanisms to compile code using CPU features that may not be available on the build machine, typically combined with runtime feature detection and dispatch.

- Rust supports fine-grained CPU feature control via the [`#[target_feature(enable = "avx2")]`][target_feature] attribute for function-level specialization.
- Clang / GCC have similar function annotations `__attribute__((target("avx2")))`/`[[ gnu::target("avx2") ]]`.
- Go doesn't validate instructions in its own assembly language.
- Zig requires separate code + object files each compiled separately with the correct flags and then the object files are linked. There is an ongoing discussion in [zig #1018] with a similar motivation as this RFC.


## Unresolved questions

- Should there be warnings and should they be be suppressible or configurable?
- Do we really need to guard the `@[Target]` def with arch flags or only the callsites?
- How can we provide helpers for  runtime feature detection?
- How does calling nested functions work?
- Clang/gcc style automatic static/dynamic dispatch could be useful for Crystal? (https://github.com/crystal-lang/crystal/issues/16570#issuecomment-3760342769)
- `debug` and `optimize` seem a bit distance from CPU features, so maybe they should be excluded from this proposal (defer to future discussion)


## Future possibilities

[target_feature]: https://doc.rust-lang.org/reference/attributes/codegen.html#r-attributes.codegen.target_feature
[zig #1018]: https://github.com/ziglang/zig/issues/1018
