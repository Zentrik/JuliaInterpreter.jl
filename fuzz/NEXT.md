# FuzzJI: state of play and what to do next

Handoff document. Read `DESIGN.md` for how the harness works and
`yield-analysis.md` for why it is built this way; this file is the short
version of *where things stand* and *what to pick up*.

Last updated after the session that added the stepping, eval_code and corpus
axes.

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
(minimize a program that kills the process), `diag_stuck.jl` (why a stepping
walk is stuck), `preserve-findings.sh` (force-commit findings, since
`findings/` is gitignored).

**Results so far: one JuliaInterpreter bug, found and fixed.**

`rethrow()` inside a `catch` block failed under `NonRecursiveInterpreter` with
*"rethrow() not allowed outside a catch block"*, where compiled Julia and
`RecursiveInterpreter` both rethrow correctly. Reproduces on 1.11.9 and
1.12.6. Cause: interpreted catch handlers never populate the task's native
exception stack — frames model active exceptions themselves — so
`evaluate_call!` intercepts `Base.rethrow` and answers from that model, but
compiled mode's method went straight to `native_call` and skipped the
interception. `Base.current_exceptions` had the same hole. Fixed in
`evaluate_stateful_call!`, shared by both interpreters (commit `7cb0715`).

The campaign that found it also produced:

- four generator bugs and five harness bugs, several silently destroying yield
  (see the lessons below);
- one genuine Julia compiler crash, which turned out to be a known 1.11
  regression already fixed in 1.12
  (`findings/julia-codegen-abort-allocopt/`).

One interpreter bug in ~10^4 cases is a real result but a thin one, and the
axes still have not run at the scale where they would be expected to produce
much — the literature's numbers are 10^8 and up.

---

## Work items, ranked

### 1. Version-aware triage of reference-side crashes

Small, and it directly fixes a hole that cost a lot of time.

Today a crash on the **reference** side (compiled Julia) lands in the same
`findings/` bucket as an interpreter divergence, and nothing checks whether it
still reproduces on current Julia. Both matter:

- A reference-side crash is a *Julia* bug, not a JuliaInterpreter bug. Classify
  and route it separately — different verdict class, different directory.
- Before reporting one, re-run it under the newest installed Julia
  (`juliaup` makes `julia +1.12 file.jl` a one-liner). If it passes there, say
  so in the report.

The whole codegen-crash episode — journal replay, minimization, C-Reduce, a
delegated reduction agent — was work on a bug fixed a release earlier, and one
version check up front would have answered it.

### 1b. Compare exception payloads, not just type names

Cheap, and the `rethrow` bug is the argument for it. That bug broke *every*
`rethrow()` in compiled mode, but the oracle only saw the cases whose original
exception was not an `ErrorException` — because the interpreter's own failure
mode is `ErrorException: rethrow() not allowed outside a catch block`, and
`classify` compares exception *type names* only. The `error("boom")` variant
reads as agreement. The fuzzer found this despite the oracle, not because of
it.

Messages were excluded deliberately (they drift across Julia versions), which
is right, but the current rule throws away too much. Compare the fields that
are contract, not prose: `MethodError.f` and `.args`, `BoundsError.a`/`.i`,
`UndefVarError.var`, `TypeError.func`/`.expected`/`.got`,
`ArgumentError`/`ErrorException` message text behind a flag. Expect a wave of
recalibration when this lands — several currently-agreeing cases will start
diverging, and the first ones will be harness artifacts as usual.

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
  question that actually matters.
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

Close this before the next long unattended run, not after.

### 4. An `ExprSplitter` axis (P3 item 13)

`construct.jl` has the densest fix history in the package (9 commits) and is
still only exercised incidentally. A dedicated axis would feed it adversarial
toplevel forms directly: nested `module` blocks, `baremodule`, bare `begin`
blocks, toplevel macros that expand to multiple statements, `const` and
global declarations in odd positions, scope blocks that cannot be split.
Oracle: the sequence of `(mod, frag)` pairs is consistent with what
`Core.eval` does with the same source, and no internal error.

### 5. Throughput

The `native` axis runs ~2 cases/s and it multiplies everything. The cost is
three fresh modules per candidate, re-lowering on the interpreted side, and
the reference JIT-compiling every generated function from scratch. Module
pooling and skipping the double lowering are the obvious wins.

Ranked here rather than higher because it makes a *low-bug-density* surface
faster. Raising the rate on the axes in items 2–4 is worth more.

### 6. EMI — equivalence modulo inputs (P4)

Profile which statements execute on a given input (nearly free, the
interpreter is instrumentable in pure Julia), mutate code that is dead on that
input, and require `interp(P) == interp(P′)`. A second oracle orthogonal to
compiled-vs-interpreted. Biggest lift of anything here.

### 7. A nightly CI job

Time-boxed, uploads `findings/` as artifacts, exits 2 on news. Mentioned in
the roadmap, never built.

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
- **A differential oracle must check that both sides ran in the same
  environment.** The corpus axis compared a reference module that had the
  fragment's imports applied against an interpreted module that did not, and
  reported the difference as an interpreter bug. It now records which prelude
  statements actually took effect and discards the case when the two disagree.
  Whether an import succeeds is genuinely not a given: a lifted
  `using .Main.OffsetArrays` names a module that does not exist in the harness.
- **Do not swallow setup failures silently.** That same bug was invisible for
  as long as it was, because `corpusmodule` caught and ignored failed prelude
  statements. A `try`/`catch` around environment setup should record what
  failed, not just carry on.
- **Re-verify a fix under the parameters that produced the report.** A first
  attempt at the above looked fixed because the check ran with the default
  `--maxsplice 3` while the campaign uses `4`, and the splice count changes
  which fragments a seed selects. Same seed, different program.

**Check whether a finding is already fixed upstream before minimizing it.**
See item 1.

**Verify a new axis actually exercises something.** A clean run and a run that
silently tests nothing look identical in the stats. Both new axes were checked
explicitly: eval_code performs ~1076 checks across 56 distinct variables per
20 programs; corpus executes ~50% of cases and reports `ran` next to
`discarded_junk` precisely so a collapse to zero is visible.

---

## Running things

```sh
julia --project=fuzz fuzz/run.jl --selftest              # 108 assertions, ~40s
julia --project=fuzz fuzz/metrics.jl --n 500             # what the generator produces
julia --project=fuzz fuzz/run.jl --engine step --n 2000
julia --project=fuzz fuzz/run.jl --engine evalcode --n 1000
julia --project=fuzz fuzz/run.jl --engine corpus --n 1000
./fuzz/longrun.sh 21600                                  # all axes, sharded, 6h
./fuzz/preserve-findings.sh                              # commit findings/ (gitignored)
```

Useful flags: `--big` (larger programs), `--fresh` (ignore existing findings
when seeding dedup — otherwise a reported bucket masks new ones),
`--policy NAME` on `metrics.jl` (measure one generation policy in isolation),
`--journaldir` (required when running shards concurrently).

Run the selftest after any generator change. It is not a formality: it caught
a generator bug this session that had raised smoke divergences from ≤5 to 13.
