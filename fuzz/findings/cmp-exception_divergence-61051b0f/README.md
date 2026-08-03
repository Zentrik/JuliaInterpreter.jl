# Compiled mode misses the `rethrow` / `current_exceptions` interception

Found by the `native` engine (seed 747, `--modes cmp`) while running the
campaign behind `fuzz/coverage.jl`. Triaged and minimized by hand; the
generated program is in `meta.md`.

**This is a JuliaInterpreter divergence, not a Julia bug and not a harness
artifact.** It reproduces from eight lines with no fuzzer involved.

## Minimal reproducer

```julia
using JuliaInterpreter
src = "let; try; error(\"boom\"); catch e; rethrow(); end; end"
# reference (Core.eval)            → ErrorException("boom")
# RecursiveInterpreter             → ErrorException("boom")            ✓
# NonRecursiveInterpreter (cmp)    → ErrorException("rethrow() not allowed outside a catch block")  ✗
```

`repro.jl` in this directory replays the original generated program;
`minimal.jl` runs the table below.

| in a `catch` block | reference | `rec` | `cmp` (compiled mode) |
|---|---|---|---|
| `rethrow()` | `ErrorException("boom")` | same | `ErrorException("rethrow() not allowed outside a catch block")` |
| `rethrow(exc)` | `ArgumentError("other")` | same | `ErrorException("rethrow(exc) not allowed outside a catch block")` |
| `length(current_exceptions())` | `1` | `1` | `0` |
| `!isempty(catch_backtrace())` | `true` | `false` | `false` |

The last row is a separate, *documented* limitation — the interpreter does not
record per-exception backtraces (`src/interpret.jl:370`) — and diverges in both
modes. The first three are the bug.

## Root cause

Exceptions caught by an interpreted handler never reach the task's native
exception stack; they live in `frame.framedata.exceptions`. `evaluate_call!`
therefore intercepts `Base.rethrow` and `Base.current_exceptions` and answers
them from the frame chain (`src/interpret.jl:329-395`).

That interception lives on the *generic* method:

```julia
function evaluate_call!(interp::Interpreter, frame::Frame, fargs::Vector{Any}, enter_generated::Bool)
    if fargs[1] === Core.eval
        ...
    elseif fargs[1] === Base.rethrow
```

and `NonRecursiveInterpreter` overrides exactly that method with a bypass
(`src/interpret.jl:315-317`):

```julia
function evaluate_call!(::NonRecursiveInterpreter, frame::Frame, fargs::Vector{Any}, ::Bool)
    return native_call(fargs, frame)
end
```

so in compiled mode `rethrow` is called natively, with no exception on the
task's stack, and Julia raises "not allowed outside a catch block". The
compiled-mode path also never sees the `Core.eval` special case on the same
method — worth checking while fixing.

Suggested fix: hoist the `Core.eval` / `rethrow` / `current_exceptions`
dispatch out of the recursive method (e.g. into a small
`intercept_call(interp, frame, fargs)` called by both) so both interpreters
share it. A regression test belongs next to
`test/interpret.jl:1512` ("rethrow() from a callee of a catch block"), which
covers this only for the recursive interpreter.

The interception is deliberate and was refined three times — `9409513`
("Make current_exceptions() see interpreted exception handlers"), `38fd518`
("Make rethrow() find the exception being handled in caller frames") and
`f1c7c6f` ("Match native rethrow semantics on the active-exception stack").
None of the three touched the non-recursive path, and the package's own tests
for all three call `finish_and_return!` with the default interpreter, so
nothing was in place to notice.

## Why the fuzzer had not found it before

The differential axis has run `--modes both` for a long time, so the *inputs*
were not the missing piece: `rethrow()` inside a `catch` is generated, but it
needs to be reached with the exception still in flight and with an observable
difference downstream. The coverage report produced in the same session shows
`src/interpret.jl:333-365` — the whole interception — as a cold span inside an
otherwise-hot `evaluate_call!`, which is the same fact stated statically.
