# FuzzJI: state of play and what to do next

Handoff document. Read `DESIGN.md` for how the harness works,
`yield-analysis.md` for why it is built this way, and `determinism.md` for
what the determinism requirement actually forces — and how to relax it; this
file is the short version of *where things stand* and *what to pick up*.

Last updated after merging two parallel sessions: the one that added the
stepping, eval_code and corpus axes plus the campaign tooling, and the one
that produced the determinism analysis and the generation-generality
proposals now folded into the ranked list below. Since then **item 1 has
landed**: the confirm-on-divergence gate and `fuzz/triage.jl`. Item 2
(semantic coverage) is now the top of the list.

---

## Session handoff — 2026-08-04, second session (read this first)

This session worked the previous handoff's follow-up list: false-positive
sources on the call and corpus axes, the nightly-CI overrun, and repro
fidelity. Everything is committed on
`claude/false-positive-fussing-improvements-igts2c` (which contains the whole
harness — it merges `claude/fuzzing-effectiveness-review-92ph29`); the nightly
workflow's checkout pin now points there too, so a `workflow_dispatch` from
that branch exercises the improved harness.

### False-positive fixes

1. **Call axis: per-run global reset** (previous item 1, the 0-for-6 axis).
   `call_program` now snapshots the module's whole mutable surface after the
   definition pass (`snapshotglobals`) and restores it before *every* run of a
   call — native #1, native #2 and the interpreted run (`restoreglobals!`):
   non-const globals are rebound to a deepcopy, const-bound mutables (Ref,
   Vector, Dict, Set, mutable struct — atomic fields included) are restored
   in place, preserving the identity closures hold. This closes the whole
   unreset-global class (`1dc96bf0` and friends) instead of downweighting the
   axis; certification stays as the backstop for what the reset cannot reach
   (const-bound closures over captured state). Selftest covers the three
   mutation shapes with calls whose native outcomes coincide by construction.
   Gotcha worth remembering: `names(m; all=true)` and `Base.isconst` consult
   the *caller's* world, so inside `call_program` they silently missed the
   just-`Core.eval`'d bindings — every world-sensitive lookup in the snapshot
   goes through `invokelatest` now.
2. **Corpus axis: frame-introspection filter** (previous item 2).
   `corpus_ok` rejects fragments that call `stacktrace`/`backtrace`/
   `catch_backtrace`/`catch_stack`/`current_exceptions` (same call-position
   AST walk as `UNSAFE_NAMES`), so backtrace-asserting fragments like
   `390a4eeb` can no longer self-certify and then diverge on frame details.
   Corpus certification rate is unchanged (~57% in the smoke run).

### Fuzzing-rate / CI fixes

3. **Nightly lane overrun diagnosed and closed** (previous item 3). Run #8's
   nightly lane ran its campaign step 5h48 against a 3 h DURATION until the
   job's 6 h limit cancelled it: a wedged nightly julia ignored the per-batch
   `timeout` TERM, which never escalated, so the deadline check never ran
   again. Three-layer fix: `timeout -k 30` per batch (longrun.sh), a
   `timeout -k 60 $((DURATION+2700))` backstop around the whole campaign step
   (workflow), and `if: always()` on the report step so findings are printed
   to the log even if a lane is cancelled. The `--n` shortening the previous
   handoff suggested was not needed — DURATION already bounds the campaign
   when TERM is deliverable.
4. **longrun.sh batches right-sized; timeout kills no longer pollute the
   crash journal.** The corpus batch (`--n 800` at ~3 s/case) could never
   finish inside the 1800 s batch timeout, so *every* corpus batch was killed
   mid-flight and its in-flight candidate preserved as spurious "crash"
   evidence. Batches are sized to finish (corpus 450, native 3500), and an
   exit-124 batch now deletes `current.jl` instead of promoting it —
   exit 137 (TERM ignored, KILLed: a real hang) and signal deaths still
   preserve theirs.

### Repro fidelity (previous item 4 — done)

`reprostep(SRC, walkseed)`, `reproevalcode(SRC, walkseed)` and
`reprocorpusstep(SRC, walkseed)` in reprolib.jl replay the recorded walk the
way `reprocall` already did (loading FuzzJI rather than duplicating walk
logic), and `writefinding` routes the step/evalcode/corpus modes to them.
Previously these modes fell back to `reprorun`, which never steps — their
repros under-reproduced by construction.

### State / what's left

- Selftest 449/449 on 1.12.6. Smoke campaigns after the changes: call 150/150
  agreed (0 findings, 0 nondet, ~1.7 cases/s steady state — reset cost is
  noise), corpus 60 cases / 29 ran / 34 certified / 0 findings.
- **Run #8's nightly findings artifact is now partially triaged** (previous
  item 5): of its ~30 new entries, 3 corpusvalue findings are the
  backtrace-introspection class (now filtered at admission) and the 6 new
  call divergences are almost certainly the unreset-global class (now
  closed) — re-run the nightly lane to confirm they stop re-deriving. What
  remains genuinely unanalyzed: ~20 corpusvalue `interp_only_throw` findings
  on 1.14-DEV (mostly `TestSetException`/`FallbackTestSetException` — real
  early-warning material for the interpreter on nightly), one
  `corpus-corpus_internal_error-6eea3f32`, and `step-step_divergence-7e03896b`.
  The artifact is `fuzz-findings-julia-nightly` on run 30854168537.
- `370cc475` (candidate upstream Julia UB) deliberately not touched — being
  handled separately.
- The previous session's ranked list below is otherwise unchanged; its items
  1–4 are done as described above.

---

## Session handoff — 2026-08-04, first session

This session ran a long `-O1` campaign plus CI runs and turned the "few
similar issues" concern into concrete fixes. Everything below is committed on
`claude/fuzzing-effectiveness-review-92ph29`; **PR #1** (branch → master) is
open and green-gated but **not merged** — left for human review.

### What landed (real interpreter/debugger bugs, each with a regression test)

1. **Module-redefinition shadowing** — `find_or_create_module`
   (`src/construct.jl`). `module F` shadowing a `using`-imported binding threw
   a spurious `invalid redefinition of constant`. Commit `7d05ccf`.
2. **Method-def type-shadowing** — `evaluate_methoddef` (`src/interpret.jl`).
   A method defined on a `using`-imported *type* created a fresh function that
   shadowed it; later use as a type threw `invalid type for argument` /
   `invalid subtyping`. Commit `3a323e8`.
