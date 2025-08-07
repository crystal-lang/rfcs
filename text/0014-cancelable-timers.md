---
Feature Name: cancelable-timers
Start Date: 2025-08-02
RFC PR: "https://github.com/crystal-lang/rfcs/pull/0014"
PoC PR: "https://github.com/crystal-lang/crystal/pull/16070"
Issue: N/A
---

# Summary

I propose to introduce a cancelable timer, designed to be low level, yet simple
and efficient, allowing higher level abstractions, such as a pool of connections
for example, to easily add timeout features.


# Motivation

Synchronization primitives, such as mutexes, condition variables or pools, could
take advantage of a simple timeout mechanism. For example try to checkout a
connection from the pool and fail after 5 seconds.

Crystal already provides the `sleep` method that suspends the execution of a
fiber for some time and eventually resumes it. A sleep timer will necessarily
expire and cannot be canceled. We can technically resume the fiber early (just
enqueue it), but since we can't cancel the sleep timer the fiber would be
resumed twice: once manually, and a second time when the timer expires.

Crystal also implements a timeout action for `select`, which is great when we
have channels, but would require to create virtual channels when all we need is
the timeout feature.

Adding timeouts to all the synchronization primitives in the stdlib, and
possibly to custom ones in shards and applications, should ideally not be much
harder than calling `#sleep`.


# Terminology

- `event loop` enables non-blocking operations. See [RFC 0007] for details.

- `timer` refers to an event that triggers after after some time has elapsed or
  an absolute time. Timers are handled by the event loop. See [RFC 0012] for
  details.

- `sleep` refers to the [`sleep(time)`] method that suspends the execution of
  the current fiber for some time. It creates a non cancelable timer in the
  event loop.

- `timeout` refers to the proposed ability to suspend the execution of a fiber
  until it is explicitly resumed (canceled timeout) or some time has elapsed
  (expired timeout). It would create a cancelable timer in the event loop.


# Guide-level explanation

Let's take a mutex with the ability to try to lock and give up after a certain
timeout as an example.

