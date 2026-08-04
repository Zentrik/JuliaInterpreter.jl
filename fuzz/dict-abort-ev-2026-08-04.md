# Dict abort-leak: expected-value measurement (2026-08-04)

Question (NEXT.md "The abort leak" bullet / item 5 follow-up): under
RecursiveInterpreter (`:rec`, 300k statement budget) dict/set-containing
programs reportedly abort at ~70% — is testing dicts in rec mode worth the
cost, and at what budget?

**Headline: the documented dict leak no longer exists.** It was measured
before commit `d058cb7` (2026-08-03, "Replace Base-Random `__RNG__` draws
with an inline SplitMix64 PRNG") replaced the Base-rand grammar. The ~70%
dict abort rate was a *confound*: rng draws co-occur in ~2/3 of dict programs
and each Base-rand draw interpreted thousands of statements. Post-fix, dict
programs abort at **0% under the default policy** and **1.9% under the
dict-densest (`:determinism`) policy**, and raising the budget to 600k is
measured to cost **0.0% throughput**.

All measurements on Julia 1.12.6, branch
`claude/false-positive-fussing-improvements-igts2c`, via
`FuzzJI.run_all(src; nstmts, modes)` on rendered `genprogram` /
`genprogram_policy` candidates (same execution path as `fuzz/run.jl`'s
native campaign, single mode per pass). Abort plumbing validated: a
dict-bearing candidate returns `:aborted` at budgets 50 and 3 000, `:done`
at 300 000.

## 1. Baseline: default policy, 180 candidates (seeds 1–180)

Dict/set presence ("`Dict{`/`Set{` in rendered source"): 76/180 (42%).
rng presence ("`__rand` in source"): 125/180 (69%).

| pass | group | n | aborted | abort % |
|---|---|---|---|---|
| rec @300k | all | 180 | 0 | 0.0% |
| rec @300k | dict | 76 | 0 | 0.0% |
| rec @300k | no-dict | 104 | 0 | 0.0% |
| rec @300k | rng (control) | 125 | 0 | 0.0% |
| rec @600k | all | 180 | 0 | 0.0% |
| rec @1M | all | 180 | 0 | 0.0% |
| cmp @300k | all | 180 | 0 | 0.0% |

The rng control confirms the fixed leak stays fixed (was 100% of
rng-bearing programs pre-fix). The dict split shows the same: nothing to
leak at default policy.

## 2. Worst case: `:determinism` policy (dict-dense), 150 candidates

Dict/set presence 105/150 (70%); mean 10.2 dict/set ops per dict program
(vs 6.6 at default policy).

| pass | group | n | aborted | abort % |
|---|---|---|---|---|
| rec @300k | all | 150 | 2 | 1.3% |
| rec @300k | dict | 105 | 2 | 1.9% |
| rec @300k | no-dict | 45 | 0 | 0.0% |
| rec @600k | all/dict | 150/105 | 0 | 0.0% |
| rec @1M | all/dict | 150/105 | 0 | 0.0% |
| cmp @300k | all/dict | 150/105 | 0 | 0.0% |

The two aborters (binary-searched true statement need): seed 49 needs
**479 838** statements (8 dict/set ctors, 8 loops — ops inside loops), seed
97 needs **308 772** (just over budget). Both complete at 600k.

### Throughput cost of raising the budget (the crux)

Warm-cache, same 150 determinism-policy candidates, one full warmup pass
first, then one timed pass per budget (rec mode, ref+interp per case):

| budget | aborts | total wall | cases/s | median case |
|---|---|---|---|---|
| 300k | 2/150 | 16.1 s | 9.32 | 93 ms |
| 600k | 0/150 | 16.1 s | 9.31 | 92 ms |
| 1M | 0/150 | 16.1 s | 9.31 | 92 ms |

**Raising the budget costs nothing measurable** (−0.1%, within noise):
budget only affects candidates that would abort, and there are 2; aborting
at 300k burns nearly the same wall clock as completing at 480k anyway.
The default-policy sample shows the same (rec pass totals 16.7 s @600k vs
18.0 s @1M vs — cold-JIT-inflated — 31.6 s @300k; nothing aborts at any
budget, so the budget is not a cost axis at all now).

## 3. Value side: what dict testing buys in rec mode

### Per-idiom interpreted statement cost (binary-searched minimum budget; delta over the 551-statement floor of a 2-statement program)

| idiom | Δ statements |
|---|---|
| `get(d,k,def)` / `haskey` / `delete!` / `in` / `length` | ~190–230 |
| empty `Dict{Int,Int}()` ctor | 173 |
| `Dict{String,Int}()` + string-key insert | 1 183 |
| `d[k] = v` (Int key, insertion) | 2 779 |
| `push!(Set, x)` | 2 799 |
| nonempty `Dict` ctor (3 pairs) | 8 075 |
| `Set` ctor (3 elts) | 8 963 |
| `__obs__(keys(d))` / whole-dict obs | ~8 060 |
| `__obs__(sort(collect(values(d))))` | 10 220 |
| (compare: `push!(vec, x)` 1 673; `__randint__()` 654) |

At mean 6.6–10.2 ops per dict program, typical dict cost is tens of
thousands of statements — comfortably inside 300k. Only op-inside-loop
compositions (the 1.9% tail) approach the budget. No single op class
dominates pathologically, so there is nothing for option (c) to cheapen.

### Unique interpreter coverage (50 dict-heavy vs 50 dict-free determinism-policy candidates, rec @300k, `--code-coverage=@src`)

- dict run: 1 084 src/ lines hit; dict-free run: 1 077.
- **13 lines hit only by the dict run**, 6 only by the dict-free run.
- The 6 dict-free-only lines are noise (different random builtin-probe
  draws: `memoryrefreplace!`, `setfieldonce!`, `invoke_in_world` arms).
- The 13 dict-only lines are *not* noise — they are mechanistically
  dict-caused:
  - `construct.jl:271,286–288,309` + `utils.jl:255` (`get_staged`) +
    `types.jl:201–202` — the **`@generated`/staged-function framecode
    path** (`get_staged`, `genframedict` caching, DebugInfo-edge walking).
    `coverage-report.md`/NEXT.md list `@generated` as a standing grammar
    gap ("`get_source` never run"); interpreting Base's Dict internals is
    currently the only thing in the native axis that reaches this machinery.
  - `optimize.jl:331–333` — the **`Base.memhash` legacy ccall-lowering
    hack** (the comment names it), i.e. the dict string-hashing path.
  - `builtins.jl:91–92` — the `<:` builtin arm.

So dict programs in rec mode do exercise interpreter code paths nothing
else reaches. That kills option (b).

## 4. cmp-mode sanity

0 aborts in cmp mode across both samples (330 candidates); dict vs
dict-free throughput identical (7.42 vs 7.38 cases/s in the determinism
sample). Unaffected, as expected — dict ops run natively there.

## Recommendation: (d) status quo — the leak is smaller than documented (it is gone)

- The NEXT.md sentence "`dict` programs abort at ~70% when present too" is
  **stale**: it dates from the pre-`d058cb7` measurement where Base-rand
  draws, not dict ops, exhausted the budget. Post-fix rates: 0/76 dict
  aborts at default policy, 2/105 (1.9%) under the dict-densest policy.
  The dict surface *is* being tested on the axis that matters, at the
  current 300k default.
- **(b) exclude `:dict` from rec — rejected**: it would reclaim ~0% of
  budget-aborted candidates (there is no leak) while losing the only
  native-axis path into the staged-function machinery and the memhash
  ccall path (step 3).
- **(c) cheapen dict idioms — rejected**: costs are spread (observations
  ~8–10k, nonempty ctors ~8–9k, point ops ~0.2–2.8k statements); nothing
  dominates, and totals sit far below budget.
- **(a) raise the budget — optional, free**: 600k removes even the 1.9%
  loop-heavy tail at a measured 0.0% throughput cost (9.32 → 9.31 cases/s).
  Worth taking as costless insurance if any budget change is being made
  anyway; not required.
- Follow-up worth one line in NEXT.md: correct the stale claim, and note
  that the audit rule it motivates ("check the abort-rate delta in
  `--modes rec` for every new grammar feature") remains sound — it is
  exactly the measurement that cleared dicts.

Caveats: samples are n=180 (default) + n=150 (determinism policy);
coverage diff is one 50-vs-50 run (noise gauged by the reverse diff);
throughput measured warm, single process, ref+interp per case — relative
comparisons across budgets are the meaningful numbers, not absolute
cases/s.

## Artifacts (this scratchpad)

- `baseline.jl` / `baseline.tsv` / `baseline-summary.txt` — default-policy passes
- `detpolicy.jl` / `detpolicy.tsv` — determinism-policy passes
- `warmtime.jl` — warm per-budget throughput
- `micro.jl` — per-idiom statement costs; `aborters.jl` — aborter statement needs
- `covrun.jl` / `covharvest.jl` / `cov-dict.txt` / `cov-nodict.txt` /
  `cov-dict-only.txt` / `cov-nodict-only.txt` — coverage comparison
- `density.jl` — dict presence/op-density; `sanity.jl` — abort-plumbing check