3. **compilerbarrier setting-validation** — `src/builtins.jl` + generator. The
   interpreter silently accepted an invalid barrier setting native rejects.
   Commit `3a323e8`.
4. **Debugger `is_leaf` crash** — `src/commands.jl`. A breakpoint firing inside
   a kwarg value left a non-leaf frame, crashing the next `debug_command`.
   Commit `b5e7fa7`.
5. **invoke non-tuple arity** — raises `TypeError` for an invoke signature arg
   that isn't a tuple type. Commit `9b839d6` (finding `value_divergence-2c10d219`).

Fixes 1–3 came from **rooting out the old `env_binding_mismatch` corpus
suppression**: that whole "corpus environment false-positive" class turned out
to contain real bugs, so the suppression was **removed entirely** — every
member was either fixed above or verified a non-divergence.

### Infrastructure that landed

- **Nightly-Julia fuzzing lane unblocked** (self-calibrating `atomic_fence`
  ban) — first-ever nightly fuzzing runs in CI (`.github/workflows/fuzz-nightly.yml`).
- **Supposition selftest flake fixed** — the support gate is no longer stochastic.

### CI / campaign state at handoff

- **CI run #8** (branch): selftest gate **green on all three lanes** (1.12,
  pre/1.13-rc1, nightly/1.14-DEV). Selftest 437/437. 1.12 + pre campaigns ran
  fresh-seed and came back **regression-clean** (no fixed-bug signature
  reappeared).
- **Nightly CI campaign** hit the ~6h runner timeout and was **cancelled
  before reporting** — findings artifact uploaded but not analyzed in-log.
  Budget is too long for the 6h limit (see follow-ups).
- **Local `-O1` campaign** (~350 batches): 345 clean exits, 5 `gc-stock.c` GC
  deaths (the known upstream `-O1` Julia GC crash, ~1/30 — documented in
  `findings/julia-gc-segfault/`, not ours).

### Open follow-ups (none blocking; ranked, for the next agent)

1. **Call axis is 0-for-6+ on real bugs.** Every divergence has been a harness
   artifact (PRNG/clock/global state). Either add three-way JI-vs-C
   adjudication or a per-call global reset, or downweight the axis. Highest
   signal-to-effort question here.
2. **Corpus axis:** filter out fragments that introspect
   backtraces/stacktraces — they self-certify then diverge on frame details
   that say nothing about the interpreter.
3. **Nightly CI campaign budget** exceeds the 6h runner limit — shorten `--n`
   in `fuzz-nightly.yml` so it reports before cancellation.
4. **step/corpus `repro.jl`** should replay the walk/prelude rather than call
   `reprorun` — current repros under-reproduce.
5. **Unanalyzed at handoff, worth a look:** `step_divergence-540b8b2b`; the
   nightly run #8 findings artifact; and `370cc475` — a candidate **upstream
   Julia UB** (corrupted exception from a too-few-args builtin at `-O1`).

---

## Where things stand

Six axes exist. Five of them cover surfaces that had no systematic testing
before. (See `evaluation-2026-08-03.md` for the rigorous progress review that
motivated the two newest additions: the step axis's real-breakpoint driver —
`breakpoints.jl` was 13% covered with 30/34 definitions never executed — and
the `call` axis over the public entry points, which every other axis
bypasses.)

| engine | what it tests | oracle |
|---|---|---|
| `native` / `supposition` | run-to-completion semantics | differential vs. compiled Julia, on observation streams |
| `step` | `debug_command` walks — `commands.jl`, `breakpoints.jl`; the walk now sets/toggles/removes **real breakpoints** (entry, per-method, conditional, line) on the program's own callables | stepping terminates, raises nothing plain interpretation doesn't, and reaches the same observations |
| `call` | the **public entry points** — `enter_call`/`prepare_args`/`prepare_call` + `debug_command` on method frames, with synthesized arguments (edge values, structs, varargs, kwargs) | native call ×2 (self-agreement certification) vs. `enter_call` + walk, on status/exception/normalized return value |
| `evalcode` | `eval_code` at paused frames — `utils.jl` | reads match `locals(frame)`; writes round-trip and don't disturb other locals |
| `corpus` | real Julia source, spliced — `construct.jl`, macro-heavy paths | per-fragment self-agreement certification → full value oracle when certified, else failure-mode only (determinism.md §6) |
| `split` | adversarial toplevel forms — `ExprSplitter` in `construct.jl` | differential vs. `Core.eval` on failure mode, observation stream, **and the resulting module tree** |

Supporting tools: `metrics.jl` (what the generator actually produces, without
executing), `coverage.jl` (what a campaign actually *reaches* inside
`src/` — line coverage of the interpreter, mapped onto builtin dispatch arms
and functions; report in `coverage-report.md`), `longrun.sh` (sharded
restart-looping campaigns), `crashmin.jl` (minimize a program that kills the
process), `triage.jl` (which side broke, and does it still break on the
newest Julia), `reshrink.jl` (re-shrink a finding from its seed far harder
than an inline campaign can afford), `diag_stuck.jl` (why a stepping walk is
stuck), `preserve-findings.sh` (force-commit findings, since `findings/` is
gitignored).

**Results so far: five JuliaInterpreter bugs, all fixed.** A common thread:
every one is in the interpreter's *hand-reimplemented builtin/exception paths*
— exactly the seam the literature predicts an interpreter diverges from the
reference — and four of the five are "wrong exception type on a malformed or
edge call".

- **Fixed**: `cmp` mode diverged on `rethrow()`/`rethrow(exc)`/
  `current_exceptions()` inside an interpreted `catch` — the interception that
  answers them from the frame's modelled exception stack sat on the generic
  `evaluate_call!`, which `NonRecursiveInterpreter` overrode with a
  `native_call` bypass. Hoisted into `intercept_call`, shared by both
  interpreters. `findings/cmp-exception_divergence-61051b0f/`.
- **Fixed**: `Core.invoke` with fewer than two arguments raised `BoundsError`
  from the interpreter's own `invoke` rewrite where compiled Julia raises
  `ArgumentError` (and `ErrorException` vs. `TypeError` for a non-type second
  argument). Defers malformed invokes to native. `findings/interp-invoke-arity-exception/`.
