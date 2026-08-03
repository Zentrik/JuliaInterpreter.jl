# Transient GC segfault — a Julia bug, not a JuliaInterpreter bug

**Status: root-caused to an upstream Julia 1.12 codegen/runtime
memory-safety bug — same class as
[#62524](https://github.com/JuliaLang/julia/issues/62524) (GC root lost
across a safepoint), but NOT confined to `-O2`: it reproduces at `-O1`
(the vulnerable compiled code ships in the -O2-built sysimage).** Core
dumps on the official binary show wild unaligned writes of the
harness's 7-byte probe string into live `Tuple{...}` DataTypes — see
`ANALYSIS.md` (investigation, two corrected verdicts, confirmation
runs) and `core-forensics.md`. A pinned JuliaInterpreter v0.11.4
campaign crashes identically: not an interpreter bug. `-O1` is a rate
reducer only (roughly minutes → hours between deaths); campaigns must
keep the restart loop. Upstream next step: comment on #62524 with both
cores' forensics. The document below is the original triage, kept as
written; its upstream attribution stands, though its cumulative-heap
framing and its #59483/LICM hypothesis are superseded.

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

## Relation to known upstream issues (searched 2026-08-03)

The prominent Julia 1.12 GC-corruption regression is **#59483** ("GC error on
Julia 1.12", label `regression 1.12`) with **#60622** split out from it. Root
cause, per fix **PR #60651** (merged 2026-01-16): codegen emitted a GC root for
`value_to_pointer` that LLVM's **LICM** could hoist into existence holding an
**undef** value, which the collector then tried to mark — a garbage pointer in
the root set. Fixed by conservatively zero-initializing GC pointers; backported
to the 1.12 release branch (in the 1.12.5 backport batch, #60612).

**This is almost certainly NOT our bug**, for three independent reasons:

1. **The fix is already in our binary.** We crash on **1.12.6**, commit
   `15346901f00`, built **2026-04-09** — ~3 months after #60651 merged and was
   backported. So the uninitialized-root fix is present, yet we still crash.
2. **#59483/#60622 are a *parallel*-collector bug.** Their signature is the
   assertion `gc_check_ptls_of_parallel_collector_thread` /
   `JL_GC_PARALLEL_COLLECTOR_THREAD`, which only fires with ≥2 GC threads. This
   environment runs **1 GC thread** (`Threads.ngcthreads() == 1`, the default on
   4 vcores), and our crashes are plain `SIGSEGV` in `gc_mark_loop_serial_` /
   the allocator — **serial** marking, not the parallel assertion.
3. **No open issue matches.** A search for open 1.12/1.13 GC-corruption issues
   turned up only unrelated reports (pkgimage/JLL load segfaults, #59219).

So our crash is either a **distinct, still-unreported serial-GC corruption** on
1.12.6, or a **residual of the same bad-root class #60651 addressed** that its
fix did not fully cover. Both are worth reporting, and the distinguishing facts
above (serial GC, post-#60651 build, cumulative/heap-state-dependent) are what
tell a triager it is not a duplicate of #59483.

Caveats kept honest: the search was not exhaustive; we have no minimal repro yet
so the mechanism is unconfirmed; and a residual-of-#59483 root cause cannot be
ruled out without a debug+asserts build (`GC_ASSERT_PARENT_VALIDITY`, as used in
#59483 to print the corrupt parent/child object types — the single most useful
next diagnostic, and runnable here without `rr`).

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
