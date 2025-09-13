---
Feature Name: time-monotonic
Start Date: 2025-08-28
RFC PR: "https://github.com/crystal-lang/rfcs/pull/15"
Issue: https://forum.crystal-lang.org/t/ambiguous-use-of-time-span-for-duration-and-monotonic-clock/8324
---

# Summary

Introduce a new type to represent instants on the monotonic timeline.
This replaces the current [`Time.monotonic`] which returns [`Time::Span`].

# Motivation

Currently, `Time.monotonic` returns a `Time::Span`, which represents a
*duration* rather than an *instant*. This overloading creates semantic
ambiguity: a `Time::Span` type is overloaded. It can either mean "an elapsed
duration" or "an absolute monotonic reading". This duplication can lead to
confusion and accidental misuse.

The expected outcome is a clearer and safer API where:
- `Time::Instant` represents a single point on the monotonic timeline.
- `Time::Span` continues to represent a duration.
- Subtracting two `Monotonic` instants yields a `Span`.
- Adding/subtracting a `Span` to/from an `Monotonic` yields a new `Monotonic`.

The confusion is aided by the fact that [`Time.measure(&)`] also returns
`Time::Span` but there it actually represents a duration.

# Guide-level explanation

With this proposal, Crystal programmers will use a dedicated type for monotonic time readings:

Crystal 1.17: Ambiguous

```crystal
start = Time.monotonic # : Time::Span
# do something
elapsed = Time.monotonic - start # : Time::Span
```

This RFC: Clearer

```crystal
start = Time::Instant.now # : Time::Instant
# do something
elapsed = Time::Instant.now - start # : Time::Span
```

The key distinction is that `Monotonic` is a point in time on the monotonic
clock, while `Span` is a duration. This separation makes code easier to reason
about and reduces the risk of type misuse.

## Transition

`Time.monotonic` gets deprecated, but continues to function. We recommend
transitioning to `Time::Instant.now`.