- **Fixed**: `Core.invokelatest()` with no function argument raised
  `BoundsError` (1.12, where it is a builtin) — the expand path indexed an
  empty args vector. Defers the empty case to native.
- **Fixed** (large-scale campaign, three-way-confirmed):
  `Core._call_latest(:b)` / `Base.invokelatest(:b)` — a non-callable Symbol
  first argument — raised `UndefVarError` under `RecursiveInterpreter` where
  compiled Julia, Compiled mode, *and Julia's own built-in interpreter* all
  raise `MethodError`. The expand path put the evaluated first-argument value
  bare in function position, where a Symbol was re-read as a name. QuoteNode-
  wrap the callee. `findings/value_divergence-142a17f7/` (minimized to 25
  lines via `ddmin_source`; the seed no longer re-derives it because the
  generator changed mid-campaign).
- **Fixed** (found by the post-evaluation reweighted campaign, 2026-08-03):
  `invoke` with a signature argument that is a `Type` but not a *tuple* type —
  `invoke(Int, Char, …)` — raised `ErrorException("expected tuple type")` from
  Base's `signature_type` under `RecursiveInterpreter` where compiled Julia
  raises a clean `TypeError`. The interpreter's `invoke` rewrite
  (`src/interpret.jl`) admitted any `argtypes isa Type` before calling
  `signature_type`; now defers a non-tuple `argtypes` to native `invoke`, the
  same "let native raise the real error" pattern the neighbouring
  malformed-shape checks use. Regression test in `test/interpret.jl`'s
  `invoke` testset. `findings/value_divergence-2c10d219/`. This is the first
  interpreter bug from the axes/throughput reallocation — the differential
  `native` axis produced it within ~1 h of the reweighted run, on a program
  reaching the `invoke` probe through the barriered-argument path.

Plus a debugger crash found by the stepping axis (`more_calls_on_current_line`
dereferencing a `nothing` from `whereis`, `findings/step-step_only_throw-88d4b5b2/`,
fixed) and a harness robustness fix (an `evalcode`-shard segfault building an
untyped `Dict` over frame locals — Julia's `lookup_typevalue`, not an
interpreter bug — closed by forcing `Dict{Symbol,Any}`).

The first large-scale campaign (Julia 1.12, three-way oracle, ~100 batches
across six axes over 3h) surfaced the fourth bug and populated the
`findings/julia/` stream with three compiled-vs-built-in-interpreter
exception-phase divergences (class-U within Julia itself, low priority). The
three-way oracle earned its keep: it distinguished the genuine
`RecursiveInterpreter` bug from class-U noise automatically.

Everything else the work produced:

- six generator bugs and five harness bugs, several of which were silently
  destroying yield (see the lessons below) — among them `__fjnorm__`
  observing a type by its *module-qualified* name (found by the split axis)
  and a scope-tracking slip that made the parse gate silently discard 4–8%
  of every candidate stream (found while building the prober);
- one genuine Julia compiler crash, which turned out to be a known 1.11
  regression already fixed in 1.12 (`findings/julia-codegen-abort-allocopt/`).
  It still bites: it aborts the *process*, so a shard that hits it writes no
  coverage data at all (`coverage.jl` reports such shards explicitly). The
  prober's soak turned up two further *reference-side* Julia defects the
  denylist now steers around: wrong-arity intrinsic calls abort inside
  codegen, and a float intrinsic handed a same-width integer
  (`Core.Intrinsics.ceil_llvm(3)`) corrupts the heap without raising.
- a **transient GC segfault on Julia 1.11.9 *and* 1.12.6**, in the same
  family: a campaign dies with SIGSEGV inside a garbage collection (seen at
  `firstdiff` in the comparator and `gc_mark_obj8` in the prober's soak on
  1.11.9; at `gc_mark_objarray`/`gc_try_claim_and_push` on 1.12.6) after
  cumulative heap activity. It does **not** reproduce on isolated replay of
  the candidate that was executing — the crashing candidate runs clean in a
  fresh process (confirmed 1.12.6: the evalcode candidate that took a misc
  shard down at batch 4 of the 2026-08-03 run ran clean across 5 processes ×
  40 walkseeds) — so it is heap-state-dependent, not a harness or interpreter
  bug. `longrun.sh` is built to survive it: each shard restart-loops and
  preserves `current.jl` to `crashed/` before the next batch. Expect shards
  to die partway and restart; that is the designed behaviour, not a failure.
  **1.12 does NOT clear it** (the standing question from the previous run,
  now answered — unlike the codegen-abort sibling, which 1.12 did fix). It is
  worth reducing to a standalone reproducer and reporting upstream: a
  cumulative-heap GC crash that survives to 1.12 is a live Julia bug, and the
  `crashed/` candidate plus `--bug-report=rr` (NEXT.md item 1's open rr step)
  is the way in — but it is a *Julia* bug, so it does not block this harness.

One bug in ~10^4 candidates is not a yield estimate. The axes have not run at
the scale where they would be expected to produce much — the literature's
numbers are 10^8 and up, these runs are 10^3–10^4.

**Post-evaluation session (2026-08-03, `evaluation-2026-08-03.md`):** the
evaluation's recommendations 2–4 are now built. What that added, and what it
measured:

- **Ground truth exists now** (`mutantbench.sh` / `mutantbench-report.md`):
  reverting historical fixes and re-fuzzing shows the **step axis rediscovers
  a real bug at n=300 in ~143 s** (same fingerprint bucket as the historical
  finding), while **native-rec did NOT rediscover the `_call_latest` bug at
  n=500** — consistent with it originally needing a ~100-batch campaign, and
  direct evidence for running long. Curation caveat: only 6 of 14+ examined
  fixes make clean mutants; the stacked utils.jl/commands.jl history means
  **no clean mutant exists for the evalcode axis**, so its yield remains
  unvalidatable for now.
- **The abort leak.** The determinism-unlock `__RNG__` grammar made *every*
  program containing a `rand(__RNG__, …)` call exhaust the 300k statement
  budget under RecursiveInterpreter (72/72 measured; overall abort rate
  70–72% vs ~1% before the grammar landed) — i.e. since that grammar landed,
  the native-rec axis was silently testing only the ~28% of programs without
  the flagship feature. Aborts hit 0/120 at a 1M budget; the structural fix
  (cheap inline PRNG instead of interpreted Base Random) is in
  `determinism.md` §3 / the grammar section of DESIGN.md. Lesson for every
  future grammar feature: **check the abort-rate delta in `--modes rec`
  before believing the feature is being tested at all** — `dict` programs
  abort at ~70% when present too, so the same audit applies there.
- **Throughput** (`throughput-report.md`): the hidden per-candidate cost was
  each module's own `__fjnorm__` re-specializing per candidate; shared
  helpers landed for a measured **1.68× on native both-modes** (2.43/s) and
  1.86× on split (24.5/s). Item 8's remaining ideas (double lowering, module
  pooling proper) measured small and are documented there.
