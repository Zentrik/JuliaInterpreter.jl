# Julia codegen abort in the alloc-opt pass (not a JuliaInterpreter bug)

`julia` aborts with SIGABRT while compiling a generated program. The failure is
in Julia's own LLVM allocation-optimization pass, and it happens on the
**reference** side of the differential harness — plain `Core.eval` of the
program — so JuliaInterpreter is not involved in the crash at all.

- Julia: 1.11.9, x86_64-linux-gnu
- Found by: FuzzJI native engine, seed 5000644 with the `--big` config profile
- Reproduced independently by two shards (`native` and `native-big`) with an
  identical backtrace, so it is not a one-off.

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

- `candidate.jl` — the program that was executing when the worker died,
  recovered from the crash-safe journal. 69 lines, not yet minimized.
- `backtrace.txt` — the raw crash output.

## Reproducing

```sh
julia --project=fuzz -e '
  m = Module(:CrashCase)
  for st in Meta.parseall(read("candidate.jl", String)).args
      st isa LineNumberNode && continue
      Core.eval(m, st)
  end'
```

Note `candidate.jl` calls `__obs__`, the harness's observation hook. Either
define `__obs__(x) = nothing` in the module first or delete those lines —
minimization will remove them anyway, since they are not what crashes.

The whole program is also regenerable from its seed, which is the more robust
reproducer while the file is still large:

```sh
julia --project=fuzz fuzz/run.jl --engine native --n 1 --seed 5000644 --big
```

## Minimizing

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
