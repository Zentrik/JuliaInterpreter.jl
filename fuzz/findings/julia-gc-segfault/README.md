# Transient GC segfault — a Julia bug, not a JuliaInterpreter bug

**Status:** open, reproducible only in aggregate (heap-cumulative). Candidate
for an upstream JuliaLang/julia report. NOT a JuliaInterpreter defect — see
"Attribution" below.

## Summary

A long-running Julia process doing sustained allocation + collection dies with
`SIGSEGV` **inside the garbage collector** (`src/gc-stock.c`). It reproduces
across unrelated workloads and does **not** reproduce on isolated replay of the
candidate that was executing when it crashed — the corruption is cumulative
heap state, and the crash fires at a later GC safepoint, not at the operation
that corrupted the heap.

- **Julia versions:** confirmed on **1.11.9** (previous campaign) and
  **1.12.6** (this campaign). The sibling `llvm-alloc-opt` codegen abort was
  fixed between these; this one was **not**.
- **Frequency (1.12.6):** 3 deaths in ~25 `evalcode`/`split` batches of the
  2026-08-03 campaign (roughly one per ~40 min of one shard), 0 in the other
  five shards over the same window — consistent with a stochastic,
  allocation-volume-driven trigger rather than a specific input.

## The three crash signatures (all `gc-stock.c`)

All three faulted in the collector or the allocator that entered it. Full
backtraces in `crashed/`.

1. **`crash1-mark-during-parse.txt`** — the most diagnostic. SIGSEGV in the
   **mark phase** walking an object array:
   ```
   gc_try_claim_and_push   gc-stock.c:1683
   gc_mark_objarray        gc-stock.c:1837
   gc_mark_outrefs / gc_mark_loop_serial / _jl_gc_collect
   ...triggered by an allocation during PARSING:
   jl_exprn                builtins.c:1660     (allocating an Expr args array)
   scm_to_julia_           ast.c:642/646       (flisp AST -> Julia Expr)
   ```
   No JuliaInterpreter frames at all. The collector tripped over a corrupt
   object *array* while marking — i.e. some live `Array`/`svec`/`Expr` on the
   heap holds a bad element pointer.

2. **`crash2-alloc-in-catch_backtrace.txt`** — SIGSEGV in
   `jl_gc_small_alloc` while `catch_backtrace()`/`_reformat_bt` grew a vector
   (ordinary `push!`), inside the harness's exception path.

3. **`crash3-alloc-in-evalcode.txt`** — SIGSEGV in `jl_gc_small_alloc`
   (`ijl_gc_small_alloc`) on an ordinary allocation.

Crashes 2 and 3 are the allocator faulting directly; crash 1 is the collector
faulting while marking. Both are the same underlying condition — a corrupt
GC-managed object — surfacing at the next safepoint.

## Attribution: why this is a Julia bug

- **Crash 1 has zero JuliaInterpreter frames** — it is pure frontend
  (`scm_to_julia`, `jl_exprn`) plus the collector.
- **It spans unrelated workloads.** Across this and the prior campaign it has
  been seen in the differential comparator (`firstdiff`), the builtins prober
  soak (`gc_mark_obj8`), the `evalcode` axis, and the `split` axis. The only
  constant is sustained allocation in a long-lived process, not any one code
  path.
- **The crashing candidate always runs clean in isolation.** The most recent
  one (`crashed/batch24-124312.jl`, `evalcode` engine) ran clean across 5
  processes × 30 walk seeds. A candidate that only crashes as the Nth of a
  long sequence is heap-state-dependent by definition.

What JuliaInterpreter contributes is *volume*: `RecursiveInterpreter` allocates
heavily (a `Frame`/`FrameData` per interpreted call, walking Base), and the
axes create thousands of fresh anonymous `Module`s. That is a GC stressor, not
a memory-safety bug in the interpreter — the fuzzer's inputs are validity- and
termination-checked and never use `unsafe_*` on this axis.

## Reproducing it

### In aggregate (reliable, ~tens of minutes)

The fuzzing campaign reproduces it by construction. Fastest path:

```sh
# one long evalcode shard; expect a SIGSEGV in gc-stock.c within ~30-60 min
julia --project=fuzz fuzz/run.jl --engine evalcode --n 100000 --nosync --noshrink
# or the sharded runner, which restart-loops through each crash:
./fuzz/longrun.sh 3600 misc
```

`fuzz/journal-<shard>/current.jl` holds the candidate that was executing,
written before each run, so every crash leaves the candidate behind (moved to
`crashed/` on the next batch by `longrun.sh`).

### Standalone attempt (no JuliaInterpreter)

`repro-pure.jl` stress-tests the frontend + module + GC path the way the
workload does (many fresh modules, parse + eval of allocating code, a large
churning live set, frequent collections), with no JuliaInterpreter dependency.
If it segfaults in `gc-stock.c`, the bug is proven pure-Julia and this file is
the upstream reproducer. See its header for status/usage.

## For the upstream report

- Attach all three `crashed/*.txt` backtraces (crash 1 first — it is the
  cleanest, frontend-only, and shows the mark-phase objarray fault).
- State both affected versions (1.11.9 and 1.12.6) and that the
  `llvm-alloc-opt` sibling was fixed in between.
- Note it is not input-specific: candidates run clean in isolation; the
  trigger is cumulative allocation.
- An `rr` recording (`julia --bug-report=rr …`) is the ideal next artifact —
  it was not capturable here (`rr` unavailable; `perf_event_paranoid=2`). On a
  machine with `rr`, wrap the aggregate reproducer above.
