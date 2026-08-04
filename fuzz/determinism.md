# Determinism: what the oracle actually requires, and how to widen the grammar without a hypervisor

Status: analysis, 2026-08-02. Companion to `DESIGN.md` and `yield-analysis.md`.

The question under exploration: the differential oracle requires deterministic
programs, and that requirement is why the grammar excludes I/O, `rand`, time,
tasks/threads, `objectid`, `ccall`, pointers, and why the corpus axis demotes
real code to a failure-mode-only oracle (`corpus.jl` header). Can we achieve
determinism for *more* kinds of code — possibly with deterministic-execution
infrastructure like Antithesis's hypervisor, Hermit, or rr?

## TL;DR

1. "Nondeterminism" here is three different phenomena conflated —
   environmental nondeterminism, semantic underspecification, and
   cross-engine incidental divergence. Separating them shows that most of
   the excluded grammar is blocked by the second and third, and **those are
   exactly the classes a deterministic hypervisor cannot touch**.
2. A deterministic hypervisor makes *one execution of one program*
   bit-reproducible. Our oracle needs *two different executions* — native
   code and the interpreter, different instruction streams by construction —
   to **agree**. Under a perfect hypervisor both runs become reproducible
   *and still different*: different allocation patterns → different
   addresses/`objectid`s, different instruction counts → different
   interleavings, shared process counters consumed at different rates.
   Determinism ≠ agreement. It removes approximately zero current grammar
   exclusions.
3. What does widen the tested surface, in cost order:
   - a **confirm-on-divergence gate** (rerun both sides before reporting;
     unstable divergence → tracked discard) — makes every other item safe;
   - **seeded/explicit RNG** and **content-keyed `Dict`/`Set`** — comparable
     today with zero new infrastructure;
   - a **self-agreement gate for the corpus axis** (run the compiled
     reference twice; if it agrees with itself, the fragment has measured
     observational determinism and gets the full value oracle) — this is the
     single biggest "test more real code" unlock;
   - **virtual doubles** for time/ENV/files in `SETUP_SRC` — the hypervisor
     idea applied at the API boundary, ~50 lines, unlocks the
     handle/`do`-block/`try-finally` idioms;
   - a **determinism taint bit** in `TySum` + relation-projected
     observations — makes `objectid`/pointer/gensym *semantics* testable
     even though their values never compare;
   - a **schedule-invariant-by-construction** task subset — sound without
     any determinization, because the observables don't depend on the
     schedule.
4. Where deterministic-execution tooling genuinely pays here: **rr for
   reproducing crashy findings** (Julia ships first-class support,
   `julia --bug-report=rr`), and possibly, much later, schedule
   *exploration* against the interpreter's own concurrent state with a
   crash/invariant oracle — a different campaign than the differential one.

## 1. Three things "nondeterminism" means here

**Class E — environmental.** RNG seeding, wall/monotonic time, `ENV`,
address-space layout, I/O contents, OS scheduling. Property: controllable —
fix it, virtualize it, or record/replay it. This is the *only* class that
deterministic hypervisors address, and the harness already controls its
cheap 90% by design: both sides run in the same process (same libm, same CPU
features, same content-hash seeds, same Julia build), the grammar has no real
I/O, generation is a pure function of a seed, and the journal makes crashes
reproducible. The residual class-E gaps are *inside the grammar* — `rand`
and time are excluded rather than virtualized — and §3 closes them at the
API level.

**Class U — semantic underspecification.** The language contract permits
several behaviors and the two engines may deterministically pick different
ones. Already hit and closed during shakedown (`DESIGN.md`, known
false-positive classes): NaN payload bits under `===`, `min(NaN, NaN)`
identity, out-of-range `unsafe_trunc` (LLVM poison vs. runtime intrinsic).
Still ahead if the grammar grows float math calls: the `muladd`/fma
contraction license and `@simd`/`@fastmath` reassociation — compiled code
may fuse or reorder where the interpreted runtime intrinsic does not (or
vice versa; the point is the contract lets them differ). Property: **both
runs are perfectly deterministic and legally different.** No environment
control helps. The only handles are exclusion, normalization, or comparison
modulo the spec's equivalence relation (e.g. `isequal` already treats all
NaNs as one class).