- **Nightly CI** (item 7 — done): `.github/workflows/fuzz-nightly.yml`,
  cron + dispatchable, Julia 1.12 lane (red = bug) plus `pre` lane
  (continue-on-error; red = upcoming breakage), selftest as a support gate so
  campaign findings are never produced on an unsupported Julia, findings
  uploaded as artifacts, fails on news.
- **Campaign mix reweighted by evidence** (`longrun.sh`): step ×2 shards
  (only ground-truth-validated axis; breakpoints.jl went 13% → 80% line
  coverage once the walk drove real breakpoints), native ×1, call ×1 (new
  public-API axis), corpus ×1, split+evalcode sharing one alternating shard.
  Shard seed ranges no longer overlap (10^8 spacing).

---

## Work items, ranked

This list merges two sessions' proposals: the axis/tooling session that first
wrote this file, and the determinism/generality session (`determinism.md`,
plus the reflection-prober design in item 4). The ordering logic is
unchanged — expected yield per engineering-hour, with oracle strength and new
surfaces ahead of raw input volume.

### 1. Finding-intake hardening — **done**, except the rr step

Small, first, and bought with time already lost. Three gates between "the
harness noticed something" and "a human looks at it":

- **Version-aware triage of reference-side crashes** — **done**:
  `fuzz/triage.jl`. A crash on the **reference** side (compiled Julia) is a
  *Julia* bug, not a JuliaInterpreter bug. Point the script at a
  `findings/<dir>/`, a `repro.jl` or any candidate `.jl` and it runs each side
  alone in its own `julia` under a timeout, attributing by exit status (signal
  death / unusual exit = crash, exit 1 = uncaught exception, exit 0 = clean)
  rather than by reading a backtrace; then, if the reference side is what
  broke, re-runs *that* side under the newest installed Julia (`julia
  +release`) and says whether it still reproduces. Verdict goes to stdout and,
  for a findings directory, to `triage.md` beside the repro. On the
  already-known codegen crash it answers the whole question in under two
  seconds: reference crashes with SIGABRT on 1.11.9, clean on 1.12.6, fixed
  upstream. That episode — journal replay, minimization, C-Reduce, a delegated
  reduction agent — was work on a bug fixed a release earlier, and this is the
  one command that would have said so.
  The **routing** half is deliberately not done: reference-side crashes still
  land in the same `findings/` bucket, because the harness cannot classify a
  crash it did not survive. Triage is what separates them, after the fact.
- **Confirm-on-divergence** (`determinism.md` §6) — **done**:
  `confirm`/`confirmed`/`confirmsrc`/`confirmreport` in `classify.jl`, used by
  both the native and the supposition engine, in both `:rec` and `:cmp` modes.
  On divergence the reference is re-run and compared against itself (status,
  exception name, observation stream elementwise + length); disagreement is
  `nondet_discard`, tracked next to `aborted`, never deduped/shrunk/reported.
  If the reference is stable the interpreted side gets the same treatment.
  After shrinking, whatever is about to be written is confirmed once more, with
  a fallback to the pre-shrink program and a discard if neither holds. Costs
  nothing on the agree path, stabilizes shrinking, and turns every future
  nondeterminism mistake — grammar, prelude, or corpus — into a tracked
  discard instead of a false finding. The selftest's nondeterminism canary (a
  program observing `rand()`) is a textbook `value_divergence` that the gate
  discards. Prerequisite for item 5, now satisfied.
- **rr for intermittent repros.** When a `findings/` repro crashes
  only sometimes, capture it under `julia --bug-report=rr` (rr support is
  first-class in Julia) before any hand minimization. **Still to do** — the one
  part of this item not built.

### 2. Semantic coverage of the interpreter (P2 in `yield-analysis.md`)

**Stage one: done** — `fuzz/coverage.jl`, with its output committed as
`fuzz/coverage-report.md`. **Stage two is still open** and is what to pick up
here.

Stage one did not need the `CoverageInterp <: Interpreter` this item
originally called for (an interpreter subtype recording statement heads,
builtin arms, `evaluate_call!` paths and `localmethtable` dispatch).
Julia's own `--code-coverage=@<repo>/src`, gathered from campaign
subprocesses, answers the same question with *zero* instrumentation of the
interpreter and a ~1.3× time tax: `coverage.jl` spawns the shards, parses the
`.cov` files (one count-or-`-` column per source line — no Coverage.jl
dependency), and maps never-executed lines back onto (a) every
`f === <builtin>` arm of `maybe_evaluate_builtin`, (b) the enclosing
definition of every other line, per file, per engine, and per interpreter
mode. Re-run it after any grammar change: `metrics.jl` says what is
*generated*, this says what is *reached*.

What the committed run says (4000 candidate-runs, four axes, both modes,
julia 1.11.9):

- **15 of 65 live dispatch arms are never hit.** A further 19 arms in the file
  are compiled out by `@static` on 1.11 and are not gaps at all — reading the
  raw `.cov` without that check would overstate the miss rate by more than
  double. The cold 15 cluster: `swapglobal!`/`modifyglobal!`/`replaceglobal!`/
  `setglobalonce!`, the four `memoryref*` atomics, `atomic_pointermodify`,
  `llvmcall`, `_compute_sparams`, `_equiv_typedef`, `_call_in_world_total`,
  `_apply_pure`, and the `kwinvoke` tail (whose test line never even executes).
  That is item 4's to-do list, and it is mostly *atomic and global mutation*
  plus keyword `invoke` — not the syntax gaps the earlier waves guessed at.
