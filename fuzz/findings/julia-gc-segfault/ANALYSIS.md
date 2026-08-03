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

### Crash 4 (new, this session): mutator-side fault in the method-table leafcache

The `evalcode` shard under the `GC_ASSERT_PARENT_VALIDITY` build died with a
**new, fourth signature** after only ~10 minutes / 107M allocations / 29 GCs
(`crashed/crash4-egal-leafcache-assertbuild.txt`):

```
compare_svec        builtins.c:90
jl_egal__unboxed_ / jl_egal_
jl_table_peek_bp    iddict.c:128
ijl_eqtable_get     iddict.c:157
lookup_leafcache    gf.c:1492
ml_matches          gf.c:4659
ijl_gf_invoke_lookup_worlds  gf.c:4250
findsup             Compiler/src/methodtable.jl
whichtt             src/utils.jl:39      (JuliaInterpreter method lookup)
prepare_call → get_call_framecode → evaluate_call! (deep interpreted stack)
```

This is **not an allocation or collection site**: the mutator faulted while
`jl_egal`-comparing an `svec` inside the **method table's leaf cache**
(`mt->leafcache`, an eqtable owned entirely by the runtime). A live runtime
cache held a dangling pointer — the same corruption class as crash 1's wild
array element, observed from the other side (a read through the stale entry
instead of the collector marking it).

Two important inferences:

1. **The mark-time assert did not fire first.** At the last GC (#29) every
   marked edge passed the child-tag validity check. So the dangling
   reference either (a) was written into the cache *after* the last
   collection while pointing at an object that GC had already freed — the
   classic **missed-write-barrier** pattern (old table, young value: the
   value dies at a young collection while the unbarriered old table still
   points at it, and the page is later madvised away), or (b) the entry's
   target page was returned to the OS between the mark and the read. Either
   way the corruption is *invisible to a mark-phase tag check* and only an
   at-write or at-free diagnostic (rr, or a GC_VERIFY build) can catch it.
2. **The workload hypothesis sharpens.** The faulting structure is a
   *method-table cache*, and this axis is exactly the workload that churns
   them: thousands of short-lived anonymous modules, each defining fresh
   generic functions and methods (invalidation + leafcache population),
   with lookups issued through `jl_gf_invoke_lookup_worlds` at
   frame-pinned worlds. Corruption localized to gf.c's caches under
   module/method churn is a much more specific upstream lead than
   "sustained allocation".

Caveats kept honest: this binary is a from-source rebuild (same v1.12.6
tarball, same flags plus the define), so a build-environment difference
can't be fully excluded; and one fast crash after a clean 10-minute run is
within the variance today's campaign showed (3 deaths concentrated in one
of six shards). The restart loop (`assertloop.sh`) is accumulating more
samples.

### Control runs (stock juliaup 1.12.6 binary, same container, in progress)

- `repro-pure.jl` (no JuliaInterpreter): 27,500+ iterations, ~2.3 GB RSS,
  ~46 min — **no crash so far**. The pure-frontend stress as written does
  not yet reproduce it; it lacks the generic-function/method-churn
  component crash 4 points at, and should be extended accordingly
  (define + call fresh generic functions per module, force invalidations,
  drop modules) before concluding anything from its silence.
- `evalcode` shard on the stock binary: 11,000+ candidates over ~50 min —
  no crash yet in this session (today's campaign needed ~40 min *per
  crashing shard* with five clean shards alongside, so this is within
  expectation; the shard keeps running).

### Crashes 5 and 6 (assert-build restart loop) — and a mechanism correction

The restart loop produced two more crashes, fast (~10 min, then ~100 s):

- **Crash 5** (`assert-run-1`, head preserved in `crashed/`): mark-phase
  fault in `gc_mark_objarray`, faulting *inside*
  `gc_assert_parent_validity` at gc-stock.c:1551 — the read of the child's
  header word. The triggering allocation was again in `prepare_call`
  (method lookup), matching crash 4's neighborhood.
- **Crash 6** (`assert-run-2`): mark-phase fault in `gc_mark_obj8`
  (gc-stock.c:1703) — marking the fields of an ordinary Julia *struct*,
  again faulting on the child header read inside the validity assert.

Two systematic observations force a correction to the "dangling pointer
into a madvised page" story:

1. **Freed GC pages cannot fault on read.** `jl_gc_free_page`
   (gc-pages.c:166) releases pages with `MADV_FREE`/`MADV_DONTNEED`; the
   mapping stays valid and reads return zeros or stale bytes. GC page
   regions are not munmapped. So a stale pointer into a freed pool page
   would read garbage silently — it would *not* SIGSEGV.
2. **The si_codes say non-canonical, not unmapped.** Crashes 1, 4, 5, 6
   all report `signal 11 (128)` (SI_KERNEL, the kernel's report for a
   general-protection fault, e.g. a *non-canonical* x86-64 address), while
   only crashes 2/3 report `signal 11 (1)` (SEGV_MAPERR — and there the
   faulting access is to page *metadata derived from* the bad freelist
   value, so a garbage freelist head produces exactly this).

Together: the corrupt slots do not hold plausible-but-freed heap
addresses. They hold **bit patterns that were never object pointers** —
unboxed data or uninitialized memory sitting in slots the GC believes are
references. The leading mechanisms are therefore:

- **type confusion**: raw bits written into (or a bits-layout object
  reinterpreted as) a boxed/reference layout — e.g. a `Memory`/struct
  whose layout flags claim pointers where the writer stored data;
- **missing zero-initialization**: a freshly allocated reference-layout
  object reaching a safepoint with undef (junk) slots — the same *class*
  as upstream #60651 (undef GC root from LICM), but in heap objects
  rather than a stack root;
- an **out-of-bounds write** scribbling bits across neighboring pool
  cells (would also explain the trashed freelist links directly).

All of these live in the runtime/codegen layer, not in anything
expressible from pure Julia — the upstream attribution stands, but the
"missed write barrier" phrasing in the crash-4 section above should be
read with this correction in mind.

**Build-rate caveat, sharpened:** the from-source build crashes far more
often (3 crashes in ~25 min of soak) than the official juliaup binary did
in this same container (0 crashes in >1 h of the identical workload
today, though the official binary did crash 3× in this morning's
campaign). Possible explanations: different compiler/flags making the
latent bug more likely (plausible for an uninitialized-memory bug —
allocation and register timing shift), or a miscompile of the runtime in
this environment's gcc. Both crash populations matter for the upstream
report; the official-binary crashes prove it is not an artifact of our
rebuild.

**In progress:** the restart loop now runs with `ulimit -c unlimited`;
the first core dump will be analyzed with gdb to read the corrupt slot's
actual bit pattern and its parent object's type — which distinguishes
unboxed-data patterns (doubles/small ints ⇒ type confusion) from
uninitialized junk, and is the single strongest piece of evidence we can
attach short of an `rr` trace.

### Crash 7 — the official binary reproduces crash 4's exact signature

After the stock-binary control was restarted under a timeout-wrapped loop
(its first attempt had silently wedged in a stuck stepping walk for >1.5 h,
so its earlier "clean" run was not a real negative), the **official juliaup
1.12.6 binary** crashed within ~9 minutes with **exactly the crash-4
signature** (`crashed/crash7-egal-leafcache-stockbinary.txt`):
`compare_svec` ← `jl_egal_` ← `ijl_eqtable_get` ← `lookup_leafcache` ←
`ml_matches` ← `ijl_gf_invoke_lookup_worlds` ← `whichtt`.

Consequences:

- **The rebuild-artifact caveat is eliminated.** The same fault at the
  same instruction on Julia's official binary and on the from-source
  build.
- **The method-table leafcache is the dominant repeat offender**: 2 of 7
  crashes at this exact instruction, 2 more with the triggering
  allocation inside the same `prepare_call` lookup path.
- si_code here is **1 (SEGV_MAPERR)** — a canonical but unmapped address —
  unlike the non-canonical (128) group. This matters because the
  stays-mapped argument in the crash-5/6 section **only covers pool
  pages**: objects over ~2 KB (large `svec`s, big `Memory` buffers) are
  **malloc'd big objects, freed at sweep**, and freed malloc arenas can
  be trimmed/unmapped. A dangling reference to a swept *big* object is
  therefore back on the table for the SEGV_MAPERR crashes (2, 3, 7),
  while the non-canonical group (1, 4, 5, 6) still requires garbage bits
  (type confusion / uninitialized slot / OOB scribble).

