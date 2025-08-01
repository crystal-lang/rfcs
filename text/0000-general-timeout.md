---
Feature Name: general-timeout
Start Date: 2025-08-02
RFC PR: "https://github.com/crystal-lang/rfcs/pull/0000"
Issue: N/A
---

# Summary

Introduce a general `#timeout` feature, ideally as simple as `#sleep` that would
return whether the timer expired, or was manually canceled.


# Motivation

Synchronization primitives, such as mutexes, condition variables, pools, or
event channels, could take advantage of a general timeout mechanism.

Crystal has a mechanism in the event loop to suspend the execution of a fiber
for a set amount of time (`#sleep`). It also has a couple mechanisms to add
timeouts: one associated to IO operations, and another tailored to `Channel` and
`select` to support the timeout branch of select actions.

> [!CAUTION]
> Verify if the select action timeout mechanism can requme *twice*.

Adding timeouts to all the synchronization primitives in the stdlib, and
possibly to custom ones in shards and applications, shouldn't be much harder
than calling `#sleep`, or need to hack into the private `Fiber#timeout_event`.


# Guide-level explanation

The complexity of timeout over sleep is that it can be canceled, which leads to
synchronization issues. For example, multiple threads may try to cancel the
timeout at the same time, and yet another thread might try to process the
expired timer too.

We want the fiber to be resumed *once* and to report whether the timeout expired
or was canceled. We need synchronization and a mean to decide which thread
resolves the timeout and will enqueue the fiber. There can of course be only
one.

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

The counterpart is that every waiter and timer event must know the actual atomic
value, thereafter called `cancelation token`, to be able to resolve the timeout.

> [!NOTE]
> Alternatively, we could allocate the atomic in the HEAP, but then every
> timeout would depend on the GC, and we'd still need to save the pointer for
> every waiter and timer. We can't store it on `Fiber` because we'd jump back
> into the ABA problem.

## Synchronization primitives

Let's take a mutex for the example.

On failure to acquire the lock, the current fiber will want to add itself into a
waiting list (private to the mutex). As explained in the previous section, we
must memorize the cancelation token to be able to cancel it, so it must set the
timeout, get the token, and then add the fiber and the token to the mutex
waiting list, then delegate the timeout to the event loop implementation.

When another fiber unlocks, the mutex must try to wake a waiting fiber. While
doing this it must resolve the timeout using its cancelation token. On success
it must enqueue the fiber, on failure it must skip the fiber because another
fiber or thread has already enqueued the fiber or will enqueue it, and the mutex
shall try to wake another waiting fiber.

The resumed fiber then will know if the timer expired or was canceled, and can
act accordingly:

- If the timeout expired, the fiber must remove itself from the waiting list and
  return an error or raise an exception for example.

- If the timeout was canceled, then the fiber was manually resumed by an unlock
  and shall try to acquire the lock again. On failure it would add itself back
  into the waiting list and set a timeout for the remaining time (if any).

## Fiber

The `Fiber` object shall hold the atomic value, and provide methods to create
the cancelation token, start waiting and to resolve the timeout.

## Event loop

Each event loop shall provide a method to suspend the calling fiber for a
duration and needs to be given the cancelation token so it can resolve the
timeout when the timer expires. On success, it shall mark the event as expired
and enqueue the fiber. On failure, it must skip the fiber (it was canceled).

When the suspended fiber resumes, it must check the state of the timer. When
expired, the method can simply return, otherwise it must cancel the timer event.

> [!NOTE]
> We could cancel the timer event sooner, but that would require a method on
> Fiber to cancel the timeout, another method on every event loop to cancel the
> timer, and the event loops would have to memorize the timer event for every
> fiber in a timeout, for example using a hashmap.
>
> By delaying the timer cancelation to when the fiber is resumed, we can avoid
> all that, at the expense of keeping the timer event a bit longer than
> necessary in the timers' data structure.

# Reference-level explanation

```crystal
class Fiber
  enum TimeoutResult
    EXPIRED
    CANCELED
  end

  alias TimeoutToken = UInt32

  def self.timeout(Time::Span, & : Fiber::TimeoutToken ->) : TimeoutResult
    token = Fiber.current.set_timeout

    # yield the cancelation token so the calling fiber can add itself _and_ the
    # token to a waiting list before the fiber suspends itself
    yield token

    expired = Crystal::EventLoop.current.timeout?(duration, token)
    expired ? TimeoutResult::EXPIRED : Timeout::CANCELED
  end

  # :nodoc:
  protected def set_timeout : TimeoutToken
    token = (@timeout.get(:relaxed) &+ 2_u32) | 1_u32
    @timeout.set(token, :relaxed)
    token
  end

  def resolve_timeout?(token : TimeoutToken) : Bool
    _, success = @timeout.compare_and_set(token, (token &+ 2_u32) & ~1_u32, :relaxed, :relaxed)
    success
  end
end

class Crystal::EventLoop::Fake < Crystal::EventLoop
  def process_timer(timer : Timer)
    case timer.type
    when :timeout
      if timer.fiber.resolve_timeout?(timer.token)
        fiber.enqueue
      end
    else
      # handle other timers
    end
  end

  def timeout?(duration : Time::Span, token : Fiber::TimeoutToken) : Bool
    timer = Timer.new(:timeout, Fiber.current, duration, token)
    add_timer(timer)

    Fiber.suspend

    if timer.expired?
      true
    else
      delete_timer(timer)
      false
    end
  end
end
```

> [!CAUTION]
> We might want to use absolute times instead of relative timeouts, so every use
> cases that need to retry wouldn't have to deal with caculating the remaining
> time on each iteration, and would only need to calculate the absolute limit
> (now + timeout).
>
> The problem is that monotonic times and durations are represented using the
> same type (`Time::Span`), and `#sleep` uses relative time. Maybe we can
> support both and add an `absolute` argument, that would default to `false`?
>
> Only `Fiber.timeout()` would need the argument. The event loop API can be
> fixed to use either absolute or relative times only (depending on the
> implementations).

# Drawbacks

...

# Rationale and alternatives

The feature is designed to be low level yet simple and efficient, allowing
higher level abstractions to easily implement a timeout. Ideally this feature
might be usable to implement all the different timeouts: select action timeouts,
IO timeouts for some event loops (this needs to be investigated).

An alternative could be to introduce lightweight abstract channels. One such
channel could have a delayed sent that would be triggered after some duration. A
select action could merely wait on this. Yet, such an delayed channel might be
implementable on top of the timeout feature presented here.

# Prior art

...

# Unresolved questions

...

# Future possibilities

...
