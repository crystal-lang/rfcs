---
Feature Name: forward-compatibility-policy
Start Date: 2026-08-25
RFC PR: "https://github.com/crystal-lang/rfcs/pull/0000" # fill me in after creating the PR, also update the filename
Issue: "https://github.com/crystal-lang/crystal/issues/0000"
---

## Summary

Establish a policy to restrict forward compatibility with old compiler versions to a sliding window of 2 years.

## Motivation

In order to build the compiler, we need an existing compiler.

In practice, the bootstrap compiler is often from the previous generation: Crystal 1.21 is typically built with a 1.20 compiler.
But it's also possible to use older compilers.
Currently, Crystal 1.0 is able to build Crystal 1.21.

We've managed to live with this long support window for over five years now.
But it's starting to cause pain because older compiler versions lack [substantial language features](#significant-compiler-features).

While it's nice to be able to build new compilers from very old ones, it's not an essential mechanism.
We don't need to maintain forward compatibility forever.

For convenience, it's still useful to span a few recent releases.
But a time frame of about 2 years (equals 8 releases) should be sufficient for that.

## Guide-level explanation

The Crystal compiler maintains forward compatibility with previous compiler releases in the same major release series for at least 2 years or 8 minor releases (whichever is shorter).

That means, for example, a 1.14 compiler is guaranteed to be able to bootstrap a 1.22 compiler.
But it might not be able to build a 1.23 compiler.

The compiler uses an in-tree version of the standard library, so this policy also constrains which language features the standard library itself may use.

We still encourage package maintainers to bootstrap from the most recently available compiler to benefit from improvements in code generation and optimization.
But it is technically possible to pin the stage 0 compiler and only advance it every 2 years. In that case, we strongly recommend building a stage 2 compiler.

> [!NOTE] Backwards Compatibility
> This policy does not affect the [_Backwards Compatibility_ policy]:
> Any compiler of the 1.x release series can still compile a program written for 1.0.
> That includes being able to build a 1.0 compiler from any future compiler of the 1.x series.

[_Backwards Compatibility_ policy]: https://crystal-lang.org/reference/1.21/project/release-policy.html#backwards-compatibility

<!-- Explain the proposal as if it was already included in the language and you were teaching it to another Crystal programmer. That generally means:

- Introducing new named concepts.
- Explaining the feature largely in terms of examples.
- Explaining how Crystal programmers should _think_ about the feature, and how it should impact the way they use Crystal. It should explain the impact as concretely as possible.
- If applicable, provide sample error messages, deprecation warnings, or migration guidance.
- If applicable, describe the differences between teaching this to existing Crystal programmers and new Crystal programmers.
- If applicable, discuss how this impacts the ability to read, understand, and maintain Crystal code. Code is read and modified far more often than written; will the proposed feature make code easier to maintain?

For implementation-oriented RFCs (e.g. for compiler internals), this section should focus on how compiler contributors should think about the change, and give examples of its concrete impact. For policy RFCs, this section should provide an example-driven introduction to the policy, and explain its impact in concrete terms. -->

## Reference-level explanation

The policy gets documented on the [_Release Policy_ page] in the Crystal book.

We already ensure compatibility with the [existing CI workflow].
This should now use a sliding window instead of only adding new versions to the matrix.
Reducing the number of forward compatibility versions reduces the number of CI jobs there.

Untested older bootstrap compilers may still work, but are unsupported.

[_Release Policy_ page]: https://crystal-lang.org/reference/1.21/project/release-policy.html
[existing CI workflow]: https://github.com/crystal-lang/crystal/blob/50078d5f4de970d593bd0768e8c28cb0194c82ef/.github/workflows/forward-compatibility.yml

## Drawbacks

We can no longer bootstrap any 1.x compiler from a 1.0 compiler.
There seems to be little practical relevance for that. When bootstrapping the compiler lineage, adding a couple of intermediaries isn't a huge issue.
Downstream packages typically already use more recent versions for bootstrapping.

## Rationale and alternatives

Two years / 8 releases of forward compatibility seems like a useful time frame.
It doesn't require constant movement, but it's recent enough to incorporate new features after a reasonable time.

The time window should be large enough to accommodate evolution in slow-moving package repositories.

