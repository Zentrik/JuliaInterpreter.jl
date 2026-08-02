# RESOLVED: a known, already-fixed Julia 1.11 regression — not a new bug

`julia` aborts with SIGABRT while compiling a generated program, in Julia's own
LLVM allocation-optimization pass. It happens on the **reference** side of the
differential harness — plain `Core.eval` — so JuliaInterpreter is not involved.

**This is [JuliaLang/julia#57190](https://github.com/JuliaLang/julia/issues/57190),
closed by PR #57208.** A regression introduced in 1.11 by PR #51720 and fixed
for 1.12. Verified here:

| Julia | `minimized.jl` | `minimized-struct.jl` | issue #57190's own repro |
|---|---|---|---|
| 1.11.9 | aborts | aborts | aborts |
| 1.12.6 | clean | clean | clean |

So the fix never reached a 1.11 patch release. The only thing arguably worth
raising upstream is whether #57208 should be backported to 1.11; nothing here
is a new defect.

- Found by: FuzzJI native engine, seed 5000644 with the `--big` config profile
- Reproduced independently by two shards (`native` and `native-big`) with an
  identical backtrace.

## The process lesson, which is the durable part

The version check should have been the *first* triage step and was instead the
last. Confirming the crash reproduces on current Julia costs one command; it
was done only after journal replay, line-level minimization, a C-Reduce run,
and a delegated reduction agent — all of which turned out to be work on a bug
fixed a release ago.

Two things follow for the harness, tracked as work items rather than fixed
here:

1. A crash on the *reference* side is a Julia bug, not an interpreter bug, and
   should be classified and routed separately instead of landing in the same
   findings bucket as a divergence.
2. Any such finding should be re-run against the newest installed Julia before
   it is reported, so "already fixed upstream" is answered automatically.

What the episode does show is that the reduction pipeline works end to end: a
69-line generated program became a 36-byte one-liner that matches the
canonical reproducer for a real, independently-confirmed compiler bug.

## Backtrace (abridged)

```
signal (6): Aborted
operator() at src/llvm-alloc-opt.cpp:797 [inlined]
moveToStack at src/llvm-alloc-opt.cpp:802
optimizeAll at src/llvm-alloc-opt.cpp:307
runOnFunction at src/llvm-alloc-opt.cpp:1292 [inlined]
...
jl_compile_method_internal at src/gf.c:2538
...
run_ref at fuzz/src/execute.jl        <- the *compiled* reference side
```

`moveToStack` is the transformation that promotes a heap allocation to a stack
slot once the pass has proved the object does not escape; the abort is an
assertion inside it.

## Files

- `minimized.jl` — 29 lines, reduced from the original 69 by `fuzz/crashmin.jl`
  in 219 subprocess runs. Reproduces standalone.
- `candidate.jl` — the original program, recovered from the crash-safe journal.
- `verify.jl` — runs a file statement by statement in a fresh module,
  swallowing ordinary exceptions, so only a process death is visible.
- `backtrace.txt` — the raw crash output.

## Reproducing

```sh
julia --startup-file=no verify.jl minimized.jl
# [pid] signal 6 (-6): Aborted
# moveToStack at src/llvm-alloc-opt.cpp:802
```

No JuliaInterpreter involved: `verify.jl` only calls `Core.eval`. It swallows
runtime exceptions on purpose — `minimized.jl` references names that
minimization deleted the definitions of, and those throw at *runtime*, whereas
the abort happens earlier, while the `let` block's thunk is being compiled.
Deleting them was legitimate for the same reason: they are not part of what
crashes.

The program is also regenerable from its seed:

```sh
julia --project=fuzz fuzz/run.jl --engine native --n 1 --seed 5000644 --big
```

## What is left in the minimized case

The surviving ingredients point at atomic fields on a stack-promotable
allocation:

- a `mutable struct` with two `@atomic` fields and one plain field,
- two instances of it constructed inside a `let`, one within a `try`,
- an `@atomic v.fld -= ...` modify on the second,
- a self-recursive `Int64` function whose calls supply the field values.

A hand-written program with just those elements — atomic struct, construction
in a `let`, `@atomic -=` inside a `try` — does *not* abort, so the trigger
needs more of the surrounding context than the shape alone suggests; the
nested recursive calls feeding the constructor arguments are likely load
bearing. Further reduction would want C-Reduce or a Julia-aware reducer
working below line granularity.

## Minimizing further

`fuzz/crashmin.jl` shrinks a program that kills the process, by running every
candidate in a subprocess and keeping any edit that still dies by signal:

```sh
julia --project=fuzz fuzz/crashmin.jl candidate.jl --out minimized.jl
```

## Why this is worth keeping despite not being an interpreter bug

The harness compiles every generated program as its reference. That makes it a
codegen fuzzer for free, on programs written to be type-unstable, heavily
nested, and full of edge-case values — which is the shape of input that
stresses escape analysis. Finding compiler bugs this way has precedent in
Julia specifically: the AFL + C-Reduce work on the Julia binary turned up a
comparable class.
