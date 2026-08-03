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

## Where things stand

Five axes exist. Four of them cover surfaces that had no systematic testing
before.

| engine | what it tests | oracle |
|---|---|---|
| `native` / `supposition` | run-to-completion semantics | differential vs. compiled Julia, on observation streams |
| `step` | `debug_command` walks — `commands.jl`, `breakpoints.jl` | stepping terminates, raises nothing plain interpretation doesn't, and reaches the same observations |
| `evalcode` | `eval_code` at paused frames — `utils.jl` | reads match `locals(frame)`; writes round-trip and don't disturb other locals |
| `corpus` | real Julia source, spliced — `construct.jl`, macro-heavy paths | differential on *failure mode only* (never on values) |
| `split` | adversarial toplevel forms — `ExprSplitter` in `construct.jl` | differential vs. `Core.eval` on failure mode, observation stream, **and the resulting module tree** |

Supporting tools: `metrics.jl` (what the generator actually produces, without
executing), `coverage.jl` (what a campaign actually *reaches* inside
`src/` — line coverage of the interpreter, mapped onto builtin dispatch arms
and functions; report in `coverage-report.md`), `longrun.sh` (sharded
restart-looping campaigns), `crashmin.jl` (minimize a program that kills the
process), `triage.jl` (which side broke, and does it still break on the
newest Julia), `diag_stuck.jl` (why a stepping walk is stuck),
`preserve-findings.sh` (force-commit findings, since `findings/` is
gitignored).

**Results so far: one JuliaInterpreter bug, found late and cheaply.** The
differential axis in `cmp` mode (compiled mode) diverges on `rethrow()`,
`rethrow(exc)` and `current_exceptions()` inside an interpreted `catch`: the
interception that answers them from the frame's modelled exception stack sits
on the generic `evaluate_call!`, and `NonRecursiveInterpreter` overrides
exactly that method with a `native_call` bypass. Eight-line reproducer and a
fix sketch in `findings/cmp-exception_divergence-61051b0f/`. Everything else
the work produced:

- four generator bugs and five harness bugs, several of which were silently
  destroying yield (see the lessons below) — the newest being `__fjnorm__`
  observing a type by its *module-qualified* name, found by the split axis;
- one genuine Julia compiler crash, which turned out to be a known 1.11
  regression already fixed in 1.12 (`findings/julia-codegen-abort-allocopt/`).
  It still bites: it aborts the *process*, so a shard that hits it writes no
  coverage data at all (`coverage.jl` reports such shards explicitly).

One bug in ~10^4 candidates is not a yield estimate. The axes have not run at
the scale where they would be expected to produce much — the literature's
numbers are 10^8 and up, these runs are 10^3–10^4.

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

### 4. Replace `BUILTIN_PROBES` with a reflection-driven prober

The 76 verbatim probe strings cover ~23 distinct builtins and never receive
generated values. Meanwhile `src/builtins.jl` special-cases **79 builtins
across 44 dispatch arms** — and that file is itself *generated* by
`bin/generate_builtins.jl`, which enumerates every `Core.Builtin` by
reflection. The fuzzer should consume the same enumeration: for each builtin
and intrinsic, generate guarded calls with an arity sweep (0 through n+1)
and arguments drawn from the TySum-directed generator — a mix of
type-plausible and deliberately wrong — so probes finally see generated
structs, vectors, closures and atomic orderings. Hand-curated knowledge
shrinks from "author every probe" to an exceptions table of roughly a dozen
entries: the SIGFPE intrinsics (`sdiv_int` on zero), unspecified-value
contracts (out-of-range `unsafe_trunc`, fptosi of NaN — `determinism.md`
§1's class U), and anything else whose contract says "unspecified". This
scales across Julia versions automatically and turns item 2's never-hit-arm
report into a to-do list the generator can act on.

### 5. Determinism unlocks, the cheap half (`determinism.md` §9)

Item 1's confirm-on-divergence gate is the safety net for all three, and it is
now in place — a determinism mistake in any of these lands as a tracked
`nondet_discard`, not as a false finding. In order:

- **Explicit RNG + content-keyed containers.** `__RNG__ = Xoshiro(seed)` in
  the prelude, with `rand`/`randn`/`shuffle!` rules drawing from it — both
  sides execute the same generator code, so streams agree bit-for-bit.
  Unlocks data-dependent control flow and indices, which every guarded rule
  currently lacks. Plus `Dict`/`Set` keyed by content-hashed types
  (Int/String/Symbol/Char and immutable combinations): already
  deterministic cross-engine, iteration order included, and the
  associative-container and iteration-protocol paths are untested today.
- **Corpus self-agreement certification.** The corpus axis demotes *all*
  real code to the failure-mode oracle because real code is "not
  deterministic" — but that property is per-fragment and measurable. Seed
  the sandbox RNG before every run, run the compiled reference **twice**;
  if it agrees with itself, the fragment is certified observationally
  deterministic and graduates to the full differential value oracle
  (`classify` applies unchanged). The single largest step toward testing
  real-world code. Track the certification rate next to
  `ran`/`discarded_junk` so a collapse is visible.
- **Virtual doubles.** `__vtime__` (monotone counter), `__venv__` (Dict
  double of ENV), `__vfs__` (Dict-backed pseudo-files) in `SETUP_SRC`,
  raising the real exception types so guarded observations stay meaningful.
  The point is not I/O — it is that resource-handle idioms
  (`open(...) do`, `try ... finally close(h)`) become generable, and those
  are the closure + `finally` + early-exit compositions wave 3 exists to
  stress. Curated deterministic `ccall`s (`strlen`/`memcmp`/libm on
  generated values) for the `:foreigncall` conversion path ride along.

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

Not done for this axis: shrinking (writes `original == shrunk`, see item 3),
Compiled-mode (`NonRecursiveInterpreter`) runs, and `Base.__toplevel__` as the
parent module — `find_or_create_module`'s package-resolution arm
(`find_toplevel_module_id`, `Base.loaded_modules`) is only reachable from
there and is still untested by any axis.

Ordering between items 4–5 is soft. Item 5 has the strongest
breadth-of-tested-code argument. A session should pick by which question it
is trying to answer.

### 7. A nightly CI job

Time-boxed, uploads `findings/` as artifacts, exits 2 on news. Mentioned in
the roadmap, never built. Item 1 has landed, which was the precondition —
unattended runs are only as useful as the trustworthiness of what they report,
and what they report is now confirmed before it is written.

### 8. Throughput

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
julia --project=fuzz fuzz/run.jl --selftest              # 253 assertions, ~75s
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
<<<<<<< HEAD
`--journaldir` (required when running shards concurrently), `--noshrink` /
`--shrinkruns N` / `--shrinksecs S` (skip or re-budget minimization; findings
are shrunk on every axis by default).
=======
`--journaldir` (required when running shards concurrently), `--keep` +
`--reuse` on `coverage.jl` (re-report from the `.cov` files a previous run
left behind, without re-running the campaign).
>>>>>>> worktree-agent-a0222a76b16352ee3

Run the selftest after any generator change. It is not a formality: it caught
a generator bug this session that had raised smoke divergences from ≤5 to 13.