We can adjust the duration of the forward compatibility window if we realize a faster or slower pace would be better.

### Significant compiler features

- 128-bit integers — 1.2 to 1.8 (version is unclear from changelogs) with later fixes in 1.10+
- PCRE2 regex literals — 1.7
- annotations on method arguments — 1.5
- LLVM 18+ — 1.12
- Slice literals — 1.10, better support/fixes in 1.14 then 1.16
- `ReferenceStorage` — 1.12
- `CharLiteral#ord` — 1.11
- Number autocasting — 1.3

See also [Release Highlights]

[Release Highlights]: https://crystal-lang.org/releases/highlights/

### Glossary

- **stage 0**: an existing compiler used to build a new version of the compiler.
- **stage 1**: the newly built compiler from current code (including stdlib), by an earlier compiler
- **stage 2**: the truly current compiler built by a compiler of the same version

## Prior art

A previous attempt at restricting forward compatibility was made in [#12937],
but it stalled due to a lack of deeper discussion and support.
At that point the pain was not that strong yet.

[#12937]: https://github.com/crystal-lang/crystal/pull/12937

Other languages with self-hosted compilers face the same trade-off, and several have already gone through similar tightening of their bootstrap requirements:

- **Rust** ([rustc bootstrapping]) only supports building from the current beta release (effectively the immediately preceding release), building the compiler through several stages (`stage0` → `stage1` → `stage2`) each time. This keeps the compiler free to use almost any language feature directly after it stabilizes, at the cost of not being able to skip forward several versions in one bootstrap step.
- **Go** ([building Go from source]) went through a similar evolution as Crystal:
  - Up until Go 1.4, bootstrapping required a C toolchain
  - 1.5 through 1.19 can be built with a 1.4 compiler
  - Since Go 1.22, each release can be built with a compiler from two or three releases prior (whichever is an even number), which equals 12 to 18 months.

The proposed time frame in this RFC is considerably more generous than Rust's policy, and roughly comparable to Go's.

[building Go from source]: https://go.dev/doc/install/source
[rustc bootstrapping]: https://rustc-dev-guide.rust-lang.org/building/bootstrapping/what-bootstrapping-does.html

<!-- Discuss prior art, both the good and the bad, in relation to this proposal.
A few examples of what this can include are:

- For language, library, tools, and compiler proposals: Does this feature exist in other programming languages and what experience have their community had?
- For community proposals: Is this done by some other community and what were their experiences with it?
- Papers: Are there any published papers or great posts that discuss this? If you have some relevant papers to refer to, this can serve as a more detailed theoretical background.

This section is intended to encourage you as an author to think about the lessons from other languages, provide readers of your RFC with a fuller picture.
If there is no prior art, that is fine - your ideas are interesting to us whether they are brand new or if it is an adaptation from other languages.

Note that while precedent set by other languages is some motivation, it does not on its own motivate an RFC.
Please also take into consideration that Crystal sometimes intentionally diverges from common language features. -->

## Unresolved questions

- We could introduce an explicit version guard to prevent using older bootstrap compilers outside the compatibility guarantee.
<!--
- What parts of the design do you expect to resolve through the RFC process before this gets merged?
- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?
- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC? -->

## Future possibilities

- We could consider reducing the time window even further if we want a faster pace.
- The policy at a major-release boundary is not yet defined.
  Probably the 2.0 release should have the same compatibility as an equivalent release of 1.x, but following releases (2.1, 2.2, etc.) are not compatible with any 1.x compiler.

<!-- Think about what the natural extension and evolution of your proposal would
be and how it would affect the language and project as a whole in a holistic
way. Try to use this section as a tool to more fully consider all possible
interactions with the project and language in your proposal.
Also consider how this all fits into the roadmap for the project
and of the relevant sub-team.

This is also a good place to "dump ideas", if they are out of scope for the
RFC you are writing but otherwise related.

If you have tried and cannot think of any future possibilities,
you may simply state that you cannot think of anything.

Note that having something written down in the future-possibilities section
is not a reason to accept the current or a future RFC; such notes should be
in the section on motivation or rationale in this or subsequent RFCs.
The section merely provides additional information. -->