A simple mechanical replacement `s/Time.monotonic/Time::Instant.now/` could be
implemented in tooling (e.g. [ameba](https://github.com/crystal-ameba/ameba)).
This should generally work fine because the usable API is identical. If the type
`Time::Span` is encoded in a type restriction (e.g. ivar or method signature),
it needs updating as well. This is not trivial to automate.

# Reference-level explanation

We introduce a new type that represents a reading of a monotonic nondecreasing
clock for the purpose of measuring elapsed time or timing an event in the future.

Instants are opaque value that can only be compared to one another.
The only useful values are differences between readings, represented as `Time::Span`.

Clock readings are guaranteed, barring [platform bugs], to be no less than any
previous reading.

The measurement itself is expected to be fast (low latency) and precise within
nanosecond resolution. This means it might not provide the best available
accuracy for long-term measurements.

The clock is not guaranteed to be steady. Ticks of the underlying clock might
vary in length. The clock may jump forwards or experience time dilation. But
does not go backwards.

The clock is expected to tick while the system is suspended. But this cannot be
guaranteed on all platforms.

The clock is only guaranteed to apply to the current process. In practice it is
usually relative to system boot, so should be interchangeable between processes.
But this is not guaranteed on all platforms.

Monotonicity is expected, but cannot be strictly guaranteed due to OS or
hardware bugs.

The new type implements a subset of the API of `Time::Span` (and `Time`)
retaining the same logic.
Existing uses should continue to work as before, despite the type change.

```cr
struct Time::Instant
  include Comparable(self)

  # Returns the current reading of the monotonic clock.
  def self.now : self
  end

  def initialize(seconds : )

  def -(other : self) : Time::Span
  end

  def +(other : Time::Span) : self
  end

  def -(other : Time::Span) : self
  end

  def <=>(other : self) : Int32
  end

  # Returns the duration between `other` and `self`.
  #
  # The resulting duration is positive or zero.
  def duration_since(other : self) : Time::Span
    (other - self).clamp(Time::Span.zero..)
  end

  # Returns the amount of time elapsed since `self`.
  #
  # The resulting duration is positive or zero.
  def elapsed : Time::Span
    Instant.now.duration_since(self)
  end
end
```

Internally, the type stores the raw monotonic clock reading in nanoseconds as an
`Int64`, consistent with `Time::Span`.  The implementation builds on the
existing platform API abstraction in `Crystal::System::Time.monotonic`. We might
want to introduce some adjustments for better aligned semantics.

[`Time.measure(&)`] stays unaffected except updating the implementation to the
new API.

## Glossary

- **monotonic:** Strictly non-decreasing: any clock reading is greater or equal to any previous reading. *Effectively this means the clock is not affected by manual changes to the system clock or mechanisms like NTP sync. A monotonic clock may or may not advance while the system is suspended.*
- **strictly increasing:** Any clock reading is greater than any previous reading. *The clocks exposed by the operating system usually cannot guarantee this: there is a chance that consecutive calls may return the same reading.*
- **steady:** Clock ticks at a constant rate, i.e. the length of a unit of time is fixed and there are no discontinuous jumps. *Monotonic clocks are usually steady (at least as far as hardware imperfection allows). Strict steadiness is not guaranteed. The Linux kernel for example may adjust the `CLOCK_MONOTONIC` tick rate to ensure clock discipline. This is usually a gradual slewing, but might be more noticeable jumps for large corrections.*
- **calendar time:** A clock tracking date + time of day. It is usually synced to civil time via NTP or manual setting and can jump arbitrarily for clock adjustments. *That makes it unsuitable for reliably measuring elapsed time.*

# Drawbacks

- This introduces a new type, increasing API surface area.

# Rationale and alternatives

Keeping `Time.monotonic` returning a `Span` risks continued ambiguity.

Not doing this change means continuously conflating two distinct concepts, potentially leading to subtle bugs.

This could be implemented as a shard outside the standard library. But it needs
to be in stdlib to successfully replace `Time.monotonic`.

# Prior art

Other standard libraries distinguish between *monotonic instants* and
*durations*:

* **Rust**: [`std::time::Instant`] vs. [`std::time::Duration`]
* **Swift**: [`DispatchTime`] vs. [`DispatchTimeInterval`]
* **Zig**: [`std.time.Instant`]

# Unresolved questions

- The `#-` method for calculating a duration between two instants is simple, but
  can lead to mistakes based on the order of operands. It's also susceptiple to
  errors in monotonicity which can lead to negative durations.
  An explicit distance calculation that ensures monotonicity would be more safe.
  An example for that is Rust's [`duration_since`]: It clearly specifies the
  expected temporal relation and saturates the return value at zero.
  Such a method could be generally useful, but questions the existence of `#-`.
  `#elapsed` would be convenient alternative that also alleviates these issues,
  but doesn't cover all use cases.

# Future possibilities

- `#elapsed` would allow extensions for different clocks. Calling `#elapsed`
  would always use the same clock as `self`.
- A stopwatch / timer implementation, similar to Zig's [`std.time.Timer`] (see
  [#3827])
- Extract commonalities between `Time` and `Time::Instant` into a module type
  (`Time::CockReading`?).
- Unified clock APIs: e.g., `sleep(until: Time::Instant)` and `sleep(until:
  Time)` (see _[Generalize `#sleep` for monotonic and wall clock]_)
- Constructor from a raw value, and a converter to a raw value. The use case
  would be to import/export clock readings. This is primarily useful for
  interacting with components outside stdlib (C libraries). Serialization
  probably isn't much relevant though, because the values are really only valid
  inside the current process.
- We could consider to delegate `Time.monotonic` to `Time::Instant.now`
  eventually. This is a breaking change and can only happen after a deprecation
  period.

[`Time.measure(&)`]:
    https://crystal-lang.org/api/1.17.1/Time.html#measure%28%26%29%3ATime%3A%3ASpan-class-method
[`Time.monotonic`]:
    https://crystal-lang.org/api/1.17.1/Time.html#monotonic%3ATime%3A%3ASpan-class-method
[`Time::Span`]: https://crystal-lang.org/api/1.17.1/Time/Span.html
[`std::time::Instant`]: https://doc.rust-lang.org/std/time/struct.Instant.html
[`std::time::Duration`]: https://doc.rust-lang.org/std/time/struct.Duration.html
[`DispatchTime`]:
    https://developer.apple.com/documentation/dispatch/dispatchtime
[`DispatchTimeInterval`]: https://developer.apple.com/documentation/dispatch/dispatchtimeinterval

[`duration_since`]:
    https://doc.rust-lang.org/std/time/struct.Instant.html#method.duration_since
[`std.time.Instant`]: https://ziglang.org/documentation/master/std/#std.time.Instant
[`std.time.Timer`]: https://ziglang.org/documentation/master/std/#std.time.Timer
[#3827]: https://github.com/crystal-lang/crystal/pull/3827
[Generalize `#sleep` for monotonic and wall clock]: https://forum.crystal-lang.org/t/generalize-sleep-for-monotonic-and-wall-clock/8383