- **The `corpus` axis reaches 47 arms; `native` reaches 36**, and 12 arms are
  reached *only* by spliced real code. What the generator is short of is
  shapes, not volume — which is the argument for item 5's corpus
  certification, from the other direction.
- **`rec` reaches 6 arms `cmp` cannot**, `cmp` reaches none `rec` cannot: the
  expected asymmetry (compiled mode runs calls natively), now measured.
- **Line totals: 1903 of 2694 instrumented lines hit (70.6%), 137 of 320
  definitions never hit.** The never-hit set is dominated by the *public
  debugger API the harness bypasses* (`enter_call`, `interpret`, `breakpoint`,
  `extract_args`) and by display code (`Base.show` methods, `print_framecode`),
  not by interpretation paths: `interpret.jl` has only 6 never-hit definitions
  of 44. `breakpoints.jl` is the weakest real surface at 13% of lines.
- Of the still-open grammar gaps listed at the bottom of this file, the ones
  with cold evidence behind them are **destructuring** (`is_indexed_iterate_call`,
  `maybe_step_through_arg_destructuring!` never run), **`@generated`**
  (`get_source` never run) and **keyword sorters**
  (`maybe_step_through_kwprep!` never run); `do` blocks have no distinct
  interpreter surface at all, so closing that gap buys inputs, not paths.

- **Stage two.** Feed it back as corpus admission: keep a candidate whose
  choice sequence hit new coverage, mutate and splice from those. The
  Supposition `TCRNG` adapter already makes generation a pure function of a
  choice sequence, so the substrate for this exists. Note what stage one
  implies about the feedback signal: line coverage of `src/` saturates fast
  (the second 2000 candidate-runs added two arms and 25 lines), so admission
  wants a finer signal than "a new line" — arm × arity, or statement-head ×
  context, which is where the `CoverageInterp` idea earns its keep after all.

### 3. ~~Shrinking for the step, evalcode and corpus axes~~ — **DONE**

Every axis minimizes a finding before writing it, and `meta.md` records the
original alongside the shrunk program. The split axis (added after this item
first landed) uses `ddmin_source` with "same fingerprint" as its property —
a pure source-text-in/verdict-out predicate.

What it took, in case any of it needs revisiting:

- **The shrinker takes the property as an argument.** `shrink_ir(prog, keep)`
  runs the same greedy removal/simplification/repair passes as before, but
  `keep(src::String)::Bool` decides whether an edit survived. The differential
  behaviour is `differential_keep` (re-run, classify, compare fingerprint) and
  `shrink(prog, fp; ...)` is a thin wrapper over it, so nothing on that axis
  changed.
- **The step walk needed its own seed first.** The walk used to continue the
  generator's RNG, which makes the command sequence a function of the
  program's size — delete a statement and every later draw moves, so no shrunk
  candidate can be replayed or judged. Each candidate now draws a `walkseed`
  from the generator's stream and runs the walk on a fresh `Xoshiro(walkseed)`;
  the seed is recorded in the finding and replayed verbatim on every candidate.
  Same for the eval_code pause walk and the corpus stepping stage.
  `diag_stuck.jl` mirrors the derivation and takes an explicit `WALKSEED`
  third argument, which is how you replay a walk against a *shrunk* program.
  Note the predicate requires the same verdict **class and fingerprint salt**,
  not the same command trace: a shorter program has fewer pause points, so the
  trace legitimately diverges.
- **Corpus findings are real code, so ddmin, not the IR shrinker.**
  `ddmin_source(src, keep)` deletes toplevel statements in shrinking chunks,
  then recurses into block bodies. It is `crashmin.jl`'s loop lifted into
  `shrink.jl`, moved from line to statement granularity, and `crashmin.jl` now
  drives it too (with "the subprocess died by signal" as the property, and its
  line-based loop kept as the fallback for a candidate that will not parse).
- **Budget and bypass.** `ShrinkBudget` caps re-executions and wall clock per
  finding, so one stubborn case cannot stall a campaign; `--noshrink` skips
  shrinking on every axis, `--shrinkruns`/`--shrinksecs` move the caps.

Left open: the corpus predicate re-runs a fragment that real code may make
nondeterministic, so a flaky corpus finding can shrink to less than its true
minimum (or not at all). Item 1's confirm-on-divergence gate and item 5's
per-fragment determinism certification are the fix; until then the budget
bounds the damage.

### 4. Replace `BUILTIN_PROBES` with a reflection-driven prober — **DONE**

Landed as `fuzz/src/probes.jl`; the 76 verbatim strings are gone. The prober
enumerates every builtin-valued name in `names(Core; all=true)`, every
`names(Core.Intrinsics; all=true)` intrinsic and the Base-level entry points
that are builtins on some versions — 269 spellings on 1.11.9, 210 of them
probeable — takes arities from the same `T_FFUNC_VAL`/`T_IFUNC` tables
`bin/generate_builtins.jl` uses, and draws arguments from the TySum-directed
generator, so probes finally see generated structs, vectors, closures, atomic
orderings and symbols. Curated knowledge is now three tables: `PROBE_BANS`
(safety, reason string per entry), `PROBE_RECIPES` (~120 argument shapes over
43 builtins, so probes reach success paths and not only the error arms) and
`FIXED_PROBES` (the templates that are not a plain `callee(args...)` call).
`metrics.jl` reports enumerated/allowed/denylisted counts plus probe density
and callable coverage under the `builtins` policy; the selftest asserts an
enumeration floor, that no denylisted callee is ever rendered, that a
probe-heavy batch executes without killing the worker, and that recipe'd
probes reach value-returning paths.

What the work turned up, all documented in `DESIGN.md`'s known-classes
section: raw `sdiv_int`/`udiv_int`/`srem_int`/`urem_int` die with SIGILL when
compiled (the `checked_*` family does not — it raises DivideError, so it is
kept); wrong-arity *intrinsic* calls abort inside codegen; the
width-relational casts fail at compile time *outside* the program's `try`;
`apply_type` with a huge Int parameter segfaults; unchecked `MemoryRef`s are
wild reads/writes and `undef` `Memory` reads are nondeterministic; a `Type` in
a module slot (`modifyglobal!`) makes inference fail internally and codegen
emit `unreachable`; `Core._call_latest()`/`Core._apply_pure()` segfault on an
empty argument list. Two genuine but *known-and-deliberate* interpreter
divergences also surfaced (`_apply_iterate` with a non-`iterate` first
argument, `compilerbarrier` with an unknown setting) — both unreachable from
lowered code, both now confined to recipes.

