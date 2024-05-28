- Feature Name: `event_loop-refactor`
- Start Date: 2023-05-02
- RFC PR: [crystal-lang/rfcs#0007](https://github.com/crystal-lang/rfcs/pull/0007)
- Issue: [crystal-lang/crystal#10766](https://github.com/crystal-lang/crystal/issues/10766)

# Summary

Refactor the event loop interface to be decoupled from `libevent` and adapts to
the needs of multithreaded execution contexts ([RFC #0002](https://github.com/crystal-lang/rfcs/pull/0002)).

# Motivation

The event loop is the central piece for enabling non-blocking operations and other event-based activities.

The original implementation of `Crystal::EventLoop` etc. is heavily based on `libevent` which was the first backing driver. Now we have an event loop based on IOCP for Windows and a version for the stripped-down abilities on WASI. Another implementation based on `io_uring` has already been proposed ([#10768](https://github.com/crystal-lang/crystal/pull/10768)).

All these implementations have quite different designs and requirements. Shoehorning them into an API intended for `libevent` isn’t ideal. Hence the interface should be refactored to be more generic.

Another concern is that `io_uring` is generally available on Linux, but requires a modern kernel. A Crystal program should be able to fall back to an `epoll` based selector if `io_uring` is unavailable.

There’s an ongoing refactoring effort for enhanced multi-threading features, which includes a refactoring of the scheduler ([RFC #0002](https://github.com/crystal-lang/rfcs/pull/2)).
This context also asks for some changes to the event loop interface to allow more capable and efficient scheduling implementations.
This has also brought up the idea to use system event loops directly instead of `libevent` (which is essentially a cross-platform wrapper around them).
This would also allow to take control of the abstraction and open possibilities for further optimization in Crystal resulting in more performance.

# Guide-level explanation

`Crystal::EventLoop` exposes a generic and compact interface for actions that are to be performed on Crystals event loop.
This interface is used in the implementation of asynchronous IO and other evented operations.

Compared to the previous event loop implementation, actions are entirely self-contained instead of scattered between the event loop and the system implementations of `Socket` and `Crystal::System::FileDescriptor`.

For example, the previous, platform-specific implementation of `Socket#unbuffered_read` for Unix systems:
```cr
private def unbuffered_read(slice : Bytes) : Int32
  evented_read(slice, "Error reading socket") do
    LibC.recv(fd, slice, slice.size, 0).to_i32
  end
end
```

The new, portable implementation of `Socket#unbuffered_read`:
```cr
private def unbuffered_read(slice : Bytes) : Int32
  event_loop.read(self, slice)
end
```

The new API initially supports adaptations of the existing backends `libevent` and `IOCP`.
The next steps are additional implementations based on `io_uring`, as well system selectors (`kqueue` and `epoll`), skipping libevent to improve performance.

Further extensions can widen the scope of the event loop.

`Crystal::Eventloop` is an internal API, thus changing it does not break backwards compatibility.

## Terminology

- **Event loop**: an abstraction to wait on specific events, such as timers (e.g. wait until a certain amount of time has passed) or IO (e.g. wait for an socket to be readable or writable).

- **Crystal event loop:** Component of the Crystal runtime that subscribes to and dispatches events from the OS and other sources to enqueue a waiting fiber when a desired event (such as IO availability) has occured. It’s an interface between Crystal’s scheduler and the system’s event loop backend.

- **System selector:** The system implementation of an event loop which the runtime component depends on to receive events from the operating system. Example implementations: `epoll`, `kqueue`, `IOCP`, `libevent` (a cross-platform wrapper of the former), `io_uring`

- **Scheduler:** manages fibers’ executions inside the program (controlled by Crystal), unlike threads that are scheduled by the operating system (outside of the accessibility of the program).

## General Design Principles

- **Generic API**: Independent of a specific event loop design
- **Black Box**: No interference with internals of the event loop
- **Pluggable**: It must be possible to compile multiple event loop implementations and choose at runtime.
  Only one type of implementation will typically be active (it would be feasible to have different event loop implementations in different execution contexts, if there's a use case for that).

# Reference-level explanation

The new `EventLoop` defines the following interface for issuing operations on the event loop:

```cr
module EventLoop
  # Reads at least one byte from the file descriptor into *slice* and continues
  # fiber when the read is complete.
  # Returns the number of bytes read.
  abstract def read(file : Crystal::System::FileDescriptor, slice : Bytes) : Int32

  # Reads at least one byte from the socket into *slice* and continues fiber
  # when the read is complete.
  # Returns the number of bytes read.
  abstract def read(socket : ::Socket, slice : Bytes) : Int32

  # Writes at least one byte from *slice* to the file descriptor and continues
  # fiber when the write is complete.
  # Returns the number of bytes written.
  abstract def write(file : Crystal::System::FileDescriptor, slice : Bytes) : Int32

  # Writes at least one byte from *slice* to the socket and continues fiber
  # when the write is complete.
  # Returns the number of bytes written.
  abstract def write(file : ::Socket, slice : Bytes) : Int32

  # Accepts an incoming TCP connection on the socket and continues fiber when a
  # connection is available.
  # Returns a handle to the socket for the new connection.
  abstract def accept(socket : ::Socket) : ::Socket::Handle?

  # Opens a connection on *socket* to the target *address* and continues fiber
  # when the connection has been established.
  # Returns `IO::Error` but does not raise.
  abstract def connect(socket : ::Socket, address : ::Socket::Addrinfo | ::Socket::Address, timeout : ::Time::Span?) : IO::Error?

  # Writes at least one byte from *slice* to the socket and continues fiber when
  # the write is complete.
  # Returns the number of bytes written.
  abstract def send(socket : ::Socket, slice : Bytes) : Int32

  # Writes at least one byte from *slice* to the socket with a target *address* (UDP)
  # and continues fiber when the write is complete.
  # Returns the number of bytes written.
  abstract def send_to(socket : ::Socket, slice : Bytes, address : ::Socket::Address) : Int32

  # Receives on the socket into *slice*  and continues fiber when the package is
  # completed
  # Returns the number of bytes received.
  abstract def receive(socket : ::Socket, slice : Bytes) : Int32

  # Receives on the socket into *slice*  and continues fiber when the package is
  # completed.
  # Returns a tuple containing the number of bytes received and the source address
  # of the packet (UDP).
  abstract def receive_from(socket : ::Socket, slice : Bytes) : Tuple(Int32, ::Socket::Address)

  # Closes the *resource*.
  abstract def close(resource) : Nil
end
```

Notable differences from the previous API:

* Timeout and resume events are not on the event loop. The scheduler is supposed to handle them directly.
  `Crystal::System::Event` gets removed as this was its only use case.
* The behaviour of event loop actions `read` and `write` has been unified: they both read/write at least one byte and return the number of bytes read/written.
  This keeps the event loop implementation minimal and more versatile. Previously, `write` was expected to write *all* bytes of the given slice.

# Drawbacks

None.

# Rationale and alternatives

TBD

# Prior art

## References

- <https://tinyclouds.org/iocp_links>
- Zig: [Proposal: Event loop redesign (ziglang/zig#8224)](https://github.com/ziglang/zig/issues/8224)
- [\[RFC\] Fiber preemption, blocking calls and other concurrency issues (crystal-lang/crystal#1454)](https://github.com/crystal-lang/crystal/issues/1454)

# Unresolved questions

- Distinction between generic system APIs and event loop-specifics is not always clear.

- Should the implementation of the Crystal event loop be in the same type as the bindings for the system selector? (i.e. are `#read(Socket, Bytes)` and `#create_resume_event(Fiber)` in the same place?)

- How many event loops are there gonna be in relation to execution contexts? ([ysbaddaden/execution_context#7](https://github.com/ysbaddaden/execution_context/issues/7))

### What’s the scope of the Crystal event loop?

This is a list of operations which we expect to go through the event loop:

- File descriptor: read, write
- Socket: read, write, accept, connect, send, receive
- Process: wait (Windows)
-
Potential extensions:

- DNS resolution? ([Async DNS resolution #13619](https://github.com/crystal-lang/crystal/issues/13619))
- OS signals?
- File system events?
- OS event (eventfd) ?
- User events

Should events from the Crystal runtime be part of the event loop as well?

- Fiber: sleep
- Select actions: send, receive, timeout

### Optional event loop features

Some activities are managed on the event loop on one platform but not on others. Example would be `Process#wait` which goes through IOCP on Windows but on Unix it’s part of signal handling. (Note: Perhaps we could try to get that on the event loop on Unix as well? **🤔** But there are other examples of system differences)

Do we require these optional methods to be present in all event loop implementations, i.e. they’re part of the global interface? Some impls would then just raise “Not implemented”. Alternatively, we could keep them out of the main interface and check for availability via `event_loop.responds_to?`. or a sub interface (`is_a?(EventLoop::Process)`). Or…?

#### Socket

One instance of this problem shows already in the core features: The event loop interface has type restrictions of the `Socket` namespace in abstract defs, but `Socket` is not in the core lib.

Options:

- Omit those abstract defs (dilutes the interface, so not ideal)
- Split `EventLoop` interface and add parts of it only with `require “socket”`
- Add stub declarations for the involved types (`Socket::Handle` and `Socket::Address` - `Socket` itself is only used as parameter type which is technically okay for abstract methods)

### Type for sizes

Currently, the return type of `unbuffered_read` is unspecified and there’s a bit of a mess. Technically, it can only be `Int32` because that’s the size of `Slice`. We could use the same in the event loop API. However, in order to be future proof for bigger sizes (<https://github.com/crystal-lang/crystal/issues/4011>), we could design the API with `SizeT` instead. Considering it’s a low-level system API, this should be fine and makes a lot of sense.\
Currently, the only possible values would still be the positive range of `Int32`, so there would be no conversion risk.

### Blocking event loop

There should be a basic implementation with blocking syscalls when non-blocking operation is unavailable. This would currently be used for WASI, for example, and allows IO to work, although not as efficiently.

When evented operations are not available (for example file system operations or DNS resolution), the scheduler could automatically fall back to execute the operation in a separate thread.

This works well with the libevent implementation because if the lib calls never return `EAGAIN`, the code works entirely without libevent. The WASI implementation raises when trying to create a resume event, but that never happens when IO operations are all blocking (`~O_NONBLOCK`). For that to happen, we’d need to explicitly set the IO to blocking.

Alternative idea: If polling is unavailable, we could consider sleeping the fiber for some time and let it retry again **🤷**

### `#connect` timeout

`Socket#connect` is the only method with a timeout parameter. This seems weird. All other timeouts are configured on the IO instance.
It probably makes sense to standardize, introduce a new property `Socket#connect_timeout`, and deprecate the def parameter.

### Bulk events without fibers

For some applications it might be useful to interact with the event loop directly, being able to push operations in bulk without having to spawn (and wait) a fiber for each one.

- [Fiber usage in high IO application](https://forum.crystal-lang.org/t/fiber-usage-in-high-io-application/6689)

### **#Integration with** `select`

`select` actions are implemented completely independent of the event loop, yet they operate in a similar domain (wait for something to happen). These actions are special in that they ensure atomicity. When waiting on multiple actions simultaneously, it’s guaranteed that only one of them executes. This probably won’t be exactly possible with most event loop features.

It would certainly be nice if we could use more actions with `select` and maybe putting everything on the event loop is actually the best path forward with that?

```cr
select
when data = @socket.gets
end
```

# Future possibilities

* Alternative event loop implementations based directly on the system selectors
  instead of `libevent`.