**Class X — cross-engine incidental divergence.** Values that are
deterministic *per engine* but derived from engine implementation detail:
`objectid` of mutable objects (address-derived; the two sides allocate
differently), raw pointers, `gensym` names (a shared process counter that
the two sequential runs consume at different offsets), iteration order of
`Dict`s keyed by mutable objects, task interleavings (any scheduler —
including a deterministic one — is a function of the instruction stream, and
the streams differ by construction). Property: **a deterministic environment
makes each side reproducible without making them equal.** The handles are
abstraction (observe relations, not values — §5), taint (§5), or dynamic
discard (§6).

Classifying the current exclusion list (`DESIGN.md` "Sources of legitimate
divergence"):

| exclusion | class | actual blocker | unlock |
|---|---|---|---|
| `rand` | E | none — seeding suffices | §3, trivial |
| timing | E | grammar calls real clocks | virtual clock, §3 |
| I/O, files, ENV | E | safety, not determinism | API doubles, §3 |
| `ccall`/pointers | E + X | pointer *values*; call safety | curated calls §3, taint §5 |
| `objectid` | X | address-derived values | relations, §5 |
| tasks/threads | X (+E for real parallelism) | interleavings | invariance, §7 |
| `eval`/`include`, method redefinition | — | world-age complexity, **not determinism** | already roadmap P4 |
| `===` on floats, `unsafe_trunc`, fastmath | U | the spec itself | stays excluded/normalized |

The load-bearing observation: the grammar-narrowing exclusions are mostly E
(virtualizable in-process for free) and X (needs abstraction, which no
hypervisor provides). U is untouchable by any infrastructure, ours or
Antithesis's.

## 2. Why a deterministic hypervisor doesn't fit this oracle

What Antithesis provides: a proprietary deterministic hypervisor that runs
your whole system (as containers in a VM) with virtualized time, randomness,
and scheduling; snapshot/branch exploration of the state space; fault
injection; a "sometimes assertions" SDK. The guarantee: same VM state + same
input stream → bit-identical execution. That is *replayability of one
execution*, aimed at flaky distributed-systems testing.

What our oracle consumes: agreement between **two different executions**.
`run_ref` executes native code emitted by LLVM; `run_interp` executes the
interpreter's loop over lowered IR (`execute.jl:131-163`). These disagree on
every class-X observable *even when each is individually deterministic*:

- allocation sequences differ → addresses and `objectid`s differ;
- the runs are sequential in one process → shared counters (`gensym`,
  world age) are consumed at different offsets;
- instruction streams differ → any deterministic scheduler produces
  different task interleavings for the two sides (determinism is a function
  *of the stream*, and the streams differ);
- virtualized clocks advance with retired instructions → interpreted code
  reads later virtual times than compiled code at the same source point.

So under a perfect hypervisor, a program observing any of the above still
produces two stable-but-different observation streams — a permanent false
positive, not a flake. The hypervisor solves "my failure won't reproduce"
(we rarely have that: seeds + the fsync'd journal already reproduce
candidates, and generation is a pure function of the seed) and does not
solve "my two engines legitimately disagree" (which is what actually narrows
the grammar).

The open-source landscape, for completeness:

- **Hermit** (facebookexperimental): ptrace-based deterministic Linux
  runtime — virtual time, sequentialized deterministic scheduling, seeded
  `/dev/urandom`. Experimental, x86_64-only, effectively unmaintained; and
  Julia's runtime (signal-based GC safepoints, libuv event loop, its own
  scheduler) is close to the worst case for syscall-interposition
  determinizers. Same class-X blindness regardless.
- **rr** (+ chaos mode): record/replay of one process tree, then schedule
  fuzzing on replay. Not an oracle enabler — but the right tool for a
  different job we do have: reproducing *crashy* findings whose journal
  repro depends on heap/GC state. Julia supports it natively
  (`julia --bug-report=rr`); worth adopting as the standard triage step when
  a `findings/` repro segfaults intermittently. Zero harness changes.
- **Antithesis itself**: commercial; you'd run the whole campaign VM inside
  it. What it would buy — replay of worker-killing candidates (the journal
  already covers this) and schedule exploration for multithreaded bugs
  (which the differential value oracle cannot use anyway, §7) — does not
  justify the integration for this SUT today. Revisit if we ever fuzz the
  interpreter's own thread-shared state (concurrent breakpoint mutation,
  `compiled_calls` caches) where *exploring* interleavings under a
  crash/invariant oracle is the goal and reproducing the winning schedule is
  the hard part. That campaign would also be served by rr chaos mode first.

One more framing that keeps this honest: the three oracles the harness runs
have three different determinism demands, and the demand is a property of
the *oracle*, not of Julia:

