# Throughput: measurement and the one change it justified (NEXT.md item 8)

Measured 2026-08-03 on Julia 1.12.6, 4 shared cores with other Julia work
running concurrently — absolute numbers are indicative; the relative
comparisons are the point. All campaign timings: `fuzz/run.jl` with `--nosync
--noshrink --fresh --journaldir fuzz/journal-bench`.

Two rate bases, because the axes expose different measurements:

- *wall-derived*: wall clock minus a measured ~32 s startup/compile baseline
  (`--engine native --n 1`), for the native axis (no in-campaign progress line
  at n=100);
- *in-campaign*: the campaign's own cumulative `rate_per_s` at a fixed case
  index, for step/call/split (their startup differs from the native probe's,
  so subtracting it misleads — the split run finished in less wall time than
  the native startup probe took). In-campaign rates include the first cases'
  in-process compile, so they understate steady state, but are consistent
  before/after.

## Before → after

| axis | basis | before cases/s | after cases/s | speedup |
|---|---|---|---|---|
| native `--modes both` (n=100) | wall-derived | 1.45 | **2.43** | **1.68x** |
| native `--modes cmp` (n=50) | wall-derived | 1.52 | 2.52 | 1.66x |
| native `--modes rec` (n=50) | wall-derived | 1.59 | 2.72 | 1.71x |
| step (n=60) | in-campaign @ i=50 | 1.68 | 1.89 | 1.13x |
| call (n=60) | in-campaign @ i=50 | 1.21 | 1.61 | 1.33x |
| split (n=300) | in-campaign @ i=300 | 13.1 | 24.5 | 1.86x |

Every campaign's stats are identical before and after — native-both 28
agreed / 72 aborted, rec 13/37, cmp 50/0, step 60 agreed, call 59 agreed plus
the same one known-bug re-report (`--fresh` re-derives
`call-call_value_divergence-700181ab`; deleted after the run), split 300
agreed — same seeds, same classifications, which is the behavioral-equivalence
check running at benchmark scale.

## Per-candidate profile of the native axis (50 candidates, warm process)

NEXT.md item 8 named three suspects: three fresh modules per candidate with
SETUP re-eval'd (and `__fjnorm__`/`__obs__` re-JIT'd per module), double
lowering (parsegate lowers, then `Core.eval`/`ExprSplitter` lower again), and
the reference JIT-compiling every generated function. Measured (scratch
script, not committed):

| stage | before ms/case | share | after ms/case |
|---|---|---|---|
| genprogram+render | 106 | 15% | 119 |
| parsegate (per-stmt `Meta.lower`) | 10 | 1.4% | 10 |
| freshmodule (SETUP eval) | 7 | 1.0% | 0.9 |
| first `__obs__` call (SETUP JIT) | 11 | 1.6% | 0.0 |
| run_ref | 277 | 39% | 159 |
| run_interp rec | 92 | 13% | 87 |
| run_interp cmp | 203 | 29% | 56 |
| **total** | **707** | | **432** |

The dominant costs sat inside `run_ref` and `run_interp(:cmp)` — the two
engines that execute natively — and a large share of both turned out to be the
first suspect wearing a deeper disguise: not just the ~18 ms/module visible
SETUP eval+JIT, but the per-module `__fjnorm__` **re-specializing on every
program-defined struct type it observed**. Every candidate defines fresh
types and every module defined a fresh `__fjnorm__`, so type inference +
codegen for the normalizer ran per candidate per module, forever cold. (The
`first __obs__` row only captures the entry-point compile; the
per-observed-type specializations were hiding inside the run_ref/run_interp
rows.)

## The change (fuzz/src/execute.jl)

`freshmodule()` no longer evaluates SETUP_SRC into each module. The helpers
are defined once in FuzzJI as callable structs (`FJNorm`/`FJObs`/`FJVTime`,
subtypes of `Function`) parameterized by the module's observation vector,
clock Ref, and name prefix — `string(m, ".")` computed at module-creation
time is exactly the `string(@__MODULE__, ".")` SETUP_SRC's `__fjnorm__`
strips. Each fresh module gets `const` bindings of *instances* under the same
names (`__OBS__`, `__VTIME__`, `__vtime__`, `__fjnorm__`, `__obs__`, plus
`using Random`). `fjnorm(@nospecialize(x), prefix)` compiles once per session
instead of once per observed type per module.

SETUP_SRC itself is unchanged and remains the specification: `ji.jl` still
evaluates it verbatim in the `--compile=min` subprocess, and `reprolib.jl`'s
REPRO_SETUP mirror is untouched (repro speed does not matter; behavior
matches). A new selftest testset ("freshmodule prelude matches SETUP_SRC",
+25 assertions, selftest now 431) builds a module by evaluating SETUP_SRC
verbatim and asserts helper-by-helper equivalence against `freshmodule()`:
every `__fjnorm__` branch, `__obs__` push-and-return, `__vtime__`
monotonicity backed by `__VTIME__`, the module-prefix strip on
program-defined types, `isa Function`, and `Xoshiro` resolution.

The win flows to every axis — all six use `freshmodule()` (three modules per
candidate on the native axis with `--modes both`, one or two elsewhere; the
split axis benefits most in relative terms because its per-case work is
small).

## Measured but deliberately not changed

- **Double lowering (parsegate).** 10 ms/case, 1.4% of baseline — not worth
  touching. Reusing parsegate's lowered output would also change semantics
  subtly: the gate lowers with `Meta.lower(Main, st)` (macro expansion in
  Main's context), while both engines expand in the fresh module at
  eval/Frame-construction time. Passing pre-lowered code into
  `Core.eval`/`Frame` would move macro expansion to a different module and a
  different world, and `ExprSplitter`'s fragment-at-a-time lowering is part of
  the surface under test. Documented instead of landed.
- **Reference JIT of generated functions.** The remaining bulk of `run_ref`
  (159 ms/case) and part of cmp. Inherent to the oracle: the reference *is*
  compiled Julia, and each candidate's functions are fresh methods in a fresh
  module. Nothing to share without weakening the per-candidate isolation
  guarantee (module reuse would let one candidate's state leak into the next).
- **genprogram+render (~107-119 ms/case over a 50-candidate process).** Real,
  but a statistical profile attributes a large slice to one-time inference of
  the generator's own highly polymorphic code plus small per-draw
  comprehensions (`fnsreturning` etc.); it amortizes over a long campaign,
  and restructuring the generator risks perturbing the choice-sequence/seed
  reproducibility contract for marginal payoff.
- **The interpreted side's abort budget.** 72% of native-both candidates
  exhaust the 300k-statement budget (`aborted`), so `run_interp(:rec)` spends
  its 87 ms/case mostly on legitimately long-running candidates. That is a
  campaign-default question (out of scope here), not an implementation
  inefficiency.
- **Journal writes** are load-bearing crash evidence and were not touched
  (`--nosync` already exists for the fsync).