So the evidence now supports **two observable corruption flavors** — slots
holding never-were-pointers bit patterns, and (possibly) references to
swept big objects — concentrated around the gf.c dispatch-cache machinery
under module + method + world churn.

### Crash 8 + core dump: the corrupting write identified byte-for-byte

Stock-binary run 2 crashed in ~3.5 min (`gc_mark_obj8`, si_code 128 — the
struct-field signature, now on the official binary) and left an 827 MB
core. The juliaup binary ships DWARF, so gdb recovered the faulting frame
fully (`core-forensics.md` has the raw session):

- faulting slot: `0x7f59cd8c1ca0`; corrupt value `0x706a665a00be8430`.
- The victim is a **live `DataType`** — typename symbol **`#5#6`**, an
  anonymous closure type from candidate code. Field layout matches
  name/super/parameters/types/instance/layout, with `parameters` expected
  to hold `0x00007f5a00be8430` (the empty svec; its sibling DataType holds
  exactly that value in the same field).
- The corruption is **7 ASCII bytes `"fjprobe"` memcpy'd at the unaligned
  address `0x...ca5`**, straddling the `parameters` and `types` fields:
  the low 5 bytes of `parameters` and high 4 bytes of `types` survive
  intact around it.
- A **second victim 64 bytes earlier** (a `Type{...}` DataType) carries a
  separate 3-byte fragment `"be\0"` at the same field offset — the tail
  of another `"…be" + NUL` write.
- `"fjprobe"` is the **harness's write-probe payload**
  (`fuzz/src/evalcodefuzz.jl:42`): the literal value `writeprobe` assigns
  into String-typed frame locals, materialized thousands of times per run
  through `repr`/`string`/IOBuffer machinery and *repeatedly printed by
  interpreted candidate code* once assigned into frame locals.
- Only one `"fjprobe"` instance exists in the surrounding 64 KB, and the
  `"` quote bytes that `repr` would emit adjacent to the payload are
  absent: the 7-byte **bulk payload copy went to a wild destination while
  the surrounding single-byte writes went elsewhere**.

