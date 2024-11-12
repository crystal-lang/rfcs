- Feature Name: `lifetime-event_loop`
- Start Date: 2024-11-11
- RFC PR:
  [crystal-lang/rfcs#0009](https://github.com/crystal-lang/rfcs/pull/9)
- Issue:
  [crystal-lang/crystal#14996](https://github.com/crystal-lang/crystal/pull/14996)

# Summary

Integrate the Crystal event loop directly with system selectors,
[`epoll`](https://linux.die.net/man/7/epoll) (Linux) and
[`kqueue`](https://man.freebsd.org/cgi/man.cgi?kqueue) (*BSD, macOS) instead of
going through [`libevent`](https://libevent.org/).

# Motivation

Direct integration with the system selectors enables a more performant
implementation thanks to a design change. Going from ad-hoc event subscriptions
to lifetime subscriptions per file descriptor (`fd`) reduces overhead per
operation.

Dropping `libevent` also removes an external runtime dependency from Crystal
programs.

This also prepares the event loop foundation for implementing execution contexts
from [RFC #0002](https://github.com/crystal-lang/rfcs/pull/2).

# Guide-level explanation

<!--
Explain the proposal as if it was already included in the language and you were
teaching it to another Crystal programmer. That generally means:

- Introducing new named concepts.
- Explaining the feature largely in terms of examples.
- Explaining how Crystal programmers should *think* about the feature, and how
  it should impact the way they use Crystal. It should explain the impact as
  concretely as possible.
- If applicable, provide sample error messages, deprecation warnings, or
  migration guidance.
- If applicable, describe the differences between teaching this to existing
  Crystal programmers and new Crystal programmers.
- If applicable, discuss how this impacts the ability to read, understand, and
  maintain Crystal code. Code is read and modified far more often than written;
  will the proposed feature make code easier to maintain?

For implementation-oriented RFCs (e.g. for compiler internals), this section
should focus on how compiler contributors should think about the change, and
give examples of its concrete impact. For policy RFCs, this section should
provide an example-driven introduction to the policy, and explain its impact in
concrete terms.
-->

This new event loop driver builds on top of the event loop refactor from [RFC
#0007](./0007-event_loop-refactor.md). It plugs right into the runtime and does
not require any changes in user code, even for direct consumers of the
`Crystal::EventLoop` API.

The new event loop driver is enabled automatically on supported targets (see
[*Availability*](#availability)). The `libevent` driver serves as a fallback for
unsupported targets and can be opted-in with the compile-time flag
`-Deventloop=libevent`.

### Design

The logic of the event loop doesn't change much from the one based on
`libevent`:

* We try to execute an operation (e.g. `read`, `write`, `connect`, ...) on
  nonblocking `fd`s
* If the operation would block (`EAGAIN`) we create an event that references the
  operation along with the current fiber
* We eventually rely on the polling system (`epoll` or `kqueue`) to report when
  an `fd` is ready, which will dequeue a pending event and resume its associated
  fiber (one at a time).

Unlike `libevent` which adds and removes the `fd` to and from the polling system
on every blocking operation, the lifetime event loop driver adds every `fd`
_once_ and only removes it when closing the `fd`.

The argument is that being notified for readiness (which happens only once
thanks to edge-triggering) is less expensive than always modifying the polling
system.

The mechanism only requires fine grained locks (read, write) which are usually
uncontended, unless you share a `fd` for the same read or write operation in
multiple fibers.

> [!NOTE]
>
> On a purely IO-bound benchmark with long running sockets, we noticed up to 20%
> performance improvement. Real applications would see less improvements,
> though.

### Multi-Threading

It supports the multi-threading preview (`-Dpreview_mt`) with one event loop
instance per thread (scheduler requirement).

Execution contexts ([RFC #0002](https://github.com/crystal-lang/rfcs/pull/2))
will have one event loop instance per context.

With multiple event loop instances, it's necessary to define what happens when
the same `fd` is used from multiple instances.

When an operation starts on a `fd` that is owned by a different event loop
instance, we transfer it. The new event loop becomes the sole "owner" of the
`fd`. This transfer happens implicitly.

This leads to a caveat: we can't have multiple fibers waiting for the same `fd`
in different event loop instances (aka threads/contexts). Trying to transfer the
`fd` raises if there is a waiting fiber in the old event loop. This is because
an IO read/write can have a timeout which is registered in the current event
loop timers, and timers aren't transferred. This also allows for future
enhancements (e.g. enqueues are _always_ local).

This can be an issue for `preview_mt`, for example when multiple fibers are
waiting for connections on a server socket. This shall be mitigated with
execution contexts where an event loop instance is shared per context — just
don't share a `fd` between contexts.

### Availability

The lifetime event loop driver is supported on:

- FreeBSD
- Linux
- macOS

On these operating systems, it's enabled automatically by default. Unsupported
systems keep using `libevent`.

Compile time flags allow choosing a different event loop driver.

- `-Devloop=libevent`: Use `libevent`
- `-Devloop=epoll`: Use `epoll` (e.g. Solaris);
- `-Devloop=kqueue`: Use `kqueue` (on *BSD);

The event loop drivers on Windows and WebAssembly (WASI) are not affected by
this change.

## Terminology

- **Event loop**: an abstraction to wait on specific events, such as timers
  (e.g. wait until a certain amount of time has passed) or IO (e.g. wait for an
  socket to be readable or writable).

- **Crystal event loop:** Component of the Crystal runtime that subscribes to
  and dispatches events from the OS and other sources to enqueue a waiting fiber
  when a desired event (such as IO availability) has occured. It’s an interface
  between Crystal’s scheduler and the event loop driver.

- **Event loop driver:** Connects the event loop backend (`libevent`, `IOCP`,
  `epoll`, `kqueue`, `io_uring`) with the Crystal runtime.

- **System selector:** The system implementation of an event loop which the
  runtime component depends on to receive events from the operating system.
  Example implementations: `epoll`, `kqueue`, `IOCP`, `io_uring`. `libevent` is
  a cross-platform wrapper for system selectors.

- **Scheduler:** manages fibers’ executions inside the program (controlled by
  Crystal), unlike threads that are scheduled by the operating system (outside
  of the accessibility of the program).

# Reference-level explanation

<!--
This is the technical portion of the RFC. Explain the design in sufficient
detail that:

- Its interaction with other features is clear.
- It is reasonably clear how the feature would be implemented.
- Corner cases are dissected by example.

The section should return to the examples given in the previous section, and
explain more fully how the detailed proposal makes those examples work.
-->

The run loop first waits on `epoll`/`kqueue`, canceling IO timeouts as it
resumes fibers, then proceeds to process timers.

The epoll/kqueue call doesn't wait until the next ready timer (it could without
MT and with `preview_mt` but can't for execution contexts). It instead relies on
`timerfd` on Linux and `EVTFILT_TIMER` on BSD to interrupt a blocking event loop
wait. It also allows to circumvent the 1ms precision of `epoll_wait` on Linux.

## Components

Each syscall is abstracted in its own little struct: `Crystal::System::Epoll`,
`Crystal::System::TimerFD`, etc.

- `Crystal::Evented` namespace (`src/crystal/system/unix/evented`) contains the
  base implementation that the system specific drivers
  `Crystal::Epoll::EventLoop` (`src/crystal/system/unix/epoll`) and
  `Crystal::Kqueue::EventLoop` (`src/crystal/system/unix/kqueue`) are built on.
- `Crystal::Evented::Timers` is a basic data structure to keep a list of timers
  (one instance per event loop).
- `Crystal::Evented::Event` holds the event, be it IO or sleep or select timeout
  or IO with timeout, while `FiberEvent` wraps an `Event` for sleeps and select
  timeouts.
- `Crystal::Evented::PollDescriptor` is allocated in a Generational Arena and
  keeps the list of readers and writers (events/fibers waiting on IO). It takes
  advantage that the OS kernel guarantees a unique `fd` number and always reuses
  numbers of closed `fd`, only adding more numbers when needed.

## Poll Descriptors

To avoid keeping pointers to the IO object that could prevent the GC from
collecting lost IO objects, this proposal introduces *Poll Descriptor* objects
(the name comes from Go's netpoll) that keep the list of readers and writers and
don't point back to the IO object. The GC collecting an IO object is fine: the
finalizer will close the `fd` and tell the event loop to cleanup the associated *Poll Descriptor* (so we can safely reuse the `fd`).

To avoid pushing raw pointers into the kernel data structures, and to quickly
retrieve the *Poll Descriptor* from a mere `fd`, but also to avoid programming
errors that would segfault the program, this propsal introduces a *Generational
Arena* to store the *Poll Descriptors* (the name is inherited from Go's netpoll)
so we only store an index into the polling system. Another benefit is that we
can reuse the existing allocation when a `fd` is reused. If we try to retrieve
an outdated index (the allocation was freed or reallocated) the arena will raise
an explicit exception.

> [!NOTE]
>
> The goals of the arena are:
> - avoid repeated allocations;
> - avoid polluting the IO object with the PollDescriptor (doesn't exist in
> other event loops);
> - avoid saving raw pointers into kernel data structures;
> - safely detect allocation issues instead of segfaults because of raw
>   pointers.

The *Poll Descriptors* associate a `fd` to an event loop instance, so we can
still have multiple event loops per processes, yet make sure that an `fd` is
only ever in one event loop. When a `fd` will block on another event loop
instance, the `fd` will be transferred automatically (i.e. removed from the old
one & added to the new one). The benefits are numerous: this avoids having
multiple event loops being notified at the same time; this avoids having to
close/remove the `fd` from each event loop instances; this avoids cross event
loop enqueues that are much slower than local enqueues in execution contexts.

A limitation is that trying to move a `fd` from one event loop to another while
there are pending waiters will raise an exception. We could move timeout events
along with the `fd` from one event loop instance to another one, but that would
also break the "always local enqueues" benefit.

Most application shouldn't notice any impact because of this design choice,
since a `fd` is usually not shared across fibers for concurrency issues. An
exception may be a server socket with multiple accepting fibers. In that case
you'll need to make sure the fibers are on the same thread (`preview_mt`) or
execution context.

# Drawbacks

<!--
Why should we *not* do this?
-->

* There's more code to maintain: Instead of only the `libevent` driver we now
  have additional ones to care about.

# Rationale and alternatives

<!--
- Why is this design the best in the space of possible designs?
- What other designs have been considered and what is the rationale for not
  choosing them?
- What is the impact of not doing this?
- If this is a language proposal, could this be done in a library instead? Does
  the proposed change make Crystal code easier or harder to read, understand,
  and maintain?
-->

# Prior art

<!--
Discuss prior art, both the good and the bad, in relation to this proposal. A
few examples of what this can include are:

- For language, library, tools, and compiler proposals: Does this feature exist
  in other programming languages and what experience have their community had?
- For community proposals: Is this done by some other community and what were
  their experiences with it?
- Papers: Are there any published papers or great posts that discuss this? If
  you have some relevant papers to refer to, this can serve as a more detailed
  theoretical background.

This section is intended to encourage you as an author to think about the
lessons from other languages, provide readers of your RFC with a fuller picture.
If there is no prior art, that is fine - your ideas are interesting to us
whether they are brand new or if it is an adaptation from other languages.

Note that while precedent set by other languages is some motivation, it does not
on its own motivate an RFC. Please also take into consideration that Crystal
sometimes intentionally diverges from common language features.
-->

Golang's [netpoll](https://go.dev/src/runtime/netpoll.go) uses a similar design.

# Unresolved questions

<!--
- What parts of the design do you expect to resolve through the RFC process
  before this gets merged?*
- What parts of the design do you expect to resolve through the implementation
  of this feature before stabilization?
- What related issues do you consider out of scope for this RFC that could be
  addressed in the future independently of the solution that comes out of this
  RFC?
-->

## Timers and timeouts

We're missing a proper data structure to store timers and timeouts. It must be
thread safe and efficient. Ideas are a minheap (4-heap) or a skiplist. Timers
and timeouts may need to be handled separately.

This issue is blocking. An inefficient data structure wrecks performance for
timers and timeouts.

## Performance issues on BSDs

The `kqueue` driver is disabled on DragonFly BSD, OpenBSD and NetBSD due to
performance regressions.

- DragonFly BSD: Running `std_spec` is eons slower than libevent. It regularly
  hangs on `event_loop.run` until the stack pool collector timeout kicks in
  (i.e. loops on 5s pauses).

- OpenBSD: Running `std_spec` is noticeably slower (4:15 minutes) compared to
  libevent (1:16 minutes). It appears that the main fiber keeps re-enqueueing
  itself from the event loop run (10us on each run).

- NetBSD: The event loop doesn't work with `kevent` returning `ENOENT` for the
  signal loop `fd` and `EINVAL` when trying to set an `EVFILT_TIMER`.

The `kqueue` driver works fine on FreeBSD and Darwin.

These issues are non-blocking. We can keep using `libevent` on these operating
systems until resolved.

# Future possibilities

<!--
Think about what the natural extension and evolution of your proposal would be
and how it would affect the language and project as a whole in a holistic way.
Try to use this section as a tool to more fully consider all possible
interactions with the project and language in your proposal. Also consider how
this all fits into the roadmap for the project and of the relevant sub-team.

This is also a good place to "dump ideas", if they are out of scope for the RFC
you are writing but otherwise related.

If you have tried and cannot think of any future possibilities, you may simply
state that you cannot think of anything.

Note that having something written down in the future-possibilities section is
not a reason to accept the current or a future RFC; such notes should be in the
section on motivation or rationale in this or subsequent RFCs. The section
merely provides additional information.
-->

* `aio` for async read/write over regular disk files with `kqueue`
* Integrate more evented operations such as `signalfd`/`EVFILT_SIGNAL` and
  `pidfd`/`EVFILT_PROC`.