On failure to acquire the lock, the current fiber shall add itself into a
waiting list (private to the mutex), and arm a timeout (aka cancelable timer).
For reasons explained in the [Rationale section](#rationale) below, we need a
cancelation token to safely cancel the timeout, and thus need to save both the
current fiber and the cancelation token to the mutex' waiting list. The timer
itself shall be handled by the event loop implementation (see the [Reference
section](#reference-level-explanation)).

When the lock is released, the mutex shall try to wake a waiting fiber. We can't
enqueue the fiber directly, because the timer may have expired and the event
loop have already enqueued the fiber; we must prevent this situation to ensure
that the fiber is only resumed once.

To solve this, we introduce a rule: the one that can cancel the timeout is the
only one that can enqueue the fiber (it owns the fiber). Both the mutex and the
event loop must try to cancel the timeout using the cancelation token (created
by the lock method). On success the mutex must enqueue the fiber, on failure it
simply skips the fiber (another fiber or thread already enqueued it) and the
mutex shall try to wake another waiting fiber instead.

When the suspended fiber is finally resumed, it must verify the outcome (expired
or canceled) and act accordingly:

- If the timeout expired, the fiber must remove itself from the mutex waiting
  list and can return an error or raise an exception for example.

- If the timeout was canceled, then the fiber was manually resumed by the unlock
  method and shall try to acquire the lock again. On failure it would add itself
  back into the waiting list and arm another timeout for the remaining time.

The [Reference](#reference-level-section) below contains an example
implementation for such a cancelable mutex using the proposed API.


# Rationale

The complexity of a cancelable timer over a simple sleep is that the cancelation
leads to synchronization issues. For example, multiple threads may try to cancel
a timeout at the same time while another thread is trying to process the expired
timer, and only one of these shall resume the fiber. We also need to report
whether the timer expired or has been canceled.

A straightforward solution is to use an atomic: the fiber sets the atomic before
suspending itself, then any attempt to enqueue the fiber must be the one that
succeeds to unset the atomic. This can be achieved with an `Atomic(Bool)` for
example (`#set(true)` then `#swap(false) == true`).

The atomic could be a property on `Fiber`, it's easily accessible to anything
that already knows about it, be it a waiting fiber in a mutex or a waiting timer
event in the event loop. The problem is that there is no telling if the timeout
changed in between. This is more commonly known as the ABA problem.

The common solution is to increment the atomic value on every attempt to change
the value using compare-and-set (CAS). If the atomic value didn't change, the
CAS succeeds, and the timeout is succesfully resolved. Other attempts will fail
because the value changed, so even if the timeout is set again, the value will
have been incremented and the CAS will always fail. Albeit, the counter will
eventually wrap, but after so many iterations that it's impossible to hit the
ABA issue in practice. For example, an UInt32 word with a 1 bit flag would need
2,147,483,648 iterations!

The counterpart is that every waiter and timer event must know the current
atomic value (thereafter called `cancelation token`) to be able to resolve the
timeout. I believe this is an acceptable trade off.

> [!NOTE]
> Alternatively, we could allocate the atomic in the HEAP, but then every
> timeout would depend on the GC, and we'd still need to save the pointer for
> every waiter and timer. We can't store it on `Fiber` because we'd jump back
> into the ABA problem.

For our use case, we can rely on a few properties to choose the best atomic
operation:

1. The fiber can only be suspended once at a time, and can thus only be waiting
   on a single timeout (or a sleep) at a time. Last but not least, only the
   current fiber can decide to create a timeout (a third party fiber can't).
   Hence we can merely set the value when setting the timeout (no need for CAS).

2. The flag is enough to prevent multiple threads to unset the timeout in
   parallel, however we must increment the value when we *set the timeout again*
   to prevent another thread from mistakenly unset the new timeout. Hence
   setting the timeout must increment the value, but resolving can merely unset
   the flag.

> [!TIP]
> To keep the flag and the increment in the same atomic value, we can use an
> UInt32 value, use bit 1 for the flag, so 0 and 1 denote the unset and set
> states repectively, and use bits 2..32 to increment the value, thus adding 2
> to do the increment—with more flags we'd shift the increment by 1 bit.
>
> Setting the timeout must get the atomic value, set the first bit and increment
> by 2 (wrapping on overflow): `token = (atm.get | 1) &+ 2` while resolving the
> timeout shall unset the first bit: `token & ~1`.


# Reference-level explanation

## Public API (`Fiber`)

We introduce an enum: `Fiber::TimeoutResult` with two values: `CANCELED` and
`EXPIRED`. We could return a `Bool` but then we'd be left wondering whether
`true` means expired or canceled.

We introduce a `TimeoutToken` struct for wrapping the atomic value and to
represent the cancelation token as a fully opaque type (you can't inadvertently
tamper with the value).

The public API can do with a couple methods:

- `Fiber.timeout(duration : Time::Span, & : Fiber::TimeoutToken ->) : Fiber::TimeoutResult`

  Sets the flag and increments the value of the atomic. Yields the cancelation
  token (aka the new atomic value) so the caller can record it (the block is a
  called-before-suspend callback), then delegates to the event loop to suspend
  the calling fiber and eventually resume it when the timeout expires, if it
  hasn't been canceled already.

  Returns `Fiber::TimeoutToken::CANCELED` if the timeout was canceled.
  Returns `Fiber::TimeoutToken::EXPIRED` if the timeout expired.

  All the details to add, trigger and remove the timer are fully delegated to
  the event loop implementations.

- `Fiber#resolve_timeout?(token : Fiber::TimeoutToken) : Bool`

  Tries to unset the flag of the timeout atomic value for `fiber`. It must fail
  if the atomic value isn't `token` anymore (the flag has already been unset or
  the value got incremented). Returns true if and only if the atomic value was
  sucessfully updated, otherwise returns false.

  On success, the caller must enqueue the fiber. On failure, the caller musn't.

Code calling `Fiber.timeout` is expected to call `Fiber#resolve_timeout?` to try
and cancel the timeout at some point, otherwise calling `sleep` would be more
efficient (no synchronization required) and to enqueue the fiber iff it resolved
the timeout.

## Internal API

The `Fiber` object holds the atomic value as an instance variable.

Each `Crystal::EventLoop` implement must implement one method:

- `Crystal::EventLoop#timeout(duration : Time::Span, token : Fiber::TimeoutToken) : Bool`

  The event loop shall suspend the current fiber for `duration` and returns
  `true` if the timeout expired, and `false` otherwise.

  When processing the timer event, the event loop must resolve the timeout by
  calling `fiber.resolve_timeout?(token)` and enqueue the fiber if an only if it
  returned true. It must skip the fiber otherwise.

> [!NOTE]
> We could cancel the timer event sooner, but that would require a method on
> `Fiber` to cancel the timeout, another method on every event loop to cancel
> the timer, and the event loops would have to memorize the timer event for
> every fiber in a timeout, for example using a hashmap.
>
> By delaying the timer cancelation to when the fiber is resumed, we can avoid
> all that, at the expense of keeping the timer event a bit longer than
> necessary in the timers' data structure, yet still remove it before it goes
> out of scope.

## Example

Following is an example implementation of how the mutex lock and unlock methods
from the [Guide section](#guide-level-explanation) could be implemented:

```crystal
class CancelableMutex
  # Tries to acquire the lock. Returns true if the lock was acquired. Returns
  # false if the lock couldn't be acquired before *timeout* is reached.
  def lock?(timeout : Time::Span) : Bool
    expires_at = Time.monotonic + timeout

    loop do
      if lock_impl?
        # done: lock acquired
        return true
      end

      # 1. arm the timeout
      result = Fiber.timeout(expires_at - Time.monotonic) do |token|
        # 2. save the fiber and the cancelation token
        enqueue_waiter(Fiber.current, token)

        # 3. the fiber will be suspended...
      end

      # 4. the fiber has resumed

      if result.expired?
        # 5. dequeue the waiter
        dequeue_waiter

        # done: timeout
        return false
      end

      # try again
    end
  end

  # Releases the lock.
  def unlock : Nil
    unlock_impl

    while waiter = dequeue_waiter?
      fiber, token = waiter

      if fiber.resolve_timeout?(token)
        # we canceled the timer: enqueue the fiber
        fiber.enqueue

        # done
        break
      end

      # try the next waiting fiber
    end
  end
end
```


# Drawbacks

None that I can think of.

# Alternatives

An alternative to the whole feature could be to introduce lightweight abstract
channels. One such channel could have a delayed sent that would be triggered
after some duration. A select action could merely wait on this. Yet, such an
delayed channel might be implementable on top of the timeout feature presented
here. It actually feels more like a potential evolution for `select`.

An alternative to the `Fiber.timeout(duration, &)` method would be to have
multiple methods instead (see below for an example). The control-flow might be
easier to grasp, though it might not be better in practice since it requires
multiple steps instead of a single method with a called-before-suspend block.

```crystal
token = Fiber.create_timeout(duration)
# record the current fiber and the cancelation token
sleep(token)
```

Instead of `Fiber#resolve_timeout?` we could have `TimeoutToken` keep the fiber
reference in addition to the cancelation token, and have a `#resolve?` method to
resolve the token. That would be more OOP and maybe allow  more evolutions, but
it would also make the token larger (pointer + u32 + padding) in addition to
duplicate the fiber reference that is likely to be already kept.

# Prior art

Most runtimes expose cancelable timers, directly (for example [timer_create(2)]
on POSIX) or indirectly through synchronization primitives (for example
[pthread_cond_timedwait(3)] on POSIX).

# Unresolved questions

1. Instead of adding a distinct `Fiber.timeout(time)` in addition to
   `sleep(time)` and `Fiber.suspend` we could introduce a single method that
   would always create a cancelable timer, for example `Fiber.suspend(time, & :
   TimeoutToken ->) : TimeoutResult`.

2. We may want to use *absolute time instead of relative duration*, so every use
   cases that need to retry wouldn't have to deal with caculating the remaining
   time on each iteration, and would only need to calculate the absolute limit
   (now + timeout).

   The problem is that monotonic times and durations are represented using the
   same type (`Time::Span`), and `#sleep` uses relative time. Using absolute
   time would be confusing. Maybe we can support *both* and add an `absolute`
   argument, that would default to `false`? Or have two overloads using
   different named arguments, for example `duration` vs `until`.


# Future possibilities

As a low level feature, we can use it to add timeouts a bit anywhere they'd make
sense. For example implement alternative methods that could timeout in every
synchronization primitive (`Mutex`, `WaitGroup`, ...), including those in the
[sync shard].

We might be able to use it in the IOCP event loop where we currently need to
sleep and yield in a specific timeout case, as well as other event loops for IO
timeouts (to be verified), as well as for the select action timeout that
currently relies on a custom solution.

[RFC 0007]: https://github.com/crystal-lang/rfcs/pull/7
[RFC 0012]: https://github.com/crystal-lang/rfcs/pull/12
[`sleep(time)`]: https://crystal-lang.org/api/1.17.1/toplevel.html#sleep(time:Time::Span):Nil-class-method
[timer_create(2)]: https://www.man7.org/linux/man-pages/man2/timer_create.2.html
[pthread_cond_timedwait(3)]: https://www.man7.org/linux/man-pages/man3/pthread_cond_timedwait.3p.html
[sync shard]: https://github.com/ysbaddaden/sync
