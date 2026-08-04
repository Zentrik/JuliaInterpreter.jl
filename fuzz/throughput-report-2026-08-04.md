# Throughput follow-up: per-candidate cost structure at HEAD (2026-08-04)

TL;DR — warm per-candidate cost at `-O1`: native-both 219 ms (ref 41% /
cmp 29% / rec 19%), step 179 ms (walk 60% / plain 26%), call 204 ms
(defpass 41% / native×2 23% / interp 18%). Nothing regressed since the
2026-08-03 report; two things newly measured: the step axis paid the parse
gate twice (fixed here, +8.5% measured), and the call axis pays a ~21 ms/case
`deepcopy` *compile* tax in `snapshotglobals` (the fjnorm disease relocated
into Base's specializing `deepcopy_internal`; fix sketched, not landed).

Measured on Julia 1.12.6 at `-O1` (the campaign config, `longrun.sh`), on the
`claude/false-positive-fussing-improvements-igts2c` branch, 4 shared cores.
A background Julia process (another agent's package test run) held ~1 core the
whole time, so absolute wall numbers are indicative; the per-stage *shares*
are measured inside one process and are robust to that contention.

Method: scratch stage timers (`native_stages.jl`, `step_stages.jl`,
`call_stages.jl` in this scratchpad) that replicate each campaign loop with
`time_ns()` around every stage, 40–50 warmup candidates then 200–300 measured
warm candidates, default `Cfg()`, budget 600k, step `maxcmds=4000` with
breakpoints, call `maxcalls=6`/`maxcmds=1500`. Journal writes and the
confirm/threeway paths are excluded (they cost nothing on the agree path;
journal is measured separately below).

## Native axis (`--modes both`), 300 candidates, seeds 51..350

| stage | ms/case | share | throughput-report baseline (share) |
|---|---|---|---|
| genprogram | 2.52 | 1.2% | gen+render 15% ("106 ms") |
| render | 0.33 | 0.1% | (included above) |
| parsegate | 13.38 | 6.1% | 10 ms, 1.4% |
| freshmodule | 0.88 | 0.4% | 0.9 ms, ~1% |
| run_ref | 89.86 | 40.9% | 159 ms, 37% (after) |
| run_interp rec | 41.45 | 18.9% | 87 ms, 20% (after) |
| run_interp cmp | 63.24 | 28.8% | 56 ms, 13% (after) |
| classify (both modes) | 7.82 | 3.6% | — |
| **total** | **219.5** | | 432 ms (after) |

Wall rate inside the stage timer: 4.55/s (the in-campaign 2.43/s of the
report additionally carries startup, early-candidate compile, and journal).

What changed vs. the 2026-08-03 baseline:

- **The abort tail is gone.** rec aborted 2/300 (0.7%) at the 600k budget,
  vs. 72% at the time of the report (pre inline-PRNG numbers). `run_interp
  rec` accordingly fell 87 → 41 ms/case. The 300k→600k budget raise is
  confirmed ~free: the 2 aborted runs averaged 197 ms and account for 3.2% of
  rec time. Nothing to reclaim here.
- **genprogram+render amortizes to ~1.3%.** The report's 15% share was
  dominated by one-time inference over a 50-candidate process; over 300 warm
  candidates it is 2.85 ms/case. The new destructuring/kwargs/@generated
  rules did NOT make generation expensive.
- **parsegate grew 10 → 13.4 ms** (larger programs, mean 34.4 → 36.6
  statements) and, with everything else faster, is now 6.1% of the axis. The
  report's reasons for not reusing its lowered output still stand; no safe
  change identified for the gate itself.
- The remaining ~89% is `run_ref`+`run_cmp`+`run_rec` — the documented
  inherent costs (the reference *is* compiled Julia; fresh methods in fresh
  modules per candidate).

## Step axis, 200 candidates, seeds 41..240

| stage | ms/case | share |
|---|---|---|
| genprogram+render | 3.92 | 2.2% |
| parsegate (campaign's call) | 13.39 | 7.5% |
| plain run (`run_interp` rec) | 46.30 | 25.9% |
| walk (`step_program`) | 106.46 | 59.5% |
| classify_step | 9.00 | 5.0% |
| **total** | **179.1** | |

200/200 agreed; mean 322 commands/walk; 0 walks ended `:budget`.

**Finding: `parsegate` runs twice per candidate.** `step_campaign` parses
`src` (stepfuzz.jl:533) and hands the tree to `run_interp`; `step_program`
(stepfuzz.jl:351) then re-parses the same string, so the 13.4 ms gate is paid
twice — the second one is inside the 106 ms walk stage. Eliminating the
duplicate is behavior-identical: `parsegate` is a pure function of `src`
(parse + per-statement `Meta.lower(Main, ·)` validation), nothing downstream
mutates the tree (`ExprSplitter` copies module exprs and pushes references;
`Frame(mod, ex)` copies statement vectors / lowers into fresh objects), and
the native axis already shares one parsed tree between `run_ref` and
`run_interp` (`run_all`). This dedup does not touch the documented
double-*lowering* question (gate lowers, engines lower again) — that stays as
documented; only the *second gate run* is removed.

## Call axis, 200 candidates, seeds 41..240

| stage | ms/case | share |
|---|---|---|
| genprogram+render | 3.33 | 1.6% |
| parsegate | 11.52 | 5.7% |
| definition pass (`Core.eval` loop) | 83.76 | 41.1% |
| `snapshotglobals` (+fjnorm lookup) | 10.50 | 5.2% |
| harvest (targets×methods) | 0.10 | 0.0% |
| argument synthesis | 10.12 | 5.0% |
| `restoreglobals!` ×3/call (2102 restores) | 0.45 | 0.2% |
| native call ×2 (certification) | 46.96 | 23.0% |
| `enter_call` + walk | 35.79 | 17.6% |
| classify_call | 0.02 | 0.0% |
| **total** | **203.9** | |

698 calls compared, 1 uncertified, 160 skipped; 5.3 snapshot entries/case.

**The per-run restore is free** (0.2%) — NEXT.md's "reset cost is noise"
claim confirmed at stage granularity. The *snapshot* is not free, and its
cost is not where it looks like it is:

- Warm, `snapshotglobals` costs 0.058 ms. Cold — first call on a fresh
  module, i.e. every real candidate — it costs **17–21 ms**, and
  `Base.cumulative_compile_timing` attributes **99.6% of that to compile
  time** (21.32 of 21.41 ms/module over 60 modules; `snap_which.jl`).
- The compiling party is `Base.deepcopy`: `deepcopy_internal` specializes
  per concrete type, and every candidate presents novel shapes — `__OBS__`'s
  `Vector{Any}` whose *elements* are tuples of unbounded shape diversity
  (`deepcopy_internal(::Tuple)` goes through `ntuple` with a fresh closure
  per shape; single observed copies up to 234 ms early, long tail after),
  plus each new `Dict{K,V}`/`Set{T}` combination (`Dict{Tuple{Int,Int},Int}`,
  `Set{Tuple{String,Int}}`, … at 25–40 ms each first time). The cold lookup
  half of the snapshot (names/isdefined/getglobal/isconst via `invokelatest`)
  is only 0.38 ms (`snap_attr.jl`).

This is the `__fjnorm__` re-specialization disease relocated into Base:
per-candidate type diversity × a specializing generic function = a
forever-cold compile tax. It is NOT restricted to first-in-process — the
shape space (tuple shapes × Dict/Set parameter combos) keeps producing
novelty for the life of a campaign.

## Journal / campaign-loop overhead

`journal_case!` with `--nosync` (campaign config) is an open/write/close plus
a flushed log line — bounded above by the gap between the stage-sum rate and
the campaign rate, which is dominated by startup and early compile. Not a
lever; load-bearing as crash evidence; untouched.

## Ranked candidates

1. **Step axis: don't parse the candidate twice** (IMPLEMENTED, see below).
   Measured duplicate: 13.4 ms/case of a 179 ms case = **~7.5% expected on
   the step axis**, which holds two of the six campaign shards. Risk: nil —
   same tree object the plain run already used; `parsegate` is deterministic;
   no AST mutation downstream (verified in `ExprSplitter`/`Frame`/`Meta.lower`).
2. **Call axis: replace `Base.deepcopy` in snapshot/restore with a
   non-specializing equivalent copier.** Measured: 21.4 ms/case compile tax,
   99.6% compile time = **~9–10% expected on the call axis** (one shard).
   NOT implemented this session: a faithful copier must replicate Base's
   semantics exactly — IdDict aliasing within a value graph, unassigned
   `Vector` slots, string copying, *throwing* on `Module` (a copier that
   succeeds where Base throws would change which bindings get snapshotted,
   i.e. classifications) — the same "callable struct + `@nospecialize`"
   pattern as the FJNorm fix, but it needs its own selftest testset
   (equivalence per shape, aliasing, undef slots, the throw cases) to meet
   this harness's bar. Small session-sized job; clearly worth it.
3. **No third candidate clears the bar.** Everything else measured is either
   documented-inherent (`run_ref`/`run_cmp`/defpass/native×2 = the compiled
   reference; the step walk = the SUT), already-free (600k budget: 0.7%
   aborts; per-run restore: 0.2%; freshmodule: 0.4%; journal), or small and
   risky-to-touch (parsegate 5.7–7.5% — the documented double-lowering
   semantics objection stands; classify/obseq 3.6–5.0% — dynamic recursion
   over observation streams, not worth perturbing the oracle's comparison
   code for ~4%).

## The patch (uncommitted)

`fuzz/src/stepfuzz.jl`: `step_program` takes an optional pre-parsed `ex`
(default `nothing` = parse as before); `step_campaign` and `step_keep` pass
the tree they already parsed. Three hunks, no RNG-visible change (the walk
seed derivation and every draw are untouched).

Validation (all at `-O1`, `--engine step --n 100 --seed 700000 --nosync
--noshrink --fresh --journaldir fuzz/journal-bench2`, identical config
before/after):

- **Stats identical**: before = after = 100 agreed / 0 aborted / 0 discarded /
  0 findings / 0 duplicates / 0 suppressed — same seeds, same classifications.
- **Rates** (in-campaign `rate_per_s`): at i=100, 4.38 → 4.56/s. The i=50→100
  warm segment (startup and first-candidate compile amortized out):
  6.16 → 6.68/s = **+8.5%**, consistent with the predicted ~7.5% (both runs
  shared the machine with the same background test-suite process; segment
  rates are the fair comparison).
- **Field-level equivalence** (`step_equiv.jl`): 60 candidates,
  `step_program(src)` vs `step_program(src; ex=parsegate(src))` with the same
  walkseed — status, excname, site, ncommands, nbp, ingen and the full
  observation stream identical on all 60; 0 mismatches.
- **Selftest** (`julia --project=fuzz fuzz/run.jl --selftest`): **547/547
  pass**, exit 0, 1m36.6s.

The patch is left uncommitted on the working tree (3 hunks in
`fuzz/src/stepfuzz.jl`): `step_program` gains an optional pre-parsed
`ex::Union{Nothing,Expr}=nothing` keyword (default = parse as before, so
`reprolib.jl`'s `reprostep`, `diag_stuck.jl` and all selftest call sites are
untouched), and `step_campaign` / `step_keep` pass the tree they already
parsed for the plain run.
