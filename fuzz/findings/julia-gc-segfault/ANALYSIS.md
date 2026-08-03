# Follow-up investigation (2026-08-03, second session)

Independent re-investigation of the transient GC segfault documented in
`README.md`. Everything here was established on a fresh container with
juliaup Julia **1.12.6** (the same binary build the campaign crashed on:
`julia-1.12.6+0.x64.linux.gnu`), 4 cores, 1 GC thread.

## 1. What the faulting source lines actually say (new)

Mapping the three backtraces onto the `v1.12.6` source tarball
(`src/gc-stock.c`) sharpens the picture considerably:

### Crash 1 — `gc_try_claim_and_push` at gc-stock.c:1683

```c
STATIC_INLINE void gc_try_claim_and_push(jl_gc_markqueue_t *mq, void *_obj, uintptr_t *nptr)
{
    if (_obj == NULL) return;
    jl_value_t *obj = (jl_value_t *)jl_assume(_obj);
    jl_taggedvalue_t *o = jl_astaggedvalue(obj);
    if (!gc_old(o->header) && nptr)      // <-- line 1683: reads obj's header word
```

Called from `gc_mark_objarray` (line 1837), i.e. while marking the elements
of an object array (`Memory{Any}` / `svec` / `Expr.args`). The fault is the
`o->header` read: a **live, reachable object array held a non-NULL element
pointer into unmapped memory**. Not a bad root, not a bad parent — a bad
*element* inside an array the collector legitimately reached.

### Crashes 2 and 3 — `jl_gc_small_alloc_inner` at gc-stock.c:744

```c
jl_taggedvalue_t *v = p->freelist;               // 735
if (v != NULL) {
    jl_taggedvalue_t *next = v->next;            // 737
    p->freelist = next;
    if (__unlikely(gc_page_data(v) != gc_page_data(next))) {
        jl_gc_pagemeta_t *pg = jl_assume(page_metadata_unsafe(v));
        assert(pg->osize == p->osize);
        pg->nfree = 0;                           // <-- line 744: faults
```

The write to `pg->nfree` faults, meaning `page_metadata_unsafe(v)` produced
an unmapped address, meaning **`v` — the pool freelist head — was not a
pointer into any GC page**. The freelist's `next` links are stored *inside
the freed cells themselves*, so this is the canonical signature of a
**write through a dangling reference into memory that had been swept onto a
freelist**: the mutator's write lands where a `next` link lives, the
allocator later follows the trashed link, and the very next
freelist-page-boundary bookkeeping faults.

### Unified mechanism

Both signatures are downstream of the same condition: **an object the GC
freed while it was still reachable** (a lost root or a missed write
barrier, in the runtime or in codegen — not something expressible in pure
Julia code):

- writes through the stale reference trash freelist links → crashes 2/3 in
  the allocator;
- if the freed cell (or its page, once madvised/returned to the OS) is
  observed through a stale array element during the next mark →
  crash 1's wild-element fault.

This mechanism-level read strengthens the upstream attribution: pure Julia
code — which is all JuliaInterpreter and the fuzz harness are, on this axis
— cannot skip a write barrier or unroot an object. `setfield!`,
`setindex!`, `jl_new_structv`, `jl_f_intrinsic_call` and the other runtime
entry points JuliaInterpreter ccalls all apply barriers internally, and the
`Vector{Any}`-as-`Ptr{Any}` ccall pattern used at
`src/interpret.jl:557/602` and `src/builtins.jl:624` is rooted by ccall's
`cconvert` for the duration of the call. An audit of every
`ccall`/`unsafe_*` site in `src/` found no raw-pointer retention and no
object construction that bypasses the runtime.

### One correction to README.md

README.md claims crash 1 has "zero JuliaInterpreter frames". Not quite: the
stack passes through `eval_code` (`src/utils.jl:787/815`) before entering
`Core.eval` → lowering → `scm_to_julia` → the faulting allocation.
The *attribution argument is unaffected* — `eval_code` merely builds an
ordinary `Expr` tree (a `let` block of `QuoteNode`s) and hands it to
`Core.eval`; every operation is GC-managed — but the claim should be stated
as "the faulting path below `Core.eval` is pure frontend + GC, with no
interpreter code in it".

## 2. Upstream issue landscape re-checked (2026-08-03, this session)

- **#58760** ("julia-1.12-beta4 segfault ~GC") — the closest historical
  match by symptom class (stochastic GC-corruption during allocation), but
  it was in the **parallel** mark loop (`gc_mark_loop_parallel` /
  `gc_mark_and_steal`) and was fixed by PR **#58792 before 1.12.0 shipped**.
  Present in our 1.12.6 binary; our crashes are serial-mark. Not our bug.
- **#59483 / #60622 / fix #60651** — as analyzed in README.md: parallel-GC
  assertion signature, fix already in 1.12.5+; our environment runs 1 GC
  thread. Not our bug.
- No open JuliaLang/julia issue matches a serial-GC objarray-element /
  pool-freelist corruption on 1.12.x as of today.

## 3. Experiments run this session

All on the exact crashing binary (`1.12.6+0.x64.linux.gnu` via juliaup),
4-core container, `Threads.ngcthreads() == 1`.

### (a) Pure-Julia reproducer (`repro-pure.jl`) — attribution experiment

Goal: crash the GC with **no JuliaInterpreter in the process**. Result:
see "Results" below.

### (b) Harness reproduction (`evalcode` axis) — does it reproduce here at all

`julia --project=fuzz fuzz/run.jl --engine evalcode --n 100000 --nosync
--noshrink`, per README's "fastest path". Result: see "Results" below.

### (c) Julia 1.12.6 built with `-DGC_ASSERT_PARENT_VALIDITY` — the README's
"single most useful next diagnostic"

Built from the official v1.12.6 source tarball with

```
# Make.user
JCFLAGS += -DGC_ASSERT_PARENT_VALIDITY
JCXXFLAGS += -DGC_ASSERT_PARENT_VALIDITY
```

(a *release* build, deliberately — the trigger is allocation-volume-driven,
and a debug build's ~10x slowdown works against reproduction; the define
adds only a child-tag validity check per marked edge). Under this build,
`gc_assert_parent_validity` aborts with the **parent and child object
types** at the moment the collector first touches a corrupt edge — turning
the delayed wild-pointer fault into an at-corruption-time diagnosis.

## Results

(filled in as the experiments complete)