**Optimizer barriers on probe arguments (landed).** Every probe argument is now
wrapped in `Base.compilerbarrier(:const, …)` at render time (`render.jl`, the
`:probe` branch; the exclusion predicate is `probe_arg_mustbeliteral` in
`probes.jl`). The barrier passes the value through unchanged but blocks constant
propagation, so the compiled reference cannot fold the call and defers to the
runtime builtin/intrinsic — matching the interpreter. This closes the
optimization-dependent class-U where the reference folds constant operands to a
*compile-time* error (mismatched-type integer operands, invalid ordering) while
the interpreter reaches the runtime error, and it spares the three-way JI
adjudicator a subprocess for divergences that no longer arise. `:const` is
type-preserving, so valid calls still return their value. Constant-required
slots stay bare — cast-intrinsic target `Type`s, atomic ordering symbols
(`atomic_fence` + the field/global/memoryref families), module refs to the
global-binding builtins, and the `memoryref*` boundscheck flag — a barrier there
would be a new compile-time error or a lost safety guarantee. Because the
reference now defers, the mismatched-operand arm of the numeric intrinsics
(`sametype_intargs`/`sametype_floatargs`) is re-enabled on a fraction of draws:
verified with 286 barriered mismatched calls through `run_both`, 0 divergences.
The selftest asserts (a) a mismatched-type intrinsic agrees under barriers, (b)
200 probe-heavy seeds all lower with 0 constant-required slots barriered, and
(c) a valid recipe'd probe still returns its value.

Closing evidence: 1500 probe-heavy candidates (native engine, `builtins`
policy, both interpreter modes) through a restart-looping subprocess soak with
the journal armed. Three process deaths, all reference-side Julia defects with
no probe involved — two known `llvm-alloc-opt` aborts and one delayed
`gc_mark_obj8` segfault that did not reproduce on replay; two divergences,
both the `invoke` finding above. Generation stayed valid by construction
throughout: 0 parse/lowering failures in 800 seeds × 7 policies, and 0 gate
discards across the soak.

One pre-existing generator bug fell out of this: the mutating-closure rule
decremented `rtscopes` without incrementing it, so everything generated after
a mutating closure believed it was at module toplevel. `while` fuel
decrements then rendered as `global fuel -= 1` for a `let`-local counter,
which does not lower — the parse gate silently discarded 4–8% of *all*
candidates (17/400 at the default policy, 31/400 under `:exceptions`). Fixed;
the rate is now 0/400 on every policy.

### 5. Determinism unlocks, the cheap half (`determinism.md` §9) — **DONE**, ENV/fs doubles deferred

Item 1's confirm-on-divergence gate was the safety net for all three, and it
held: across the calibration campaigns the new grammar produced **zero**
nondeterminism false positives (0 `nondet_discard` attributable to the new
rules). What shipped:

- **Explicit RNG + content-keyed containers** — **done** (`determinism.md`
  §3/§4). An inline SplitMix64 PRNG (`const __LCG__ = Ref{UInt64}(seed)` +
  draw helpers, `render.jl` `rngheader`) is baked into the rendered program
  with a *literal* seed (`Program.rngseed`), identical on both engines, so
  `__randint__()` / `__randrange__(lo, hi)` / `__randbool__()` /
  `__randfloat__()` agree bit-for-bit at a few interpreted statements per draw
  (originally Base `rand` on a `Xoshiro`; replaced after measuring 100%
  statement-budget exhaustion in rec mode). Wired into the Int/Float/Bool expression
  menus and a rand-derived `for` trip count, so data-dependent control flow and
  indices are now generable (termination still by construction — rand never
  feeds while-fuel). `Dict`/`Set` keyed by the content-hashed whitelist
  (Int/String/Symbol/Char/Bool + tuples; new `DictT`/`SetT`/`CharT`): rules for
  construction, `get`/`get!`/`haskey`/`in`/`length`, `setindex!`/`delete!`/
  `push!`, and `keys`/`values`/whole/`length` observations, all under the full
  value oracle (iteration order included; `__fjnorm__` sorts normalized
  contents). Gated by the `:rng`/`:dict` swarm features and a new
  `:determinism` policy. Densities under `--policy determinism`: rng 67%,
  vtime 42%, dict ~50% of programs; blended rng 66%, dict 27%, vtime 34%.
