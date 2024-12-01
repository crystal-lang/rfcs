- Feature Name: `timers`
- Start Date: 2024-11-22
- RFC PR: [crystal-lang/rfcs#12](https://github.com/crystal-lang/rfcs/pull/12)
- Issue: ...

# Summary

Determine a general interface and internal data structure to handle and store
timers in the Crystal runtime.

# Motivation

With the Event Loop overhaul made possible by [RFC 7] and achieved in [RFC 9]
where we remove the libevent dependency, that we already didn't use on Windows,
we need to handle the correct execution of timers ourselves.

We must handle timers, we must store them into efficient data structure(s), and
we must suppor the following operations:

- create a timer;
- cancel a timer;
- execute expired timers;
- determine the next timer to expire, so we can decide for how long a process or
  thread can be suspended (usually when there is nothing to do).

The IOCP event loop currently uses an unordered `Deque`, and thus needs a simple
O(1) operation to insert a time, but needs a linear scan to delete the timer and
a full scan to decide the next expiring timer or to dequeue the expired timers.

The Polling event-loop (wraps `epoll` and `kqueue`) uses an ordered `Deque` and
needs a linear scan for insert and delete, but getting the next expiring timer
and dequeueing the expired timers is O(1).

This is far from efficient. We can do better.

# Guide-level explanation

First we emphasize that Crystal cannot be a realtime language (at least without
dropping the whole stdlib) because it relies on a GC that can stop the world at
any time and for a long time; the fiber schedulers also only reach to the event
loop when there is nothing left to do. These necessarily **introduce latencies
to the execution of expired timers**.

We can categorize timers into two categories, that I shamelessly took from the
[Hrtimers and Beyond: Transforming the Linux Time
Subsystems](https://www.kernel.org/doc/ols/2006/ols2006v1-pages-333-346.pdf)
paper about the introduction of high resolution timers in the Linux kernel:

1. **Timeouts**: Timeouts are used primarily to detect when an event (I/O
   completion, for example) does not occur as expected. They have low resolution
   requirements, and they are almost always removed before they actually expire.

   In Crystal such a `timeout` may be created before every blocking read or
   write IO operation (when configured on the IO object) or to handle the
   timeout action of a `select` statement. They're usually cancelled once the IO
   operation or a channel operation becomes ready; they may expire, that is
   raise an `IO::Timeout` exception or execute the timeout branch of the
   `select` action.

   The low resolution is because timeouts are mostly about bookkeeping, to
   eventually close a connection after some time has passed for example, so a
   10s timeout running after 11s won't create issues.

2. **Timers**: Timers are used to schedule ongoing events. They can have high
   resolution requirements, and usually expire.

   In crystal such a `timer` is created when we call `sleep(Time::Span)` or
   `Fiber.yield` that behaves as a `sleep(0.seconds)`. There are no public API
   to cancel a sleep, and they always expire.

   The high resolution is because timers are expected to run at the scheduled
   time. As explained above this might be hard, but we can still try to avoid
   too much latency.

Both categories share common traits:

- fast `insert` operation (lower impact on performance, especially with
  parallelism);
- fast `get-min` operation (same as `insert` but less frequently called);
- reasonably fast `delete-min` operation (only needed when processing expired
  timers);

However they differ in these other traits:

1. Timeouts:

   - low precision (some milliseconds is acceptable);
   - fast `delete` operation (likely to be cancelled);
   - must accomodate many timeouts at any given time (e.g. [c10k problem](https://en.wikipedia.org/wiki/C10k_problem)).

2. Timers (sleeps):

   - high precision (sub-millisecond and below is desireable);
   - no need for `delete` (never cancelled);
   - more reasonable number of timers (**BOLD CLAIM TO BE VERIFIED**)

These requirements can help us to shape which data structure(s) to choose.

## Relative clock

The relative clock to compare the time against. For example `libevent` uses the
monotonic clock, and the other event loop implementations followed suits (AFAIK).

This hasn't been an issue for the current usages in Crystal that always consider
an interval from now (be it a timeout or a sleep).

# Reference-level explanation

> [!CAUTION]
> This is a rough draft, asking more questions than providing answers!
>
> The technical definition will come and evolve as we experiment and refactor
> the different event loops.
>
> For example the technical details of abstracting the interface to be usable
> from different event loops lead to technical issues, notably around how to
> define the individual `Timer` interface, its relationship with the event loop
> `Event` actual object (e.g. struct pointer in the polling evloop), ...

**TBD**: the general internal interface, for example (loosely shaped from the
polling event loop, with different wording):

```crystal
# The type `T` must implement `#wake_at : Time::Span` and return the absolute
# time at which a timer expires (monotonic clock).

class Crystal::Timers(T)
  # Schedules a timer. Returns true if it is the next timer to expire.
  abstract def schedule(timer : T) : Bool

  # Cancels a previously scheduled timer. Returns a tuple(deleted,
  # was_next_timer_to_expire).
  abstract def cancel(timer : T) : {Bool, Bool}

  # Yields and dequeues expired timers to be executed (cancel timeout, resume
  # fiber, ...).
  abstract def dequeue_expired(& : T ->) : Nil

  # Returns the absolute time at which the next expiring timer is scheduled at.
  # Returns nil if there are no timers.
  abstract def next_expiring_at? : Time::Span?
end
```

## Data structure: min pairing heap

A min-heap is a simple, fast and efficient tree data structure, that keeps the
smaller value as the HEAD of the tree (the rest isn't ordered). This is enough
for timers in general as we only really need to know about the next expiring
timer, we don't need the list to be fully ordered.

From the [wikipedia page](https://en.wikipedia.org/wiki/Pairing_heap): in
practice a D-ary heap is always faster unless the `decrease-key` operation is
needed, in which case the Pairing HEAP often becomes faster (even to supposedly
more efficient algorithms, like the Fibonacci HEAP).

An initial implementation (twopass algorithm, no auxiliary insert, intrusive
nodes) led to to slighly faster `insert` time than a D-ary Heap (that needs more
swaps) especially when timers come out of order, but a noticeably slower
`delete-min` since it must rebalance the tree. The `delete` operation however
quickly outperforms the 4-heap, even at low occupancy (a hundred timers) and
never balloons.

Despite the drawback on the `delete-min` operation, a benchmark using mixed
operations (insert + delete-min, insert + delete) led the pairing heap to have
the best overall performance. See the [benchmark
results](https://gist.github.com/ysbaddaden/a5d98c88105ea58ba85f4db1ed814d70)
for more details.

Since it performs well for timers (add / delete-min) and timeouts (add / delete
and sometimes delete-min) as well I propose to use it to store both categories
in a single data structure.

Reference:

- [Pairing Heaps: Experiments and Analysis](https://dl.acm.org/doi/pdf/10.1145/214748.214759)

# Drawbacks

TBD.

# Rationale

This is an initial proposal for a long term work to internally handle timers in
the Crystal runtime. It aims to forge the path forward as we refactor the
different event loops (`IOCP`, `Polling`), introduce new ones (`io_uring`), and
as we evolve the public API interface.

# Alternatives

## Deque

We could treat `Fiber.yield` and `sleep(0.seconds)` and by extension any already
expired timer specifically with a push to a mere `Deque`: no need to keep these
in an ordered data structure.

## 4-heap (D-ary HEAP)

A [D-ary HEAP] can be implemented as a flat array to take full advantage of CPU
caches, and be binary or higher. Even at large occupancy (million timers) the
overall performance is excellent... except for the `delete` operation that
cannot benefit from the tree structure, and requires a linear scan. Performance
quickly plummets at low to moderate occupancy (thousand timers) and becomes
unbearable at higher occupancies.

Aside from timeouts, timers (sleeps) could take advantage of this data structure
since we can't cancel a sleep (so far).

## Skip list

An alternative to heaps is the [skip list](https://en.wikipedia.org/wiki/Skip_list)
data structure. It's a simple doubly linked list but with multiple levels. The
lowest level is the whole list, while the higher levels skip over more and more
entries, leading to quick arbitrary lookups (from highest down to the lowest).

While the `delete-min` has excellent performance, the increased cost of keeping
the whole list ordered on every add/remove and creating and deleting multiple
links reduces the overall performance compared to the pairing heap.

## Non-cascading timer wheel

> [!NOTE]
> The concept is a total rip-off from the Linux kernel!
> - [documentation](https://www.kernel.org/doc/html/latest/timers/highres.html)
> - [LWN article](https://lwn.net/Articles/646950/) that explains the core idea;
> - [implementation](https://github.com/torvalds/linux/blob/master/kernel/time/timer.c) (warning: GPL license!)

The idea derives from the "hierarchical timing wheels" design. This is a ring
(circular array) of N slots sub-divided into M slots where each individual slot
represents a jiffy (or moment) with a specific precision (1ms, 4ms or 10ms for
example). Each slot is a doubly linked list of events scheduled for the
specified jiffy. Each M slots represent a wheel, with less precision the higher
we climb up the wheels. When we process timers, we process the expired timers
from the "last" processed slot up to the "current" slot.

The usual disadvantage of hierarchical timer wheels is that whenever we loop on
the initial wheel we must cascade down the timers from the upper wheel into the
lower wheel. This can lead to multiple cascades in a row.

The trick is to skip the cascade altogether. This means losing precision (the
farther in the future the larger the delta), which is unacceptable for timers,
but for timeouts? They're usually cancelled and we don't need to run precisely
at the scheduled time, we just need them to run.

Example table from the current linux kernel (jiffies at 10ms precision, aka
100HZ). The ring has 512 slots in total and can accomodate timers up to 15 days
from now:

    Level Offset  Granularity            Range
     0      0         10 ms               0 ms -        630 ms
     1     64         80 ms             640 ms -       5110 ms (640ms - ~5s)
     2    128        640 ms            5120 ms -      40950 ms (~5s - ~40s)
     3    192       5120 ms (~5s)     40960 ms -     327670 ms (~40s - ~5m)
     4    256      40960 ms (~40s)   327680 ms -    2621430 ms (~5m - ~43m)
     5    320     327680 ms (~5m)   2621440 ms -   20971510 ms (~43m - ~5h)
     6    384    2621440 ms (~43m) 20971520 ms -  167772150 ms (~5h - ~1d)
     7    448   20971520 ms (~5h) 167772160 ms - 1342177270 ms (~1d - ~15d)

The technical operations are:

- `insert`: determine the slot (relative to the current slot), append (or
  prepend) to the linked list;
- `delete`: remove the timer from any linked list it may be in (no need to
  lookup the timer);
- `get-min`: the delta between the current and the first non empty slot (can be
  sped up with a bitmap of (not)empty slots);
- `delete-min`: process the linked list(s) as we advance the slot(s).

Aside from deciding the slot, all these operations involve mere doubly linked
list operations.

**NOTE** I didn't test this solution, it currently sounds overkill; yet the
overall simplicity makes it a good contender to the pairing heap for storing
timeouts. In that case maybe a dual D-ary Heap for timers and a Timing Wheel for
timeouts would be a better choice than the single Pairing Heap?

# Prior art

- `libevent` stores events with a timer into a min-heap, but it also keeps a
  list of "common timeouts"... I didn't investigate what they mean by it
  exactly.

- Go stores all timers into a min-heap (4-ary) but allocates timers in the GC
  HEAP and merely marks cancelled timers on delete. I didn't investigate how
  it deals with the tombstones.

- The Linux kernel keeps timeouts in a non cascading timing wheel, and timers in
  a red-black tree. See the [hrtimers] page.

# Unresolved questions

TBD.

# Future possibilities

The monotonic relative clock can be an issue for timers that need to execute at
a specific realtime, that is relative to the realtime clock. We might want to
introduce an  explicit `Timer` type that could expire once or at a defined
interval, using different clocks (realtime, monotonic, boottime), as well as be
absolute or relative to the current time.

These would fall into the *timers* category, and change the requirements for
them from "never cancelled" to "sometimes cancelled", though in practice it
should probably be implemented using system timers, for example `timerfd` on
Linux, `EVFILT_TIMER` on BSD, something else on Windows.

[RFC 7]: https://github.com/crystal-lang/rfcs/pull/7
[RFC 9]: https://github.com/crystal-lang/rfcs/pull/9
[D-ary HEAP]: https://en.wikipedia.org/wiki/D-ary_heap
[hrtimers]: https://www.kernel.org/doc/html/latest/timers/hrtimers.html