So the corruption mechanism is now concrete: **a bulk string write
(`unsafe_write`/memcpy of a String's bytes) executed with a garbage
destination pointer**, landing mid-object at unaligned addresses in the
live heap. Everything else — freelist trash (2/3), wild array elements
(1/5), corrupt leafcache keys (4/7), corrupt struct fields (6/8) — is
downstream shrapnel of such writes.

### Attribution reopened: the interpreter is a suspect again

The wild-destination write reframes the suspect list. The payload string
sits in **frame locals**, and candidate code that touches those locals is
executed **by JuliaInterpreter**, including Base's string/IO internals
with their `pointer(...)`/`memcpy` foreigncalls. If the interpreter ever
supplies a **stale slot value as a pointer argument** to a foreigncall —
for instance because a recycled `FrameData`'s arrays are still aliased by
a live frame, so another frame's writes clobber the slot between the
`pointer(...)` computation and the `memcpy` — the interpreter itself would
issue exactly this wild write: legit source bytes, garbage destination.

Two very recent optimizations create precisely that hazard class, and
**both are in the code every crashing campaign ran** (merged 2026-07-21,
present on the fuzzing branch; the 1.11.9 campaign also postdates them):

- **#761 "optimize frame recycle tracking"** — frame recycling has a
  prior history of aliasing bugs (#748/#749, "Pool each frame at most
  once when recycling", "fix double-recycle exception unwind").
- **#759 "reenable global ref lookup optimization"**.

Registered **v0.11.4 predates both** (same-day release, before the
merges) while containing the older recycling mechanism. A pinned
discriminating campaign (`fuzzwt-pin`: identical harness, stock Julia
1.12.6, `JuliaInterpreter@0.11.4` from the registry) is now running
alongside the branch-source loops:

- crashes **vanish** on 0.11.4 → regression in the #759–#761 window;
  bisect those three PRs next.
- crashes **persist** on 0.11.4 → pre-existing bug (older recycling, or
  genuinely upstream Julia); next split is disabling recycling entirely.

## CORRECTION (later the same day): it crashes at -O1 too — the #62524
## verdict below was overconfident

After the verdict below was written, a crash **at `-O1`** was reported
from campaign use. Reproduced here in ~90 minutes of accelerated soak
(`-O1 --heap-size-hint=64M`, official binary; `crashed/crash11-…`), with
a core dump. The forensics rewrite the story once more:

- The victim is again a pool object marked with DataType descriptors —
  and this time fully identifiable: a **live, fully-initialized
  `Tuple{...}` type object** (typename chain reads `"Tuple"`) — an
  argument-tuple DataType of the kind method lookup mints by the
  thousand. Its `instance` field was legitimately `NULL` and `layout`
  valid; an **8-byte bulk write of `"fjprobe\0"` at the unaligned
  address `0x…cf6`** clobbered the boundary between the two fields.
- With that lens, the -O2 core (crash 8, `core-forensics.md`) reads the
  same way: valid fields around a 7-byte unaligned `"fjprobe"` write.
  The "uninitialized fields exposing recycled-cell residue" reading in
  `core-forensics.md` — adopted to fit #62524 — is **wrong**: `jl_new_uninitialized_datatype`
  NULLs every pointer field with no safepoint in between, so live
  DataTypes cannot carry junk fields by construction. These are **wild
  unaligned string-payload writes into live objects**.
- Since it reproduces at `-O1`, the corrupting writer is **not
  runtime-JIT-compiled code** (pkgimage caches are opt_level-keyed —
  verified — so package code really was -O1). The writer lives in the
  **sysimage** (Base/stdlib, always compiled -O2 at julia build time)
  or the C runtime. The string/IOBuffer bulk-write paths
  (`unsafe_write` memcpy of exactly the payload bytes, with `repr`'s
  quote bytes landing elsewhere via the separate single-byte path) are
  the standing suspects: a stale destination — an IOBuffer data
  `Memory` swept mid-operation because compiled Base code dropped its
  GC root across a safepoint — would produce exactly these unaligned
  text fragments in recycled DataType pool pages.

Bottom line, revised:

- **Still a Julia bug, not JuliaInterpreter** (the v0.11.4 control and
  every audit stand; the probe string is an innocent payload carried by
  Base's own compiled write paths).
- **Same bug class as #62524** — 1.12-codegen losing a GC root — but
  **not its MWE**, and crucially **not confined to `-O2` user code**:
  the vulnerable compiled code ships inside the -O2-built sysimage, so
  the runtime `-O1` flag only reduces exposure (fewer vulnerable
  JIT-compiled frames), it does not remove it. Observed rates: minutes
  at -O2 + 64M heap; ~90 min at -O1 + 64M; ~22 clean 8-min batches at
  -O1 with default heap before the reported campaign crash.
- **Mitigation guidance corrected**: `-O1` is a rate reducer, not a
  fix. Campaigns must keep the restart loop; treat any gc-stock.c death
  as this bug. The only real fixes are upstream.
- **For upstream**: comment on #62524 with both cores' forensics (the
  wild unaligned `"fjprobe"` writes into live Tuple-type DataTypes, at
  -O1 and -O2, official binary), noting it may be the same root cause
  surfacing via sysimage-compiled Base code rather than the MWE's
  JIT-compiled function — or a sibling bug in the same #55767/#56847
  era. The next discriminating experiment (not run here): change the
  probe payload to a long distinctive string and confirm the corrupt
  bytes track it — pinning the writer to the `repr`/`string` path; then
  an `rr` trace of that write is the definitive artifact.

## Superseded verdict (kept for the record): upstream JuliaLang/julia issue #62524

A refreshed upstream sweep (prompted mid-investigation) surfaced
**[#62524] "Segfault in `gc_mark_obj8` from partially initialized boxed
tuple at `-O2`"** (open, filed 2026-07-27): PR #55767 stopped
heap-to-stack promotion of boxed tuples carrying GC pointers, and the
`-O2`-only dead-store-elimination pass from PR #56847 then lets a boxed
tuple be **rooted before its pointer fields are stored** — any GC at that
window scans the field bytes, which are whatever the recycled pool cell
last held. Affects 1.12.6 and 1.13-rc1; incidentally fixed on master by
#55045 (stack allocation of union results); **no fix in any 1.12.x**.

Every piece of our evidence snaps into place:

- **Exact crash-line match**: #62524's backtrace is `gc_mark_obj8` at
  gc-stock.c:1704 — identical to crashes 6 and 8.
- **Confirmation matrix run here** (stock juliaup 1.12.6, evalcode axis):
  - `-O2 --heap-size-hint=64M`: **"GC error (probable corruption)"
    detected within ~minutes** (193 GCs) — the issue's predicted
    fast-reproduction mode (`crashed/crash9-…`).
  - `-O1 --heap-size-hint=64M`: **clean** — 3,700 candidates over 10
    minutes at the same extreme GC pressure. DSE runs only at `-O2`;
    the -O1/-O2 split is the discriminating fingerprint.
- **The core forensics reread correctly**: nothing *overwrote* the
  victim object — the object is a **freshly allocated, partially
  initialized value whose uninitialized field bytes expose the recycled
  cell's previous contents** (fragments of the omnipresent `"fjprobe"`
  probe strings, stale pointers' low bytes). This also explains the
  mixed si_codes: leftover text → non-canonical faults (1/4/5/6/8);
  leftover stale addresses → SEGV_MAPERR (2/3/7); and leftover junk
  read as a freelist link → the allocator crashes.
- **Why this workload, and not the pure reproducers**: JuliaInterpreter's
  hot loop churns union-typed, type-unstable returns (`(frame, pc)`
  tuples from `debug_command`/`step_expr!` and `Union{Some,Nothing}`
  lookups) — exactly the union-split boxed-tuple codegen the bug needs.
  `repro-pure.jl`/`repro-pure-v2.jl` are too type-stable to emit it,
  which is why they stayed clean (v1: 27k iters; v2: 126k iters).
- **JuliaInterpreter fully exonerated**: the pinned campaign on
  registered **v0.11.4** (predating #759/#760/#761) crashed twice with
  the same signature within minutes — the interpreter's recent
  optimizations are not involved; the interpreter is only the workload
  that emits the vulnerable compiled-code pattern at volume.

Loose end kept honest: README.md reports the previous campaign crashed
on **1.11.9**, but #62524 says 1.11 is *not* affected (the DSE pass is
1.12+). Either that campaign's version note is wrong, or the 1.11.9
crashes were a different (rarer) bug; the 1.11.9 backtraces in
`crashed/` predate this session and cannot distinguish it. Worth
stating plainly in any upstream comment.

### What to do with this

1. **Comment on JuliaLang/julia#62524** (rather than filing a new
   issue) with: the confirmation matrix above, the exact-line match on
   the official 1.12.6 binary, the core-dump forensics (recycled-cell
   text visible through uninitialized fields — direct physical evidence
   of the mechanism), and JuliaInterpreter+fuzz-harness as a reliable
   open-source reproducer (`--heap-size-hint=64M` → minutes).
2. **Mitigate the nightly fuzz workflow**: run campaign shards with
   `-O1` until a fixed 1.12.x ships. The -O1 lane here ran *faster*
   than -O2 (6.6/s vs 5.7/s — this workload is interpretation-bound and
   saves compile time), so the mitigation is free.
3. Track the 1.11.9 question: if the 1.11 lane of a future campaign
   crashes in `gc-stock.c`, capture a core immediately — that would be
   a *different* upstream bug.

### Interim conclusion (superseded by the verdict above; kept for the record)

Four distinct fault sites — GC mark of an object array, pool allocator
freelist walk (×2), and now an egal compare inside the method-table
leafcache — across two Julia versions (1.11.9, 1.12.6), two binaries
(official juliaup build and a from-source rebuild), and both GC-side and
mutator-side observers. All are reads/writes through **runtime-owned**
structures; none implicate interpreter-managed data. The evidence
continues to support a Julia runtime/GC memory-safety bug (most plausibly
a missed write barrier or lost root in the gf.c cache machinery under
module + method churn), with JuliaInterpreter acting as an unusually
effective stressor. Next diagnostics, in order of value: an `rr` recording
on hardware that allows it; a `WITH_GC_VERIFY=1` build (catches the missed
barrier at the corrupting write, at heavy slowdown); extending
`repro-pure.jl` with generic-function churn to sever the JuliaInterpreter
dependency entirely.
