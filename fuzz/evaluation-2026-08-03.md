# Evaluation: fuzzing effectiveness as of 2026-08-03

Status: rigorous progress review, requested after the first large-scale
campaign. Companion to `yield-analysis.md` (which diagnosed the *generator and
oracle*); this evaluates the *project* — where the time went, what each
component has actually produced, and what that implies about where the next
bug comes from. Sources: the commit log of this branch (94 commits,
2026-08-02 12:18 → 2026-08-03 09:15), `NEXT.md`, `coverage-report.md`,
`findings/`, and an independent read of `fuzz/src/`.

## Verdict

The infrastructure is genuinely strong — five axes, a reflection-driven
prober, confirm-on-divergence, per-axis shrinking, version-aware triage,
crash-safe journalling. The problem is not the methods. It is that

1. **the effort ratio is inverted** — roughly 21 hours of engineering
   (~11,500 lines of harness across ~90 commits) against roughly 3–4 hours of
   total campaign compute, in a field whose yield curves are written in units
   of 10⁸ candidates;
2. **the one component with proven teeth has a narrow lens** — the builtins
   prober accounts for 4 of the 5 interpreter findings, and its field of view
   is "malformed builtin/intrinsic calls raise the wrong exception", which is
   exactly why the findings all look alike; and
3. **the two coldest historically-buggy surfaces are still effectively
   unfuzzed** — `breakpoints.jl` (13.3% of instrumented lines, 30 of 34
   definitions never executed; the step axis only ever arms
   `break_on(:error)` and never sets a real breakpoint) and the public entry
   points (`@interpret`, `enter_call`, `interpret`, `extract_args`: zero
   coverage; every axis bypasses them).

One sentence: **a 10⁸-class harness has run a 10⁴-class campaign — stop
sharpening, start grinding, and point the grinder at breakpoints and the
public API while it runs.**

## Per-component yield attribution

Attributing the five interpreter findings to the component that produced
them:

| component | engineering invested | interpreter bugs found |
|---|---|---|
| builtins prober + differential exception grammar | moderate (`probes.jl` ~1000 LOC) | **4 of 5** — invoke arity, invokelatest empty-args, `_call_latest` non-callable Symbol, cmp-mode rethrow interception |
| step axis | moderate (`stepfuzz.jl` ~390 LOC) | 1 — the `more_calls_on_current_line` / `whereis` crash |
| evalcode axis (287 LOC), corpus axis (897 LOC), split axis (1049 LOC), determinism grammar (rng/dict/vtime), three-way oracle, shrink/reshrink | **the majority of recent effort** | **0** |

Three caveats that keep this honest:

- **Zero findings at n ≈ 10³–10⁴ is not evidence of zero yield.** A Poisson
  95% upper bound on "0 findings in 10⁴ candidates" is consistent with a true
  rate of ~37 bugs per 10⁶. The zero-yield axes are *unmeasured*, not
  unproductive — but that cuts both ways: their expected value is a guess
  until they run at 10⁶ or are validated against known bugs (below).
- **The prober's four bugs are real but low-severity.** All four are in the
  hand-reimplemented builtin expand paths, three are "wrong exception type on
  a call no real program writes" (`Core.invoke(abs)` with no arguments). If
  the goal is bugs maintainers prioritize, the fix history says those live in
  stepping, breakpoints and eval_code — the surfaces with one crash between
  them so far.
- **Some infrastructure earned its keep indirectly.** The three-way oracle
  adjudicated bug 4 automatically; confirm-on-divergence produced zero false
  findings across the determinism-grammar calibration; triage.jl answered
  "fixed upstream?" in seconds on the codegen crash after that question had
  once cost hours. The critique is the *ratio*, not any single item.

## The pattern to break

`yield-analysis.md` (2026-08-02) closes its campaign section with: *"The next
thing to do with them is run them long, not build a fifth."* The commit log
after that sentence: a fifth axis (split), the determinism grammar, the
three-way oracle, `reshrink.jl`, optimizer barriers. Each individually
well-justified; collectively the same drift the analysis diagnosed. Meanwhile
total campaign compute stayed at ~3–4 hours, on 4 cores shared with another
tenant.

The scarce resource is no longer harness capability. It is candidate volume
and, per candidate, the severity-weighted bug density of the surface being
sampled.

## Ground truth is missing

The split axis is the only component whose oracle has been validated against
*known true positives* (the drop-one-fragment mutation test: 86% caught).
The step, evalcode, corpus and native oracles were calibrated against false
positives only. "The run-to-completion surface is hardened" and "our oracle
is blind" are currently indistinguishable hypotheses.

The cheap, decisive experiment — already cited in `yield-analysis.md`'s
references ("Bug Histories as Mutators") but never run: **revert a real
historical fix, and measure whether each axis rediscovers it, and at what
n.** Candidates: the four bugs this project just fixed (they come with seeds
and repros), #758–#761 from July 2025, and the older eval_code/stepping fixes
that motivated those axes. An axis that cannot rediscover a *known* bug at
10⁴ will not find an unknown one at 10⁴, and its compute share should move to
an axis that can.

## Recommendations, ranked by expected yield per hour

1. **Freeze feature work; run a 48–72h campaign** (all axes, sharded, Julia
   1.12 to dodge the 1.11 GC segfault). Costs zero engineering; everything
   needed exists.
2. **First spend one day on throughput + unattended compute** (NEXT item 8 +
   item 7, both ranked too low): module pooling, skip the double lowering,
   batch the journal fsync, weight shards toward the cheap axes; and a
   time-boxed nightly CI job so compute accrues without a session
   babysitting it. Native at ~2/s × 4 shared cores × 72h ≈ 2M candidates; a
   5–10× throughput win is the difference between 10⁶ and 10⁷.
3. **Give the step axis real breakpoints** — random `breakpoint(f)`,
   file:line and conditional breakpoints, toggled/disabled/removed mid-walk,
   under the existing invariant oracle. Largest cold surface with a real fix
   history, and it drops into an axis that already exists. Also drive
   `enter_call`/`@interpret` as an alternate entry mode: currently 0%
   covered, trivial to add.
4. **Run the bug-history mutant benchmark** (revert ~8 known fixes one at a
   time; 10⁴ candidates per axis per mutant; record detection). Converts
   "which axes deserve compute" from opinion into measurement, and
   calibrates expected campaign yield.
5. **Decide deliberately about the prober's bug class.** Widening
   `PROBE_RECIPES` toward plausible-but-edge *well-formed* calls keeps
   producing findings of the current class; the debugger surfaces produce
   fewer but weightier ones. The current allocation drifted into the former;
   it should be a choice, not a drift.

Deferred until after a real long run: coverage-feedback stage two, EMI, the
ENV/fs virtual doubles. All defensible; none should precede the first
10⁶-candidate campaign.

## Scorecard against the standing goal ("find many more issues")

| dimension | state | grade |
|---|---|---|
| harness capability (axes, oracles, intake) | five axes, validated intake gates, triage | strong |
| campaign volume | ~10⁴–10⁵ lifetime candidates vs. the literature's 10⁸ | the bottleneck |
| surface targeting | prober saturating malformed-call class; breakpoints + public API cold | misallocated |
| oracle validation | split axis only (86% mutant catch); others unvalidated | gap |
| finding severity | 4/5 findings are malformed-call exception-type divergences | low |
| ops (unattended compute, CI) | longrun.sh exists; no CI; interactive-session-bound | gap |
