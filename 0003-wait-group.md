- Feature Name: `wait_group`
- Start Date: 2024-02-06
- RFC PR: [crystal-lang/rfcs#3](https://github.com/crystal-lang/rfcs/pull/3)
- Implementation PR: [crystal-lang/crystal#0000](https://github.com/crystal-lang/crystal/pull/14167)

# Summary

Provide a mechanism to wait on the execution of a set of operations distributed to a set of fibers.

# Motivation

Applications currently rely on Channel(Nil) to implement this:

```crystal
chan = Channel(Nil).new(256)

256.times do |i|
  spawn do
    sliced_operation(i)
  ensure
    chan.write(nil)
  end
end

256.times { channel.receive }
```

In the above example, the main fiber will be resumed 256 times and the nil value be sent and received 256 times in the channel queue. Neither of these are necessary.

# Guide-level explanation

Introduce a new WaitGroup class that would keep a counter of how many fibers to wait for, each fiber would report when they're done, and the main fiber only be resumed once all fibers are done.
All methods can be called concurrently as well as in parallel (so the type must be thread-safe), and there may be multiple fibers waiting on the same WaitGroup at the same time.

The main usage is very close to how we'd use a Channel(Nil), except that we resume the main fiber once (not N times) and we don't pass any value to a queue (less allocations, less moving data). The intent is also more clear: a fiber is waiting, a fiber reports that it terminated.

WaitGroup would also allow scenarios that aren't possible with Channel(Nil):

- Mutable counter: a WaitGroup may be modified at any time (but always _before_ the fiber calls `#done`) to increment or decrement the counter. The waiting fibers don't need to know about these changes: they will wait until all the execution is done.

- Signaling fibers: multiple fibers can wait on a WaitGroup, so we can signal a set of fibers at once. For example have a set of fibers wait before starting execution.

# Reference-level explanation 

The proposed API:

```crystal
class WaitGroup
  def initialize(counter = 0)

  # Increments the counter by *n* (decrements if n < 0).
  # Resumes pending fibers when the counter reaches 0.
  # Raises if the counter reaches below 0.
  def add(n : Int) : Nil

  # Decrements the counter by 1.
  # Resumes pending fibers when the counter reaches 0.
  # Raises if the counter reaches below 0.
  def done : Nil
    add(-1)
  end

  # Blocks the current fiber until the counter reaches 0.
  def wait : Nil
end
```

All methods can be called concurrently as well as in parallel (so the type must be thread-safe), and there may be multiple fibers waiting on the same WaitGroup at the same time.

The following example usage is very close to how we'd use a Channel, except that we resume the main fiber once (not 256 times) and we don't pass any value to a queue. 

```crystal
def sliced_operation(wg, i)
  wg.add(32)

  32.times do |j|
    spawn do
      sub_sliced_operation(i, j)
    ensure
      wg.done
    end
  end
end

wg = WaitGroup.new(16)

16.times do |i|
  spawn do
    prepare_slice(i)
    sliced_operation(wg, i)
  ensure
    wg.done
  end
end

wg.wait
```

# Drawbacks

We introduce a new synchronization primitive to fix an issue that could be non-existent with a different concurrency pattern (i.e. structured concurrency).

# Rationale and alternatives

Structured concurrency, where descendant fibers can't outlive their direct parent, could achieve the same behavior of the initial scenario (waiting on fibers), possibly obsoleting the proposed WaitGroup object.

The proposed WaitGroup type would still have some advantages: it can signal fibers, can wait on arbitrary fibers (albeit breaking the principle of structured concurrency), and at worst be a building block for waiting on said descendant fibers.

# Prior art

Go has the sync.WaitGroup type. Java has the CountDownLatch class. Both behave in a similar way as the proposed solution.

The [Earl](https://www.shardbox.org/shards/earl) shard uses a WaitGroup type in its Supervisor and Pool classes to wait on the child fibers it spawned.

# Unresolved questions

What should happen when the counter reached zero? The `#add` and `#done` shall raise a RuntimeError exception, but what about waiting fibers? They might be stuck forever.

- Should the application abort (aka panic)?
- Should the waiting fibers be resumed _and_ also raise a RuntimeError exception?

# Future possibilities

WaitGroup may eventually be used to implement higher level constructs, for example in structured concurrency, or Erlang-like supervisors. It might also be integrated into `select` expressions to wait alongside channels and timeouts.