| oracle | demands | why |
|---|---|---|
| differential value equality (`classify.jl`) | cross-**engine** observational determinism | compares compiled vs. interpreted |
| stepping equality (`stepfuzz.jl` `step_divergence`) | cross-**run** determinism, same engine | compares stepped vs. plain interpretation |
| invariants (`step_stuck`, `evalcode_*`, internal errors, corpus failure-mode) | **none** | properties hold per-run |

Everything below is about cheaply *supplying* the first two demands for more
constructs — or *weakening* an observation to the row below when we can't.

## 3. Class E: determinize at the API boundary, not the machine boundary

The SUT is an evaluator. It does not implement clocks, RNG state, files, or
sockets — it executes *calls* to them. What the differential oracle needs is
not "real I/O behaves identically" but "both sides execute the same call
patterns and see the same values". So interpose at the API the generated
program calls, inside the prelude both sides already share (`SETUP_SRC`,
`render.jl:275`), rather than at the syscall layer:

- **An inline per-program PRNG** (`const __LCG__ = Ref{UInt64}(seed)` +
  SplitMix64 draw helpers, rendered into the program text — `render.jl`
  `rngheader`), with grammar rules drawing `__randint__()`,
  `__randrange__(lo, hi)`, `__randbool__()`, `__randfloat__()`. An explicit
  per-program PRNG rather than `Random.seed!` keeps the program hermetic
  from harness and task-local RNG state; a *hand-rolled inline* PRNG rather
  than `const __RNG__ = Xoshiro(seed)` + Base `rand` (the first-shipped
  design) because under RecursiveInterpreter each Base Random draw
  interprets thousands of statements — measured: 100% of `__RNG__`-bearing
  programs exhausted the default 300k statement budget (72/72; 70-72%
  overall abort rate), so the rec axis never actually tested the feature.
  The helpers are a handful of integer/float intrinsics, which run natively
  under interpretation too, so the streams agree bit-for-bit — `DESIGN.md`
  already notes RNG is "handled: both sides could seed identically"; this
  cashes that in. Payoff beyond coverage of the draws themselves:
  *data-dependent* control flow and indices — the guarded-indexing and loop
  rules finally see nonuniform runtime values instead of literal bounds.
  (`SETUP_SRC` keeps `using Random` so old findings/repros with
  `Xoshiro(seed)` still run.)
- **`__vtime__()`**: a monotone counter in the prelude. Unlocks
  timeout-shaped code (`while __vtime__() < deadline`), deadline arithmetic,
  "elapsed" comparisons — control-flow idioms that currently cannot exist.
- **`__venv__`**: a `Dict{String,String}` double of ENV;
  **`__vfs__`**: a Dict-backed pseudo-file API (`__open__`, `__read__`,
  `__write__`, `__close__`) whose error paths raise the *real* exception
  types (`SystemError`, `EOFError`) so guarded observations of exception
  types stay meaningful. The value is not "testing I/O" — it's that
  resource-handle idioms (`open(...) do`, `try ... finally close(h)`) are
  precisely the closure + `finally` + early-exit compositions wave 3 exists
  to stress, and they are currently ungenerable because their subjects are
  excluded.
- **Curated deterministic `ccall`s**: the blanket `ccall` exclusion
  conflates unsafety and pointer values with the call mechanism. The
  `:foreigncall` argument-conversion path is real interpreted surface
  (`src/interpret.jl`), and `ccall(:strlen, Csize_t, (Cstring,), s)` on a
  generated `String`, `memcmp` on two generated strings, or libm calls on
  finite generated floats are deterministic, safe, and identical across
  sides (same process, same libm). Add as probe-style rules that accept
  generated values. Raw pointer *values* stay tainted (§5).

All of this is a few dozen lines of prelude plus grammar rules. It is the
hypervisor's interposition idea applied at the only layer where this oracle
needs it — and unlike a hypervisor, it composes with rec-mode
interpretation of Base, per-candidate seeding, and the existing repro
format (the double is part of `SETUP_SRC`, so `repro.jl` files stay
standalone).

## 4. Zero-infrastructure unlocks hiding in plain sight

Two exclusions currently enforced by grammar absence are already
deterministic and comparable, same-process:

- **`Dict`/`Set` with content-hashed keys** (`Int`, `String`, `Symbol`,
  `Char`, tuples of those; any immutable without an `objectid` fallback).
  Julia's `hash` for these is content-based and identical for both sides of
  one candidate, so iteration order — a deterministic function of insertion
  sequence, hashes, and table geometry — is *also* identical. Full-strength
  value oracle applies, including order-sensitive observations:
  `get`/`get!`/`haskey`/`delete!`/`merge`/`keys`/`values`/iteration. The
  associative-container code paths (two-arg `getindex` vs three-arg `get`,
  `iterate` protocol over a nontrivial struct, `Pair` construction) are
  entirely untested today. The generator constraint is a *key-type
  whitelist*, which `TySum` can already express.
- **Method redefinition / world-age scenarios** ("define f, call, redefine
  f, call") are deterministic — their exclusion is world-age machinery
  complexity, not determinism, and roadmap P4 already claims them. Filed
  here only so the determinism narrative doesn't wrongly absorb them.

## 5. Class X: a taint bit in `TySum`, and observing relations instead of values

`TySum` already rides along every generated expression so rules can pick
compatible operands. Add one lattice bit: `det::Bool` — "this value is
identical across the two engines". Sources of taint: `objectid` of a
mutable, `pointer_from_objref`, `gensym()`, unseeded `rand`, `__vtime__`-free
real clocks if ever admitted. Propagation is the usual join: any operation
consuming a tainted operand produces a tainted result. The rendering of
`__obs__` then keys off taint:

- **untainted** → observe the value, as today;
- **tainted** → observe a *projection* that is deterministic even though the
  value is not: the type name, or — much stronger — a **relation**. Identity
  semantics has exactly this shape: generate `a`, `b` of mutable type and
  observe `objectid(a) === objectid(a)` (stability),
  `(a === b) == (objectid(a) == objectid(b))` (agreement with `===`),
  `objectid(a) == objectid(b)` after `b = a` (aliasing). These are `Bool`s,
  identical across engines, and they test precisely the interpreter's
  `===`/`objectid`/aliasing semantics — the *semantics* become testable
  while the *values* never compare. Same trick for pointers
  (`UInt(p) == UInt(pointer_from_objref(x))` after re-deriving) and `gensym`
  (`startswith(String(s), "##")`, `s !== gensym()`).

This converts "excluded construct" into "construct with a weaker but sound
observation", *per value* rather than per program: full-strength comparison
survives everywhere the taint doesn't flow. It is also the honest
formulation of what a hypervisor cannot do — no environment makes
`objectid` values equal across engines, but their algebra is equal, and the
algebra is what the interpreter implements.

## 6. Determinism as a measurement: the dynamic gates

Everything above is static — the generator only emits what it can prove
comparable. The complementary strategy: emit more, and *measure*
determinism where proof is unavailable. Two gates, cheapest first:

**Confirm-on-divergence (do this first, it makes everything else safe).**
*Implemented — see `classify.jl`'s `confirm`/`confirmed` and `DESIGN.md`; the
description below is the design it was built to.*
A finding used to be reported after one ref run and one interp run
(`run_all`, `execute.jl`). Add: when `classify` produces a finding,
rerun the reference; if `ref₂` disagrees with `ref₁`, classify
`nondet_discard` (tracked alongside `aborted`, never reported). Else rerun
the interpreted side; unstable → same discard. Only *stable* divergences
reach dedup/shrinking. Cost lands only on divergences — rare by
construction — so the agree path pays nothing. This is the backstop that
makes taint mistakes, prelude oversights, and future grammar expansions
degrade into tracked discards instead of false findings. (It also
stabilizes shrinking: every shrink step already re-runs the candidate, and
a nondeterministic fingerprint would make the shrinker reject or, worse,
chase moving targets.)

**Self-agreement admission for the corpus axis (the big prize).**
*Implemented — see `corpus.jl`'s `corpus_certify`/`corpus_value_run` and the
`certified` counter; the description below is the design it was built to.*
The corpus axis is the direct answer to "we can't generate a lot of code" — real
Julia has the constructs no one wrote rules for — but it used to demote
*all* real code to the failure-mode oracle because "real code is not
deterministic" (`corpus.jl` header). That property is per-fragment, not
universal, and it is *measurable*: seed the sandbox RNG (`Random.seed!(k)`
before every run — task-local RNG makes corpus `rand` calls reproducible),
run the fragment under `Core.eval` **twice** in two fresh modules, and
compare the observation streams. Agreement is a determinism certificate for
this fragment on this input; certified fragments graduate to the full
differential value oracle (`classify` applies unchanged), and the rest keep
today's failure-mode oracle. In practice most spliced fragments compute —
arithmetic, collections, string formatting, comprehensions — and will
certify; a fragment computing `sum(rand(10))` certifies under seeding and
becomes a value-compared test of interpreted `rand`+`sum` against compiled,
which today it cannot be. The same certificate authorizes the *stepping*
oracle's value comparison (cross-run demand, weaker than cross-engine) on
real code.

Two honest caveats. `ref₁ == ref₂` is evidence, not proof — a stable heap
can repeat address-derived values; the confirm-on-divergence gate is the
second line, and coincidence-twice-then-again-under-reconfirmation is fuzzer
noise-floor territory. And fragments that are deterministic but not
idempotent (mutating a stdlib global, consuming a process counter) fail
self-agreement and are discarded — the safe direction. Track the
certification rate next to the existing `ran`/`discarded_junk` counters for
the same reason those exist: a rate collapse means the gate, not the
corpus, is broken.

Budget note: rec-mode interpretation dominates per-candidate cost
(`yield-analysis.md`, throughput note); an extra `Core.eval` run on corpus
candidates is comparatively cheap, and confirm-on-divergence costs nothing
on the agree path.

## 7. Concurrency: invariance, not determinization

The roadmap's structured-concurrency subset (`DESIGN.md` M3) already
records the key constraint: task *bodies* escape interpretation (the
scheduler invokes them), so the interpreted surface is task setup, `@sync`
lowering, exception propagation, and `:enter`/`:leave` interaction with
switches. For that subset the differential oracle is salvageable — but not
by determinizing schedules. Even deterministic schedulers are functions of
the instruction stream, and the two engines' streams differ, so their
schedules differ; class X again. The sound construction is
**schedule-invariant observables**: each task writes only its own slot (or
communicates only through `Channel`s), observations happen after the
`@sync` join, order-sensitive observations of cross-task effects are either
forbidden or multiset-normalized in `__fjnorm__`. Then *any* schedule on
*either* side yields identical observations and no determinism is needed at
all — the program is deterministic in the semantics, not the environment.
`-t1` keeps hardware parallelism (class E) out; the fuel discipline extends
to `wait`/`take!` via bounded channels and mandatory joins.

Racy programs — where the observable *does* depend on the interleaving —
are permanently outside the differential value oracle, hypervisor or not
(two deterministic engines exploring two different interleavings is a false
positive that reproduces forever). They remain reachable by the
invariant-oracle rows of the table in §2: no internal errors, no deadlock
within budget, stepping doesn't wedge. That is also where schedule
*exploration* tooling (rr chaos; Antithesis, if ever) would slot in — as a
crash-oracle campaign against the interpreter's own shared state, not as a
widening of this oracle.

## 8. What stays excluded, and why no infrastructure changes it

- **Class U**: `===`/`reinterpret` on float expressions, out-of-range
  `unsafe_trunc`, `@fastmath`/`@simd`, and — flagged for any future float
  math expansion (`sin`/`^`/`evalpoly` reach `muladd`) — fma contraction.
  Comparison-modulo-spec (`isequal`'s NaN class, tolerance bands) or
  exclusion. The shakedown lessons in `DESIGN.md` are all this class; expect
  the next one the first time a transcendental enters the grammar.
- **Real threads** (`-t N`): class E at the hardware level plus class X
  interleavings; invariant oracles only.
- **Real I/O / processes / network / `sleep`**: SUT-irrelevant (§3); the
  doubles capture the evaluator-visible surface. Also the corpus denylist
  (`corpus.jl:46-53`) stays — it guards the fuzzer process, not the oracle.
- **Finalizers / GC-timing observables / `WeakRef`**: when a finalizer runs
  is a function of allocation behavior, which differs across engines —
  class X with no useful relational projection ("ran at most once" is an
  invariant, not a value). Excluded from value comparison; fair game for
  invariant axes.

## 9. Ordered plan

1. **Confirm-on-divergence gate** — **done** (`classify.jl`:
   `confirm`/`confirmed`/`confirmsrc`/`confirmreport`, wired into `driver.jl`
   and `supposition.jl`; new tracked class `nondet_discard`, counted next to
   `aborted` in campaign stats). Safety net for everything below.
2. **Inline PRNG + rand rules; `Dict`/`Set` with content-hashed keys** —
   **done** (§3 RNG, §4). The inline SplitMix64 header (`const __LCG__ =
   Ref{UInt64}(seed)` + draw helpers) is baked into the rendered program with
   a *literal* seed (`Program.rngseed`, `render.jl` `rngheader`), so both
   engines run identical integer transitions and agree bit-for-bit. (First
   shipped as `const __RNG__ = Xoshiro(seed)` + Base `rand`; replaced after
   measuring that 100% of such programs exhausted the 300k statement budget
   under RecursiveInterpreter — Base's Random machinery costs thousands of
   interpreted statements per draw. `SETUP_SRC` keeps `using Random` for old
   repros.) Rules `__randint__()` / `__randrange__(1, n)` / `__randbool__()` /
   `__randfloat__()` feed the Int/Float/Bool expression menus, so rand-derived
   values flow into guarded indices, `if`/`while` conditions and a rand-derived
   `for` trip count (`for i in 1:__randrange__(0, maxloop)`) — data-dependent
   control flow, termination still by construction (rand never feeds while-fuel).
   `Dict`/`Set` are keyed by the content-hashed whitelist (Int/String/Symbol/
   Char/Bool + tuples of those; new `DictT`/`SetT`/`CharT` summaries): rules for
   construction, `get`/`get!`/`haskey`/`in`/`length`, `setindex!`/`delete!`/
   `push!`, and `keys`/`values`/whole/`length` observations; `__fjnorm__`
   normalizes `AbstractDict`/`AbstractSet` to sorted normalized contents.
   All gated by the `:rng`/`:dict` swarm features and a new `:determinism`
   policy. Measured: 0 manufactured divergences over thousands of cases.
3. **Corpus self-agreement certification** — **done** (§6, `corpus.jl`). Before
   the failure-mode oracle, each case is certified: seed the sandbox RNG, run
   the fragment under `Core.eval` twice, auto-observe its comparable top-level
   bindings, and compare the streams with `outcomeeq`. Agreement graduates the
   fragment to the full differential value oracle (`classify` + the
   confirm-on-divergence gate + fingerprint/dedup/shrink/`writefinding`);
   disagreement falls back to today's failure-mode + stepping oracle. A
   `certified` counter is printed next to `ran`/`discarded_junk`. Real code
   graduates from failure-mode to value oracle per-fragment — the largest step
   toward "test a lot more code".
4. **Virtual doubles** — **`__vtime__` done**, ENV/fs deferred. `__vtime__()`
   (monotone counter in `SETUP_SRC`) is in the Int expression menu, so
   deadline/elapsed-shaped control flow (`while __vtime__() < N`) is generable;
   deterministic because both sides call it in lockstep. `__venv__`/`__vfs__`
   and the handle/do-block/`try-finally` grammar rules they would unlock are
   **deferred** (they are the larger, optional half of this item, and only pay
   off once the resource-idiom rules that consume them exist); curated
   deterministic `ccall`s likewise. See NEXT.md item 5.
5. **Taint bit in `TySum` + relation observations** for
   `objectid`/`gensym`/pointer; curated deterministic `ccall` probes
   (about a week; touches `typesum.jl`/`env.jl`/`rules.jl`/`render.jl`).
6. **Schedule-invariant task subset** per roadmap M3, now with the
   soundness argument spelled out (a week).
7. **rr for crash triage** (docs-only: when a `findings/` repro segfaults
   intermittently, capture it under `julia --bug-report=rr`).

Explicitly not on the plan: Hermit/Antithesis-style whole-system
determinization — wrong layer for a two-engine oracle (§2). Reconsider only
for a future interleaving-exploration campaign against interpreter-internal
concurrency, and try rr chaos mode first even then.

Relation to `yield-analysis.md`: this track is orthogonal to P2 (semantic
coverage) and the eval_code/ExprSplitter axes, which remain the
highest-expected-yield items overall; items 1–3 here are cheap enough to
interleave, and item 3 multiplies the corpus axis that P3 already
established.

## References

- Antithesis (deterministic hypervisor + state-space exploration):
  https://antithesis.com/docs/introduction/how_antithesis_works/
- Hermit (deterministic Linux runtime, facebookexperimental):
  https://github.com/facebookexperimental/hermit
- rr + chaos mode: https://rr-project.org/ ; Julia integration:
  `julia --bug-report=rr` (BugReporting.jl)
- Jit-Picking (CCS 2022) — the nondeterminism-normalization layer for
  differential engine testing:
  https://publications.cispa.saarland/3773/1/2022-CCS-JIT-Fuzzing.pdf
- dettrace / "reproducible containers" (ASPLOS 2020), the academic lineage
  of syscall-level determinization:
  https://dl.acm.org/doi/10.1145/3373376.3378519