- **Corpus self-agreement certification** — **done** (`determinism.md` §6,
  `corpus.jl`). Before the failure-mode oracle, each case is certified: seed the
  sandbox RNG, run the fragment under `Core.eval` twice, auto-observe its
  comparable top-level bindings (real fragments don't call `__obs__`), and
  compare the streams. Agreement graduates the fragment to the full differential
  value oracle (classify + confirm gate + fingerprint/dedup/shrink/report);
  disagreement falls back to today's failure-mode + stepping oracle. A
  `certified` counter is printed next to `ran`/`discarded_junk`. Measured
  certification rate ~60% of runnable cases; seeded-`rand` fragments certify and
  become value-compared (the §6 headline), while `objectid`/clock fragments
  correctly fail self-agreement and fall back.
- **Virtual doubles** — **`__vtime__` done**, `__venv__`/`__vfs__` **deferred**.
  `__vtime__()` (monotone counter in `SETUP_SRC`) is in the Int menu, so
  deadline/elapsed-shaped control flow (`while __vtime__() < N`) is generable.
  The ENV/fs doubles and the handle/`do`-block/`try-finally` grammar rules they
  unlock, plus curated deterministic `ccall`s, are **not built** — they are the
  larger, optional half and only pay off once the resource-idiom rules that
  consume them exist. Pick this up next: `__venv__::Dict{String,String}` and a
  `__vfs__` (`__open__`/`__read__`/`__write__`/`__close__`) in `SETUP_SRC`
  raising the real exception types (`SystemError`/`EOFError`), then
  `open(...) do`/`try…finally close(h)` templates in `rules.jl`.

### 6. An `ExprSplitter` axis (P3 item 13) — **done**

`--engine split`, `fuzz/src/splitfuzz.jl`; see DESIGN.md's section for the
shape of it. A template-combinator generator (not the IR grammar) emits
adversarial toplevel forms — nested `module`/`baremodule`, unsplittable
`begin`/`let`/`try` blocks, toplevel macros expanding to `:block`,
`Expr(:toplevel, ...)`, a bare `global`, or a whole `module`, docstrings
(including a module docstring interpolating a binding its own body defines),
`const`/`global`/typed-global in odd positions, `;`-separated toplevel lines,
cross-module references, `export`/`public`/`using .M`, name shadowing in
nested modules, and empty/comment-only sections. The oracle is differential
against `Core.eval` on three things: failure mode, observation stream, and the
**module tree** — every name defined in the root module and recursively in the
submodules the program created, values normalized `__fjnorm__`-style. That
third one is the point: these programs mostly define rather than compute, so a
definition the interpreted path silently skipped is invisible to an
observation-stream oracle.

Calibration: ~14 000 cases on the final generator run clean (8000 through the
CLI plus 5000 offline, no findings, 0 discards, 0 aborts, ~20 cases/s, mean
12 fragments and 11 compared names per case). A mutation test — drop one
`ExprSplitter` fragment on the interpreted side — is caught 86% of the time
(66% `split_missing_effect`, 20% `split_internal_error`), which is what says
the oracle has teeth rather than the axis being vacuous. Two legitimate
divergences were found and designed out of the generator rather than
suppressed; one more (module creation runs *one fragment ahead*, so a module
after a throwing statement exists on the interpreted side only) is why module
state is not compared on the throwing path. All three are documented at their
constants in `splitfuzz.jl`.

Since closed for this axis: **Compiled-mode runs** (every case now runs the
interpreted side in both `:rec` and `:cmp` against one shared reference —
see `split_campaign`'s docstring for why run-both beat a per-case draw) and
**`Base.__toplevel__` as the parent module** — a gated quarter of cases
(`SPLIT_TL_FRACTION`) now reaches `find_or_create_module`'s package-resolution
arm (`find_toplevel_module_id`, `Base.loaded_modules`), previously untested by
any axis. The isolation contract (process-unique per-run wrapper names,
side-tagged, `FJTL`-prefixed, unregistered after each run) is documented at
`TL_PLACEHOLDER` in splitfuzz.jl; the third known-legitimate divergence
(reuse-vs-replace) exists at process scope there too and is designed out the
same way — unique names — with the reproducer testset keeping a fixture of it.
Calibration after the extension: 6000 cases (4000 campaign-mix at the 25%
`__toplevel__` fraction + 2000 forced-`__toplevel__`), both modes each, zero
findings, zero discards. Still not done: shrinking (writes
`original == shrunk`, see item 3).

Ordering between items 4–5 is soft. Item 5 has the strongest
breadth-of-tested-code argument. A session should pick by which question it
is trying to answer.

### 7. A nightly CI job — **DONE**

`.github/workflows/fuzz-nightly.yml`: cron + `workflow_dispatch(duration_seconds)`,
Julia 1.12 (required) and `pre` (continue-on-error) lanes, the selftest as a
support gate before any campaign runs, `longrun.sh` time-boxed, findings and
crash journals uploaded as artifacts, red on new findings.

### 8. Throughput — **partially done**, see `throughput-report.md`

The `native` axis runs ~2 cases/s and it multiplies everything. The cost is
three fresh modules per candidate, re-lowering on the interpreted side, and
the reference JIT-compiling every generated function from scratch. Module
pooling and skipping the double lowering are the obvious wins.

Ranked here rather than higher because it makes a *low-bug-density* surface
faster. Raising the rate on the axes in items 2–6 is worth more. (Item 5's
extra reference runs barely move this: confirm-on-divergence only pays on
divergences, and the corpus certification run is compiled-side, the cheap
side.)

### Long-horizon, in one place

- **Coverage stage two** — corpus admission + choice-sequence
  mutation/splicing over the `TCRNG` substrate (item 2's second half).
- **EMI — equivalence modulo inputs (P4).** Profile which statements execute
  on a given input (nearly free, the interpreter is instrumentable in pure
  Julia), mutate code that is dead on that input, and require
  `interp(P) == interp(P′)`. A second oracle orthogonal to
  compiled-vs-interpreted. Biggest lift of anything here.
- **Determinism taint + relation observations** (`determinism.md` §5): a
  `det` bit in `TySum`; tainted values (`objectid`, pointers, `gensym`)
  observed as *relations* rather than values — identity semantics becomes
  testable while the values never compare.
- **Schedule-invariant task subset** (`determinism.md` §7): `@sync`/`@async`
  with observables independent of interleaving by construction — sound with
  no determinization infrastructure at all.
- **LLM-seeded corpus**: generality without rule-authoring; the
  certification gate decides what is admitted, so the oracle stack doesn't
  care about provenance.
- **Explicit non-item: whole-system deterministic execution**
  (Antithesis/Hermit-style hypervisors). Wrong layer for a two-engine
  oracle — determinism is not agreement; see `determinism.md` §2. rr for
  crash repro (item 1) is the part of that toolbox worth having.
- **Corpus environment-equivalence gate** (port from the parallel session's
  `claude/julia-fuzzing-strategy-bmh692`, commit `be1d869`). That session's
  corpus axis discards a case when the *interpreted* module's environment
  (which prelude `using`/`import`s actually took effect) differs from the
  environment the reference succeeded in — otherwise "compiled ran it, interp
  threw `UndefVarError: @testset`" is a statement about the harness's setup,
  not about JuliaInterpreter. This branch instead prevents `LOAD_PATH`
  corruption at the source (`freshmodule` restores the harness load path) and
  certifies determinism; the environment-equivalence check is complementary
  and more general (it catches any environment mismatch, not just load-path
  ones). Not cherry-pickable directly: their `corpus.jl` predates this
  branch's certification + `LOAD_PATH` changes, so it needs hand-porting into
  `corpusmodule`/the corpus runners (have `corpusmodule` report which prelude
  statements took effect; discard when the interp and ref environments
  diverge). Deferred deliberately — the `LOAD_PATH` fix already closed the
  crash it was chasing; this hardens the remaining false-positive surface.

### Still-open grammar gaps

From earlier waves, never closed: destructuring, `do` blocks, `@generated`
functions, parametric structs, inner constructors, defaults referencing
earlier parameters.

Item 2 now answers which of them matter, and the answer is in
`coverage-report.md`'s last table rather than in this list: **destructuring**,
**`@generated`** and **keyword sorters** each leave a specific interpreter
function with zero executed lines, **`do` blocks** have no distinct
interpreter surface to leave cold, and **parametric structs / inner
constructors** are mostly already reached by other constructs (all the
`Core._structtype`/`_typevar`/`apply_type` arms are hit) — so that one buys
new inputs rather than new paths. Re-run `fuzz/coverage.jl` after closing any
of them: the report is the regression check.

---

## Lessons that will save you time

**A new axis's first reports are about the axis, not about the interpreter.**
Of the stepping axis's first six reports, five were miscalibrations of my own
oracle and one was a generator bug. Budget for calibration before believing
any yield number. The specific traps, all of which cost real time:

- **World age.** The prelude and any method the program defines at runtime are
  newer than the world the harness function was compiled in. `debug_command`
  has no toplevel loop, so the *caller* must refresh `frame.world`;
  `ExprSplitter`/`Frame` expand macros at construction, so they need
  `Base.invokelatest`. Symptom: "the interpreter threw UndefVarError: @testset"
  where compiled Julia was fine.
- **"The backtrace mentions JuliaInterpreter" does not mean it is an
  interpreter bug.** A program-thrown exception unwinds through interpreter
  frames too. Decide by comparing against plain interpretation of the same
  program, never by the backtrace.
- **Soft scope.** A `while` or `for` body at module toplevel is a soft scope,
  so a bare assignment there declares a *new local* and reads it before
  assignment. This bit the generator's fuel counters twice, and then bit
  `crashmin.jl`'s own ddmin loop. Track *runtime* scopes (`rtscopes`), not
  generation scopes — `if` is transparent, `let`/`for`/`while`/`try` are not.
- **Unassigned array slots are not the same as missing ones.** `push!` grows
  then stores; an interpretation that stops in between leaves a live element
  that was never written. Reading it is sometimes `UndefRefError` and
  sometimes a segfault.
- **Budget exhaustion is not a hang, and a breakpoint pause is not a stuck
  command.** Both were reportable classes at first and both were pure false
  positives. Measure the actual property — for "stuck", that a command leaves
  `(framecode, pc)` unchanged repeatedly *while returning a normal pc*.

**Check whether a finding is already fixed upstream before minimizing it.**
`julia --project=fuzz fuzz/triage.jl <finding>` is now that check, and it also
tells you which side broke. Run it first, always. See item 1.

**Verify a new axis actually exercises something.** A clean run and a run that
silently tests nothing look identical in the stats. Every axis was checked
explicitly: eval_code performs ~1076 checks across 56 distinct variables per
20 programs; corpus executes ~50% of cases and reports `ran` next to
`discarded_junk` precisely so a collapse to zero is visible.

**The cheapest way to prove an oracle has teeth is to break the SUT on
purpose.** The split axis reported nothing on its first several thousand cases,
which is indistinguishable from an oracle that cannot fail. So: copy the
interpreted-side driver, have the copy *skip one `ExprSplitter` fragment*, and
re-classify. 86% of those mutants are caught (66% as `split_missing_effect`,
20% as an internal error); the 14% that pass are fragments whose omission has
no observable effect — comments, empty modules, the docstring binding, which
is excluded as compiler-internal. Fifteen minutes of work, and it converts
"clean run" from a worry into a measurement. The mutant driver lives outside
the repo (it is a probe, not a feature), but the technique transfers to every
axis here.

**Normalization gaps hide in the *rare* observation branches.** `__fjnorm__`
had scrubbed module identity everywhere except `x isa Type`, where it used
`string(T)` — which is module-qualified, so a type the program defined read as
`Main.FJ95.ZT` against `Main.FJ96.ZT`. Four axes never hit it because they
never observe a bare type; the split axis emitted `__obs__(M1.A5)` and produced
16 false divergences in 5000 cases. When adding a template that observes a new
*kind* of value, check the normalizer's branch for it first.

---

## Running things

```sh
julia --project=fuzz fuzz/run.jl --selftest              # 372 assertions, ~2min
julia --project=fuzz fuzz/metrics.jl --n 500             # what the generator produces
julia --project=fuzz fuzz/coverage.jl --n 20             # what a campaign reaches (smoke)
julia --project=fuzz fuzz/coverage.jl --n 400 --shards 2 \
      --engine native,step,evalcode,corpus --modes rec,cmp --slowdown   # the real thing, ~30 min
julia --project=fuzz fuzz/run.jl --engine step --n 2000
julia --project=fuzz fuzz/run.jl --engine evalcode --n 1000
julia --project=fuzz fuzz/run.jl --engine corpus --n 1000
julia --project=fuzz fuzz/run.jl --engine split --n 5000  # ~19 cases/s
./fuzz/longrun.sh 21600                                  # all axes, sharded, 6h
./fuzz/preserve-findings.sh                              # commit findings/ (gitignored)
```

**Triage anything that lands in `findings/` before you work on it:**

```sh
julia --project=fuzz fuzz/triage.jl fuzz/findings/<dir>/     # writes triage.md there too
julia --project=fuzz fuzz/triage.jl fuzz/journal/current.jl  # or a bare candidate
```

It attributes the failure to a side by running each one alone in its own
`julia` (exit status, not backtrace contents), and re-runs a broken *reference*
side under `julia +release` so "already fixed upstream" is answered before
anyone minimizes anything. Flags: `--timeout SECS`, `--mode rec|cmp` (override
the mode recovered from the repro), `--channel CHAN` (juliaup channel to check
against, default `release`), `--nowrite` (don't write `triage.md`).

Useful flags: `--big` (larger programs), `--fresh` (ignore existing findings
when seeding dedup — otherwise a reported bucket masks new ones),
`--policy NAME` on `metrics.jl` (measure one generation policy in isolation),
`--journaldir` (required when running shards concurrently), `--noshrink` /
`--shrinkruns N` / `--shrinksecs S` (skip or re-budget minimization; findings
are shrunk on every axis by default), `--keep` + `--reuse` on `coverage.jl`
(re-report from the `.cov` files a previous run left behind, without
re-running the campaign).

Run the selftest after any generator change. It is not a formality: it caught
a generator bug this session that had raised smoke divergences from ≤5 to 13.
