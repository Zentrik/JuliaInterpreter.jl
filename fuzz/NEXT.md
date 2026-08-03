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

Four axes exist. Three of them cover surfaces that had no systematic testing
before.

| engine | what it tests | oracle |
|---|---|---|
| `native` / `supposition` | run-to-completion semantics | differential vs. compiled Julia, on observation streams |
| `step` | `debug_command` walks — `commands.jl`, `breakpoints.jl` | stepping terminates, raises nothing plain interpretation doesn't, and reaches the same observations |
| `evalcode` | `eval_code` at paused frames — `utils.jl` | reads match `locals(frame)`; writes round-trip and don't disturb other locals |
| `corpus` | real Julia source, spliced — `construct.jl`, macro-heavy paths | differential on *failure mode only* (never on values) |

Supporting tools: `metrics.jl` (what the generator actually produces, without
executing), `longrun.sh` (sharded restart-looping campaigns), `crashmin.jl`
(minimize a program that kills the process), `triage.jl` (which side broke, and
does it still break on the newest Julia), `diag_stuck.jl` (why a stepping
walk is stuck), `preserve-findings.sh` (force-commit findings, since
`findings/` is gitignored).

**Results so far: no JuliaInterpreter bug.** Campaigns of hundreds to a few
thousand cases per axis ran clean. What the work did produce:

- four generator bugs and four harness bugs, several of which were silently
  destroying yield (see the lessons below);
- one genuine Julia compiler crash, which turned out to be a known 1.11
  regression already fixed in 1.12 (`findings/julia-codegen-abort-allocopt/`).

Treat "no interpreter bug yet" as an open question, not a conclusion. The
axes have not run at the scale where they would be expected to produce
anything — the literature's numbers are 10^8 and up, these runs are 10^3–10^4.

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

The highest-value item, and still not started. It is the only thing that
replaces guessing about grammar gaps with measurement.

Build a `CoverageInterp <: Interpreter` that records what each candidate
touches: statement heads, which builtin arms in `builtins.jl`, which
`evaluate_call!` paths, whether dispatch went through `localmethtable`. Then:

- **Stage one, offline (a weekend).** Run 10^4 candidates, diff the hit-set
  against the interpreter's reachable surface, and report every arm never hit.
  Each is either a grammar gap or dead code, and either answer is useful. This
  also becomes the regression check for grammar changes — `metrics.jl` shows
  what is *generated*, this would show what is *reached*, which is the
  question that actually matters. It also tells item 4 which dispatch arms
  the prober needs to reach, and which of the still-open grammar gaps below
  actually matter.
- **Stage two.** Feed it back as corpus admission: keep a candidate whose
  choice sequence hit new coverage, mutate and splice from those. The
  Supposition `TCRNG` adapter already makes generation a pure function of a
  choice sequence, so the substrate for this exists.

Do stage one before stage two. It is cheap and it de-risks the rest.

### 3. Shrinking for the step, evalcode and corpus axes

These three write findings **unshrunk** — `writefinding` is handed the same
source twice. So the first real finding on the axes with the best
bug-density argument arrives as a 60-line program with no minimization.

The differential axis's IR shrinker (`shrink.jl`) does not transfer directly:
it re-runs `run_both` and compares fingerprints. Each new axis needs its
property threaded through instead — for `step`, "the same command walk still
diverges/gets stuck"; for `evalcode`, "the same check still fails". Note the
RNG stream matters for `step` (see `diag_stuck.jl`): the walk continues the
same RNG the generator used, so a shrunk program must be replayed the same
way or the command sequence changes.

Close this before the next long unattended run, not after. Item 5's corpus
upgrade raises the stakes: a value oracle on real code will produce its
findings in real-code-sized fragments.

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

### 6. An `ExprSplitter` axis (P3 item 13)

`construct.jl` has the densest fix history in the package (9 commits) and is
still only exercised incidentally. A dedicated axis would feed it adversarial
toplevel forms directly: nested `module` blocks, `baremodule`, bare `begin`
blocks, toplevel macros that expand to multiple statements, `const` and
global declarations in odd positions, scope blocks that cannot be split.
Oracle: the sequence of `(mod, frag)` pairs is consistent with what
`Core.eval` does with the same source, and no internal error.

Ordering between items 4–6 is soft. This one has the strongest pure
bug-density argument (fix history); item 5 has the strongest
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
earlier parameters. Item 2 would tell you which of these actually matter
instead of guessing.

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
silently tests nothing look identical in the stats. Both new axes were checked
explicitly: eval_code performs ~1076 checks across 56 distinct variables per
20 programs; corpus executes ~50% of cases and reports `ran` next to
`discarded_junk` precisely so a collapse to zero is visible.

---

## Running things

```sh
julia --project=fuzz fuzz/run.jl --selftest              # 160 assertions, ~45s
julia --project=fuzz fuzz/metrics.jl --n 500             # what the generator produces
julia --project=fuzz fuzz/run.jl --engine step --n 2000
julia --project=fuzz fuzz/run.jl --engine evalcode --n 1000
julia --project=fuzz fuzz/run.jl --engine corpus --n 1000
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
`--journaldir` (required when running shards concurrently).

Run the selftest after any generator change. It is not a formality: it caught
a generator bug this session that had raised smoke divergences from ≤5 to 13.
