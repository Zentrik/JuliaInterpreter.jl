# Bug-history mutant benchmark

Recommendation 4 of `evaluation-2026-08-03.md`, made runnable: revert a real
historical fix commit, point each fuzzing axis at the resulting mutant, and
measure whether the axis rediscovers the bug — and at what n. An axis that
cannot rediscover a *known* bug at 10^4 will not find an unknown one at 10^4,
so this converts "which axes deserve compute" from opinion into measurement.

Tool: `fuzz/mutantbench.sh` (see its header for mechanics). Raw rows accrue in
`fuzz/mutantbench-results.tsv`; the matrix below the marker is regenerated from
it on every run. Findings produced by mutant runs describe **already-fixed
bugs** — they stay in the temp worktree (preserved under the run's tmpdir as
`evidence/`) and are never committed.

## Curated mutant list

All SHAs are ancestors of this branch's HEAD (the clone was unshallowed to
full history, 1090 commits). "Expected detector" is the axis whose surface the
fix belongs to — the benchmark's null hypothesis is that at least that axis
can re-find the bug.

| fix commit | description | expected detector | revert at HEAD | notes |
|---|---|---|---|---|
| 1e52e3e | Preserve module self-bindings during resolution (#758) | split | clean (construct.jl) | module-tree oracle territory |
| 7194542 | improve stepping behavior (#760) | step | **conflict, skipped** | later commands.jl churn (#759 among others) overlaps its hunks |
| 43f72e9 | reenable global ref lookup optimization (#759) | — | clean | **no semantic mutant, skipped**: the revert restores the previously-correct no-fold state (optimization off), so the mutant is slower, not wrong |
| 4eea2e9 | optimize frame recycle tracking (#761) | — | clean | **no semantic mutant, skipped**: pure representation change (`IdSet` membership → `Frame.pooled` flag) with identical idempotency semantics |
| 76605f6 | Enforce invoke argument-type conformance in the interpreter | native (builtins probes) | clean (interpret.jl) | |
| f81ef27 | Defer malformed Core.invoke to native invoke for the right exception | native (builtins probes) | **conflict, skipped** | 76605f6 rewrote the same lines |
| a6c8f0b | Defer malformed Core.invokelatest to native for the right exception | native (builtins probes) | **conflict, skipped** | beeb4b0 rewrote the same lines |
| beeb4b0 | Fix rec-mode _call_latest/invokelatest on a non-callable first argument | native `--modes rec` | clean (builtins.jl) | originally found by a ~100-batch campaign; small-n rediscovery is the open question |
| a3eabb3 | Fix a debugger crash (whereis returning nothing in more_calls_on_current_line) | step | clean (commands.jl, src/ half only) | mixed commit — also touches fuzz/; the tool restores fuzz/ to HEAD for every mutant |
| 94cc282 | Intercept rethrow/current_exceptions in Compiled mode too | native `--modes cmp` | clean (interpret.jl) | |
| 73d94c4 | Make next_line! stop on assignment-only lines | step | clean textually — **semantically inconsistent** | the revert removes `is_next_line_stop`, which a later commit's exception-retry path (commands.jl:751) still calls; the step axis "detects" the resulting internal `UndefVarError`, i.e. a revert artifact, not the historical bug. See pilot notes. |
| 95cc23c | Unwind exceptions to caller-frame handlers in finish_stack! | step | clean (commands.jl) | older classic |
| 2cd2b4a | Fix ExprSplitter re-yielding the parent block after an unsplittable scope-block | split | **conflict, skipped** | construct.jl churn |
| d14d9e1 | Make an empty vararg visible to locals() and eval_code | evalcode | **conflict, skipped** | utils.jl churn |
| 94bb46d | Fix eval_code writing static parameters back to the wrong slots | evalcode | **conflict, skipped** | utils.jl churn |

Revert cleanliness was measured (dry-run `git revert --no-commit` per SHA at
HEAD, conflicts aborted, not resolved). A wider sweep over the older
eval_code/stepping/ExprSplitter fixes (9787c63, beb61fb, 0d2c4a7, d8c19b5,
44c31dd, 9cd7c54, 6015413, 56fd40b, 6304df5, fb2a799, b1b0696, 932f0d7,
720d51a, 294eafe, eb74e8a, 7265afe) found **every one of them conflicting** —
these fixes stack on one another in utils.jl/commands.jl/construct.jl, so
single-commit reverts do not compose with HEAD. Net effect: **no
clean-reverting evalcode mutant exists**; the runnable matrix is 6 valid
mutants — split (1), native (1), native-rec (1), native-cmp (1), step (2) —
plus 73d94c4, which reverts cleanly but turned out to be a revert artifact
(see its row and the pilot notes).

## Pilot results (2026-08-03)

Budgeted pilot proving the harness end-to-end; deliberately small n, and a
non-detection at these n is recorded as a result, not retried until it turns
positive. Commands (as finally run — the step pair was re-run once after two
harness bugs in the *benchmark tool itself* were fixed, see "tool
calibration" below):

```sh
fuzz/mutantbench.sh --n 500 --axes native-rec beeb4b0
fuzz/mutantbench.sh --n 300 --axes step a3eabb3 7194542 73d94c4
```

What the matrix below says, mutant by mutant (Julia 1.12.6, defaults, seed
1000000, `--fresh --noshrink --nosync`):

- **a3eabb3 → REDISCOVERED at n=300** (143 s wall for the campaign, ~2.1
  cases/s). The step axis re-found the `more_calls_on_current_line` /
  `whereis`-returns-`nothing` crash and wrote it to the *same
  class+fingerprint bucket* as the historical finding
  (`step-step_only_throw-88d4b5b2`): same `MethodError` from the reverted
  guard at commands.jl:570, fresh seed (1000238) and walk seed. The stepping
  oracle demonstrably has teeth against its one historical crash class, at
  small n.
- **7194542 → revert-conflict, skipped.** Later commands.jl churn (#759 and
  the subsequent stepping fixes) overlaps its hunks; per policy conflicts are
  recorded, not resolved.
- **73d94c4 → detected at n=300 (131 s), but as a revert artifact, not the
  historical bug.** The finding (`step-step_only_throw-bd46d40d`, first hit at
  candidate seed 1000010, then 7 duplicates in 300 cases) is
  `UndefVarError: is_next_line_stop not defined in JuliaInterpreter` — the
  revert removed that helper while a later commit's exception-retry path
  still calls it. The mutant is textually clean but semantically
  inconsistent, so this row measures "the axis notices a broken interpreter
  fast" (true, and worth knowing) rather than bug rediscovery. Scored as
  *invalid mutant* for yield-calibration purposes.
- **beeb4b0 → NOT detected at n=500** (236 s, ~2.1 cases/s, native engine,
  `--modes rec`, 0 findings; 140 agreed, 359 aborted — the abort share is
  budget-exhausted candidates, so the effectively-compared volume is nearer
  140 than 500, which weakens even this bound). This is the
  honest headline result: the bug was originally found by the multi-hour
  large-scale campaign (~100 batches across six axes), and n=500 with the
  default policy (probe density diluted across all builtins) does not reach
  it. It bounds the per-candidate
  hit rate well below 1/500 under the default policy — consistent with the
  evaluation's Poisson argument that the axes are unmeasured at 10^2–10^3.
  The full-matrix rerun at n=10^4 (commands below the marker) is the actual
  measurement; if 10^4 still misses, the next knob is a probe-heavy
  generation policy — `metrics.jl` has `--policy builtins` but `run.jl`
  exposes no policy flag today, so that knob would first need wiring in.

Tool calibration (in the spirit of "a new axis's first reports are about the
axis"): the pilot's first pass produced two false readings that were fixed
before the numbers above were taken. (1) The temp worktree inherits the
force-committed historical `fuzz/findings/` — including, for a mutant, the
very finding its fix came from under the same bucket name — so finding counts
were inflated and the "first finding" misattributed; the tool now wipes
`fuzz/findings` in the mutant worktree before running axes. (2) A validity
probe (interpret + a trivial `debug_command` walk) was added to catch
semantically-inconsistent reverts; its first version hit the soft-scope trap
documented in NEXT.md's lessons and failed on every mutant. The probe passes
valid mutants now but is necessarily shallow — 73d94c4's artifact sits in the
exception-retry path the trivial walk never reaches, which is why its verdict
above comes from reading the finding, not from the probe.

Pilot compute: ~25 min wall total across the three campaign runs plus
per-mutant env setup (~2 min each).

<!-- mutantbench:matrix -->

_Matrix regenerated 2026-08-03T10:26:50Z from `fuzz/mutantbench-results.tsv`._

| mutant (revert of) | description | native-rec | step |
|---|---|---|---|
| 7194542 | improve stepping behavior (#760) | revert-conflict, skipped | revert-conflict, skipped |
| beeb4b0 | Fix rec-mode _call_latest/invokelatest on a non-callable first argument | not detected@500 (236s) | — |
| a3eabb3 | Fix a debugger crash and remove two Compiled-mode class-X probe sources | — | detected@300 (1: step-step_only_throw-88d4b5b2, 143s) |
| 73d94c4 | Make next_line! stop on assignment-only lines | — | detected@300 (1: step-step_only_throw-bd46d40d, 131s) |

Cells: `detected@N (k: class-fingerprint, secs)` = the axis produced k
finding(s) within N candidates; `not detected@N` = clean run at that n;
`—` = that (mutant, axis) pair has not been run.

Rerun the full matrix (larger n as compute allows; these are the mutants
whose reverts apply cleanly at HEAD *and* are semantically valid — see the
curation table for the conflicting/skipped rest, including 73d94c4,
which reverts cleanly but is a revert artifact, not the historical bug):

```sh
fuzz/mutantbench.sh --n 10000 --axes split 1e52e3e
fuzz/mutantbench.sh --n 10000 --axes step a3eabb3 95cc23c
fuzz/mutantbench.sh --n 10000 --axes native 76605f6
fuzz/mutantbench.sh --n 10000 --axes native-rec beeb4b0
fuzz/mutantbench.sh --n 10000 --axes native-cmp 94cc282
```
