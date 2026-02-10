---
Feature Name: immutable_env
Start Date: 2026-01-19
RFC PR: "https://github.com/crystal-lang/rfcs/pull/19"
Issue: "https://github.com/crystal-lang/crystal/issues/16449"
Proof of Concept: "https://github.com/crystal-lang/crystal/pull/16567"
---

# Summary

`ENV` should be an immutable collection.


# Motivation

The system environment should be considered immutable nowadays. Environment
variables are meant to externally configure a program. We can explictly pass
a modified copy of the environment when spawning a subprocess.

Mutating environment variables at runtime to add, replace or delete an
environment variable is never safe on UNIX targets, and can cause a mere read in
another thread to segfault.

External libraries, including system libc function calls executed by the stdlib
itself (e.g. `getaddrinfo` on glibc, `execvp` on UNIX, ...), can make direct
calls to `getenv` bypassing any attempt to protect mutations with a
multiple-readers single-writer lock for example.


# Guide-level explanation

We expect the impact to be invisible to most programs:

- Reading values from `ENV` still works normally. The following calls still
  return the environment variable value set by the parent process:

  - `ENV["HOME"]`
  - `ENV["HOME"]?`
  - `ENV.fetch("HOST", "localhost")`

- To execute a subprocess, the `env` and `clear_env` arguments of `Process.new`,
  `Process.run` and `Process.exec` are already there to clear and/or set the
  environment of the child process. For example:

  ```crystal
  Process.run("sh", {"-c", "echo $FOO"}, env: { "FOO" => "child" }, &.output.gets_to_end)
  # => "child\n"
  ```

> [!NOTE]
> We highly recommend to always use the `env` (and `clear_env`) arguments
> explicitly when the environment must be customized for the child process,
> regardless of this RFC!

Still, a number of programs are gonna be affected because they mutate `ENV`,
including the Crystal's spec suites! Here are the most common cases we
identified:

- Calling `ENV["APP_ENV"] = "test"` to force the environment to a test suite;
  there should instead be an explicit setter, for example `App.env = "test"`.

- Setting the `CRYSTAL_PATH` environment variable so it will be inherited by
  every call to the `crystal` executable. Instead, we should use the `env`
  argument of `Process.new`.

- Testing the program's behavior around `ENV` variables. We could mock `ENV`
  methods, though sometimes it might no be easy (e.g. tweak `PATH` to test
  sub-processes).

- Testing `ENV` itself is challenging. Maybe we could compile an additional
  program (once), then each test would call it with a custom environment and a
  list of operations to execute and assert the output.

After running a survey, the main case for mutating `ENV` is to load a `.env`
file (or equivalent), have it mutate `ENV` and then have anything that takes
environment variables just use it. This behavior will no longer be possible.

Applications could make sure to source any `.env` before the program is executed
through a wrapper shell script, shell plugin ([direnv]), the `--env-file`
argument to docker and podman, ... or develop alternatives to not depend on
`ENV` only.

> [!NOTE]
> We can't recommend enough a configuration library such as [totem] to revisit
> and centralize your application's settings.

[direnv]: https://direnv.net/
[totem]: https://shardbox.org/shards/totem


# Reference-level explanation

A new system method is introduced to parse `LibC.environ` (or system equivalent)
into a collection of key/value entries once at startup (before any thread is
started).

The `ENV` methods are modified to access the internal collection of key/values
and to never call the system functions (`setenv`, `unsetenv` and equivalents),
at the exception of the following deprecated methods that shall mutate the
collection and call the system functions (backward compatibility):

- `ENV.[]=`
- `ENV.delete`
- `ENV.clear`

Because of backward compatibility, the internal collection must be protected by
a multiple-readers single-writer lock (rwlock) — unless we can figure out when
none of the mutating methods are called?

By extension, proposals that would lead to mutate `ENV` will be refused.

The change impacts `Process` that shouldn't assume that the environment is
inherited implicitly anymore. `Process#spawn` and `Process#exec` must now read
environment variables from `ENV` and pass an explicit list of environment
variables to the sub-processes.


# Drawbacks

The obvious drawback is that we can't change the system environment variables at
runtime anymore. We can still read the environment from the parent process and
inherit and pass an explicit environment to sub-processes.

Runtime changes to the system environment variables, for example an external
library calling `setenv`, won't be noticed by `ENV` anymore. It's unlikely for
such a scenario to happen in real life, libraries usually only read environment
variables.

Developers are attached to loading `.env` at runtime into `ENV` and then to
configure their application by reading from `ENV`. The current RFC breaks that
scenario, or makes it much more complex

Testing `ENV` itself in the stdlib spec suite is challenging. Maybe
we could compile an additional program (once), then each test would
call it with a custom environment and a list of operations to execute
and assert the output.

# Rationale and alternatives

Since the system environment is safe on single threaded programs and always safe
on Windows (even multithreaded), we can question the requirement to make `ENV`
immutable.

We can protect calls to the system functions (`getenv`, `setenv`, `unsetenv`)
using a multiple-readers single-writer lock (rwlock) on UNIX targets only (see
[#16591](https://github.com/crystal-lang/crystal/pull/16591)), but that only
synchronizes Crystal code: any external library such as libc itself can call
`getenv` while another thread running Crystal code holds the write lock and
calls `setenv` and... segfault :boom:

With [RFC 0002], programs will start using threads by default and stdlib needs
to be thread safe, and single threaded crystal programs may actually start
threads (e.g. Boehm GC or another library).

Finally, all targets shall behave the same to avoid portability issues and
confusing behavior.

[RFC 0002]: https://github.com/crystal-lang/rfcs/blob/main/text/0002-execution-contexts.md

Another solution would also snapshot the environment at startup and keep `ENV`
mutable but never call the system functions. The mutation would only affect the
snapshot. That would work, and sub-processes would still inherit the `ENV` (for
example `execvpe` on UNIX), but external libraries would be oblivious to changes
and that would lead to a confusing behavior where Crystal code and libraries
won't see the same environment variables.


# Prior art

Java and Swift parse the system environment once during startup into an internal
snapshot. The snapshot is immutable and the system environment can't be changed.

Go parses the system environment once during startup into an internal snapshot.
Go always accesses the internal snapshot and never reads from the system
environment again. Unlike Java and Swift, the snapshot is mutable, and Go calls
the system functions to mutate the system environment. Calls to the system
functions are synchronized.

Rust documents that mutating environment variables is unsafe and that your
application can segfault at any time as soon as there is more than one thread
(unless the target is Windows). Calls to the system functions are synchronized.


# Unresolved questions

It might be necessary to mutate the system environment variables in very edge
cases, so we could consider to introduce a couple public, unsafe, methods to
always access the system functions, while being explicitly unsafe:

- `ENV.unsafe_set(key : String, value : String?) : Nil`

  Updates the internal collection and calls the system function to set (value is
  `String`) or unset (value is `Nil`) the environment variable.

This method could be an easy escape to reading `.env` files at runtime. The
responsibility is on the developer to use the feature safely.


# Future possibilities

With an internal snapshot, mocking the environment safely becomes simple: we can
snapshot and restore the internal collection, raise in `#unsafe_set`, and the
rest of `ENV` will just behave normally (instead of being fully replaced).

