---
Feature Name: process-spawn-api
Start Date: 2022-02-28
RFC PR: "https://github.com/crystal-lang/rfcs/pull/25" # fill me in after creating the PR, also update the filename
Issue: "https://github.com/crystal-lang/crystal/issues/16657"
---

## Summary

Provide an ergonomic, safe, and portable API for spawning subprocesses.

## Motivation

This proposal consolidates several ongoing discussions (see [#16657]) into a coherent set of changes. We maintain backward compatibility by introducing incompatible behavior only in new method variants.

These changes aim to improve convenience and portability, and reduce accidental misuse.
Spawning processes is a fundamental capability for many programs, and many users end up writing small helpers to capture output, run one-off commands, or probe for executables. The current API is flexible but doesn't cater to some common needs, and it exposes escape hatches (`shell: true`, `$?`) that make code fragile and non-portable.

## Guide-level explanation

The modern API treats the command line as an array of strings where the first element is the program to execute, and the remaining elements are its arguments.
The command line can be given as a single string array argument, or as splat string arguments.

The `Process.capture` group of methods conveniently capture the output of subprocesses.

```cr
Process.capture("echo", "foo") # => "foo"
```

A major change to method signatures is redesigning the parameters of spawning methods from `command, args` to just `args`, or the splat variant `*args` ([#14773]).

```cr
# legacy:
Process.run("crystal", ["tool", "format"])

# both:
Process.run("crystal")

# modern:
Process.run(["crystal", "tool", "format"])
Process.run("crystal", "tool", "format")
```

String array literals offer a convenient notation that looks similar to a shell command line. Literals with interpolation (`%W`, [RFC 21]) are especially useful for process arguments with dynamic components.

```cr
Process.run(%w[crystal tool format])

path = "src/foo.cr"
Process.run(%W[crystal tool format #{path}])
```

The modern API does not support the `shell` parameter. It's generally recommended to avoid shell commands due to portability concerns.
When shell-like behavior is required, spawn the shell explicitly and pass the command string.

```cr
# legacy:
Process.run("echo foo bar | head", shell: true)

# modern:
Process.run("/bin/sh", "-c", "echo foo bar | head")
```

## Reference-level explanation

### Common method signature

All modern process-spawning methods use a canonical set of parameters that differs from the legacy variants:

1. The `command` parameter is dropped. The command argument is now the first entry in the `args` collection.
2. All other parameters become named parameters. They are all optional configuration without any clear positional order.
3. The `shell` parameter is dropped. Implicit shell mode is not supported in the modern API.

The signature of `Process.run` serves as a template for the modern API:

```cr
def Process.run(
  args : Enumerable(String), *,
  env : Env = nil, clear_env : Bool = false,
  input : Stdio = Redirect::Close, output : Stdio = Redirect::Close, error : Stdio = Redirect::Close,
  chdir : Path | String? = nil
) : Process::Status
```

Methods that yield to a block (e.g., `Process.run(&)`) now return a tuple of the block output and the process status, so callers get both without relying on the `$?` side channel.

### Single `args` array

The entire command line consisting of the command and its arguments is represented as a single value which can be passed around easily.

String array literals are a convenient way to write a command line. The syntax reads similar to a shell command, but it's actually an array and thus avoids shell parsing rules.

```cr
# splat parameter
Process.run("crystal", "tool", "format", path)
Process.run("crystal", "tool", "format", *paths) # `paths` must be a Tuple

# array literal
Process.run(["crystal", "tool", "format", path])
Process.run(["crystal", "tool", "format", *paths])

# string array literal + mutation
Process.run(%w[crystal tool format] << path)
Process.run(%w[crystal tool format].concat(paths))

# string array literal with interpolation (RFC 21)
Process.run(%W[crystal tool format #{path}])
Process.run(%W[crystal tool format #{*paths}])
```

> [!NOTE]
> String array literals with interpolation are discussed in [RFC 21].

### `shell` parameter

Because shell parsing and behaviour vary across platforms, `shell: true` is not part of the modern API.

When shell-like behavior is required, spawn the shell explicitly and pass the command string.

```cr
# legacy:
Process.run("NAME=Crystal && echo \"$NAME\"", shell: true)
Process.run("set NAME=Crystal && echo %NAME%", shell: true)

# modern:
Process.run("/bin/sh", "-c", "NAME=Crystal && echo \"$NAME\"")
Process.run("cmd.exe", "/c", "set NAME=Crystal && echo %NAME%")
```

The legacy methods with `shell` parameters will continue to work for now, but they are expected to be deprecated eventually.
This includes the methods `::system` and (`` ::` ``), as well as command literals which all implicitly use `shell: true`.

> [!NOTE]
> This issue is discussed in more detail in [#16614].

### Magic variable `$?`

Using the magic variable `$?` makes code depend on hidden state which is harder to reason about and more fragile.

Methods using the modern API always return exit status directly and do not set `$?`.

The return type of `Process.run(&)` is a tuple of the output value and the process exit status.

```cr
# legacy:
output = Process.run("crystal", ["tool", "format"]) do
  1
end
status = $?

# modern:
output, status = Process.run("crystal", "tool", "format") do
  1
end
```

### Nilable methods

In some use cases it's not an error if a process cannot execute. It might even be expected.
For example when testing the availability of a command or running an entirely optional one-off command.
These nilable method variants allow failure without having to rescue exceptions.
They return `nil` when the executable doesn't exist or is not executable (start failure).

- `Process.new?(...) : Process?`
- `Process.run?(...) : Process::Status?`

> [!NOTE]
> The discussion about these methods is in [#9896].

### Capture methods

The `Process.capture` group of methods provides a convenient tool to capture the output of the subprocess.

By default, `Process.capture` captures both `output` and `error`, but it only returns `output`.
The captured output of `error` is passed to the error message in case the process was unsuccessful. If the error output is unreasonably long, it's truncated to keep only the first and last 32kB in order to prevent resource exhaustion.
Passing any value other than `error: :pipe` prevents capturing the error stream.

- `Process.capture(...) : String`: Returns captured output or raises if the process does not terminate successfully.
- `Process.capture?(...) : String?`: Returns captured output or `nil` if the process does not terminate successfully.
- `Process.capture_result(...) : Process::Result`: Returns captured result or raises if the process fails to execute.
- `Process.capture_result?(...) : Process::Result?`: Returns captured result or `nil` if the process fails to execute.

`Process::Result` exposes the exit status of the process as well as captured output and error streams, if available.

```cr
struct Process::Result
  # Returns the captured `output` stream.
  #
  # If `output` was not captured, returns the empty string.
  def output : String
  end

  # Returns the captured `output` stream.
  #
  # If `output` was not captured, returns `nil`.
  def output? : String?
  end

  # Returns the captured `error` stream.
  #
  # If `error` was not captured, returns the empty string.
  #
  # The captured error stream might be truncated. If the total output is larger
  # than 64kB, only the first 32kB and the last 32kB are preserved.
  def error : String
  end

  # Returns the captured `error` stream.
  #
  # If `error` was not captured, returns `nil`.
  #
  # The captured error stream might be truncated. If the total output is larger
  # than 64kB, only the first 32kB and the last 32kB are preserved.
  def error? : String?
  end

  # Returns the status of the process.
  def status : Process::Status
  end
end
```

> [!NOTE]
> The discussion about these methods is in [#7171].

## Drawbacks

- The change requires some migration of call sites that previously relied on `command` + `args` positional parameters and `shell: true` behaviour.
  The introduction of new methods offsets this to some extent because they
  provide more convenient alternatives.
- Removing implicit shell behaviour may make short one-liners slightly more
  verbose when porting scripts that relied on shell features.
- Deprecating `$?` assignments reduces an implicit convenience some users  expect.
  Migration requires small code changes.

## Rationale and alternatives

### Merging `command` and `args`

The entire command line consisting of the command and its arguments is usually considered a single item. Splitting them into two values is counterintuitive.

It's easier to pass the entire command line as a single value and encourages safe argument passing without shell parsing.

A single list matches process spawn arguments in Unix operating systems (`execve`) and is closer to the representation on Windows (`CreateProcessW`).

Many APIs for spawning processes in other programming languages use a single list of arguments, with the first one representing the command.

The internal implementation already merges `command` and `args` into an array.
Exposing that in the public API can enhance efficiency.

Allowing to pass the command line as splat parameter is a convenient alternative
to requiring array literal syntax everywhere.
It also means that single commands without arguments are identical in both variants.

### Dropping `shell: true`

Shell invocation implies platform-specific parsing and potential security hazards. Rather than hide this behind a boolean, making shell invocation explicit clarifies intent and makes cross-platform portability a conscious choice.

As discussed in [#16614], `shell: true` should've never been an alternate mode of `Process.run` & co, but an entirely different method. It differs from non-shell mode with significantly altered behaviour.

We don't see any feasible way to implement a portable method with shell-like semantics, which leaves no option but to drop this mode entirely. The replacement is an explicit shell invocation. There is little benefit in abstracting that into a helper method.

A non-trivial alternative would be to embed a shell-parser library which would provide cross-platform consistency. This could be a potential enhancement in the future, but might better fit as an external library.

### Dropping `$?`

Explicit return values are easier to reason about, easier to test, and avoid subtle ordering bugs.
In the interest of code reliability it seems important to offer alternatives that don't depend on side channel communication.

We could continue to assign `$?` as a secondary option and leave it up to users whether they want to use it or not (a ban could be enforced by linter rules, for example).
But when the API already provides for direct status communication, there is no reason for using `$?` at all.

### New nilable methods

### New capture methods

Many programs need to capture output and use custom wrappers for this. This requires complex calls to `Process.run` or non-portable and potentially unsafe shell command using the command operator.
Providing a robust, well-tested implementation in the standard library is more convenient and helps avoid subtle resource and quoting bugs.

### Dropping `clear_env`

We could consider dropping `clear_env` and assuming `clear_env: true` always. This would change the semantics of `env` to be absolute instead of a merge set.
Reusing the current process' environment would require merging `ENV` explicitly: `Process.run(..., env: ENV.merge({"FOO" => "BAR"}))`. But this would silently break established and expected behaviour.
Also, inheriting from the current env seems the most common case. The current API ergonomics are optimized for that common use case.

### `Process::Options`

The set of parameters is quite extensive and duplicated across a large number of method signatures.
It might be useful to consolidate them into an options type to reduce duplication.

This would work well with a process builder API.
But it's also a big change from the current syntax.

The new utility methods should cover many use cases where custom options where required and the use of parameters other than `env` and `chdir` is expected to reduce significantly.

## Prior art

Many languages' standard libraries represent a command and its arguments as a single list.

Go provides [`Cmd.Output()`](https://pkg.go.dev/os/exec#Cmd.Output) to capture process output. It always captures stderr and exposes it in the error value. The captured amount is limited to preserving only the first 32k and last 32k bytes (see [`os.exec.ExitError`](https://pkg.go.dev/os/exec#ExitError)).

## Unresolved questions

- Deprecation of legacy API methods.
- Deprecation of command literals.

## Future possibilities

- `Process::Builder` fluent API for complex invocations with composable defaults.
- Timeouts and background job management primitives built on top of the same API.
- We could provide overloads with the modern API that accepts a single string parameter (or potentially even a string splat for arguments?) in order to keep trivial use cases like `Process.run("foo")`.
- Embedded shell parser.

[#16657]: https://github.com/crystal-lang/crystal/issues/16657
[#14773]: https://github.com/crystal-lang/crystal/issues/14773
[#16614]: https://github.com/crystal-lang/crystal/issues/16614
[#7171]: https://github.com/crystal-lang/crystal/issues/7171
[RFC 21]: https://github.com/crystal-lang/rfcs/pull/21
[#9896]: https://github.com/crystal-lang/crystal/issues/9896
