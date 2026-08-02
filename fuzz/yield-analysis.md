# Why FuzzJI's yield is low, and what to do about it

Status: analysis, 2026-08-02. Companion to `DESIGN.md`. Sources: an audit of
`fuzz/src/` as of `0b326ce`, the repo's own bug-fix history, and a survey of
interpreter/compiler fuzzing literature (Fuzzilli, Jit-Picking, YARPGen, swarm
testing, EMI, Nautilus/Zest, tree-splicer; links at the end).

**Implementation status.** P0, P1, and P3 below are implemented; see the
"What was done" section at the end for measurements and what each change
actually moved. P2 (semantic coverage) and P4 (EMI, world-age stress) are
still open, and are now the highest-value remaining work.

## TL;DR

Yield to date is one real bug (`invoke` argument conformance, fixed in
`76605f6`). Four causes, in decreasing order of importance:

1. **The fuzzer targets the pre-hardened surface.** Plain run-to-completion
   execution is exactly what `test/juliatests.jl` (Julia's Base test suite run
   under the interpreter) and years of Debugger.jl/Revise usage already
   exercise. The historically bug-dense surfaces — stepping (`commands.jl`),
   breakpoints, `eval_code`, `ExprSplitter` edge cases — are untouched by the
   harness. Fix-commit counts per file over the repo's history:
   `construct.jl` 9, `utils.jl` 7, `types.jl` 5, `interpret.jl` 4,
   `commands.jl` 3, `breakpoints.jl` 3, `builtins.jl` 2. The debugger/toplevel
   machinery dominates; the execution core the fuzzer tests is the *least*
   historically buggy part per line. Notably, the one bug FuzzJI did find was
   in a hand-reimplemented builtin path (`invoke`) — the seam the literature
   predicts (an interpreter's hand-written re-implementations of engine
   primitives are where it diverges from the reference).
2. **"Programs too simple" is confirmed, and it's structural, not just
   probabilistic.** Key feature compositions are *impossible* to generate, not
   merely rare (details below). The flagship wave-3 target — `break`/`return`
   through `try`/`finally` inside an interpreted function frame — cannot be
   emitted by the current grammar at all.
3. **The oracle and dedup swallow findings.** `isequal` stream comparison
   hides type divergences (`isequal(1, 1.0)` is true); exceptions compare by
   bare type name; 3-tuple fingerprints for exception-class verdicts put e.g.
   *all* interp-only `UndefVarError`s in one bucket; and `seen` is permanently
   pre-seeded from the findings directory across campaigns, so after the first
   run, new bugs in a popular bucket count as duplicates forever.
4. **Sample count is tiny.** Order 1–10 candidates/sec (per-candidate fsync,
   three fresh modules, full re-JIT of every generated function on the
   reference side, rec-mode interpretation of Base internals), default
   `--n 1000`, and the Supposition campaign exits on the first round with no
   new finding. A default campaign explores a few thousand programs;
   Fuzzilli-class campaigns explore 10^8–10^9. At current diversity *and*
   current throughput, deep-tail compositions simply never come up.

Their relative weight matters for planning: better generation (2) and more
throughput (4) raise the sampling rate of a surface whose real-bug density is
low (1); new surfaces and stronger oracles (1, 3) raise the bug density being
sampled. Do some of both, but don't invest exclusively in the generator.

## A. Audit findings: concrete generator constraints

All references `fuzz/src/...` at `0b326ce`.

**Structurally impossible compositions** (cannot occur at any n):

- Control-flow nesting deeper than 2, and deeper than **1 inside function
  bodies**: `genstmt` offers `:if/:for/:while/:let/:try` only when
  `blockdepth < 2` (`rules.jl:415-417`), the let-body starts at depth 0
  (`rules.jl:801`), function bodies start at depth 1 (`rules.jl:683`), bare
  toplevel statements at depth 2 (`rules.jl:791`, i.e. no control flow at all
  in the section meant to exercise the toplevel-frame path). Consequences: no
  `try` inside a loop inside a function, no loop-in-loop, no nested `try`, no
  `:enter`/`:leave` unwinding through a nontrivial interpreted frame stack.
- Closures are single expressions (`rules.jl:369-372`); no statements, loops,
  or `try` in any closure body; no `try` inside comprehension bodies either
  (their `want` menus carry no guard rules).
- Generated functions only receive and return concretized scalars
  (`rules.jl:284,289,304,316,668,745`): tuples, vectors, structs, closures,
  `nothing`, and Any-typed values never cross a generated call boundary. No
  higher-order functions, no closures returned from functions, no mutual
  recursion (call graph is a DAG plus one fixed self-recursion template).
- Struct fields and generator-emitted globals are scalars only
  (`rules.jl:383,704,719`): no function/vector/struct/Union fields, no
  parametric structs, no inner constructors.
- All 76 `BUILTIN_PROBES` are verbatim constant strings — probes never
  receive generated values, generated structs, or generated orderings.

**Dilution** (possible but too rare to matter at n ≈ 10^3):

- P(a program contains a break-through-`finally`) ≈ 0.15%; never inside a
  function frame (see above).
- Each specific builtin probe appears in ≈ 1/800 programs (uniform pick over
  76, gated behind an AnyT-want that itself occurs ≲1×/program).
- @atomic modify ≈ 1–2% of programs; a mutating closure that is created *and*
  called *and* has its capture observed ≈ 2–4%.
- 20% of `for` loops run zero times (`rand(0:maxloop)`); `while` conditions
  are frequently false on entry; trip counts ≤ 4 — per-iteration machinery
  gets thin dynamic coverage.
- Empty vector literals are ungenerable; collections are ≤ 3 elements; only
  Int64/Float64 arithmetic exists outside fixed probes.

**Dead/missing config:** `Cfg.maxblockstmts` is never read (block sizes are
hardcoded `rand(1:3)` etc.), and no `Cfg` field is exposed on the CLI —
program size can't be scaled without editing source.

**Oracle blind spots:**

- `isequal` on observation streams (`classify.jl:32-38`) hides Int-vs-Float
  and Bool-vs-Int divergences; the normalizer never records types.
- Struct instances normalize to `nameof(typeof(x))`, functions to `:__fn__` —
  field-value divergences are invisible unless separately observed; only the
  final 3 bindings are force-observed, FnT bindings never.
- Exceptions compare by bare type name; parameters/messages/fields ignored.
- Aborted runs with a consistent prefix are discards — and the deepest
  programs are precisely the ones that abort (every comprehension `collect`,
  `push!`, `string` call burns thousands of rec-mode statements against the
  300k budget).

**Dedup/campaign mechanics:**

- Exception-class verdicts fingerprint as just `(class, refexc, intexc)` —
  obs-shape salting only applies to value divergences. One
  `interp_only_throw`+`UndefVarError` finding shadows all future ones.
- `seen` is pre-seeded from `findings/` across restarts; suppression is
  permanent and coarse.
- The Supposition campaign stops at the first round with no new finding and
  spends hundreds of executions shrinking each candidate; shrinking may also
  drift to a *different* fingerprint than the one originally hit (the
  original is lost).
- Per-candidate `fsync` in both engines costs milliseconds each.

## B. What similar systems do (and what to steal)

- **Fuzzilli** (JS engines): generates/mutates a typed SSA IR ("FuzzIL") where
  instruction inputs are always variables — so InputMutator (swap an operand
  for another in-scope, type-compatible variable), OperationMutator, and
  crucially **SpliceMutator** (transplant an instruction range from another
  corpus program, remapping variables) are trivial and validity-preserving.
  Coverage feedback decides what enters the corpus; mutation-over-corpus
  compounds structure that pure generation re-derives from scratch each time.
  *Steal:* corpus + splicing over FuzzJI's existing mini-IR; the `Ex`/`St`
  nodes with `TySum` summaries are already exactly the representation
  splicing needs.
- **Jit-Picking** (CCS 2022, built on Fuzzilli): differential testing of an
  engine's interpreter vs. JIT tiers — the exact analogue of FuzzJI's oracle.
  Its sensitivity comes from comparing *full observable state* (all mutated
  state, exception identity, not just return values) plus an aggressive
  nondeterminism-normalization layer. *Steal:* type-aware observation
  comparison, observe every binding not just the final 3, compare exception
  fields.
- **Swarm testing** (ISSTA 2012): don't enable every grammar feature in every
  program; draw a random feature subset per program. +40% distinct compiler
  crashes over always-everything Csmith, because some bugs are *suppressed*
  by the presence of other features. One afternoon of work on any grammar
  fuzzer. *Steal:* per-program feature mask over the wave-1/2/3 rule set.
- **YARPGen generation policies** (OOPSLA 2020): deliberately skew choice
  distributions per program region to make targeted subsystems fire. *Steal:*
  per-program weight profiles ("exception-heavy", "dispatch-heavy",
  "atomics-heavy", "toplevel-heavy") instead of one global weight table —
  this fixes the dilution problem without a rewrite.
- **EMI** (Orion/Athena/Hermes): profile which statements execute on an
  input; mutate code that's dead on that input (or insert provably inert
  code); semantics must be unchanged, so any divergence is a bug. *Steal:*
  this is unusually cheap here — the interpreter is instrumentable pure
  Julia, so per-candidate "which IR statements ran" is nearly free, and it
  yields a second oracle orthogonal to compiled-vs-interpreted: require
  `interp(P) == interp(P′)` for EMI-equivalent P′.
- **Zest/JQF and Hypothesis-style choice sequences**: make the generator a
  deterministic function of a byte/choice stream so byte-level mutation =
  valid structural mutation. FuzzJI already has this substrate (the
  Supposition `TCRNG` adapter). *Steal:* keep a corpus of choice sequences
  that hit new coverage and mutate/splice *those* — a mini-Nautilus with no
  new generator code.
- **tree-splicer / icemaker** (rustc): generate by splicing subtrees parsed
  from a real-code corpus (compiler's own test suite) rather than authoring
  a richer grammar. *Steal:* run Base/stdlib test files (and
  `test/interpret.jl` etc.) through a crash/stepping oracle; mutate them
  EMI-style rather than trying to make them pass a semantic-equivalence
  oracle (real code is too nondeterministic for stream equality, but "the
  interpreter must not throw from its own frames, and stepping must
  terminate and agree with running" needs no semantic oracle).
- **Prior Julia fuzzing** (AFL-on-julia by Dan Luu; TypeFuzz.jl): the
  memorable AFL findings were exception/control-flow bugs — corroborating
  `:enter`/`:leave`/unwinding as the richest seam — and the main friction
  was process-startup cost, which FuzzJI's in-process design already avoids.

## C. On the two hypotheses

**"Programs too simple/constrained" — yes, confirmed,** but the actionable
form is sharper than "make them bigger": specific compositions are
*ungenerable* (§A), and the interesting constructs that are generable are
diluted below 1/100–1/800 programs while campaigns only sample ~10^3. Fixing
the two hard gates (blockdepth, scalar-only call boundaries) matters more
than raising size knobs.

**"Use coverage to better generate inputs" — yes, but in a specific way.**
Binary edge coverage (AFL-style) of julia itself is the wrong tool here.
What's cheap and high-signal is coverage *of the interpreter*, in pure Julia:
which `step_expr!` branches, builtin arms, `evaluate_call!` paths, and
`commands.jl` code paths each candidate touches. Use it in two stages:
first **as a metric** (run 10^4 candidates, diff hit-set against the
interpreter's reachable surface — every never-hit arm is either a grammar gap
or dead code; this directly validates/refutes generator changes), then **as
feedback** (corpus of choice sequences retained for novel coverage, mutated
and spliced). Stage 1 is a weekend and de-risks stage 2.

But note both hypotheses implicitly assume the bugs are in the surface being
fuzzed. The fix history says the larger pool is elsewhere (stepping,
breakpoints, eval_code, ExprSplitter) — surfaces with *no* existing
systematic testing, where even a weak fuzzer meets untested code. Expected
yield per engineering-hour is highest there.

## D. Recommended plan

**P0 — mechanical unblocking (a day, do regardless):**
1. Drop the `blockdepth < 2` gate to a weighted-decay probability; enter
   function bodies at depth 0. Makes try-in-loop-in-function generable.
2. Wire `Cfg` to CLI flags; fix dead `maxblockstmts`; add a `--big` profile.
3. Salt exception-class fingerprints with obs-shape (like value divergences)
   and add a `--nodedupe-cache` flag so disk-seeded `seen` is opt-in.
4. Don't end Supposition campaigns on the first empty round; batch the
   journal fsync (fsync only before *execution*, not per generation).
5. Compare observation streams type-sensitively (`isequal(x,y) &&
   typeof(x)==typeof(y)` modulo the deliberate normalizations); observe all
   live bindings at scope exit, not the final 3; compare exception
   arguments/fields where meaningful, not just the type name.

**P1 — distribution shaping (days):**
6. Swarm feature masks: per-program random subset of rule families.
7. Generation policies: 4–6 weight profiles (exception-heavy, dispatch-heavy,
   atomics/builtin-heavy, toplevel-heavy, closure-heavy), picked per program.
8. Parameterize a subset of builtin probes to take generated values/structs.
9. Let Any/Tup/Vec/Struct/FnT values cross generated-function boundaries;
   allow struct fields and globals of those kinds.

**P2 — coverage (a weekend for the metric; more for the loop):**
10. Semantic-coverage instrumentation of the interpreter (statement-head ×
    context, builtin × arity-class, dispatch-path flags — the M3 sketch), used
    first offline as a grammar-gap report, then as corpus-admission feedback
    with choice-sequence mutation + splicing (mini-Nautilus/Zest; the TCRNG
    substrate already exists).

**P3 — new surfaces (the biggest expected-yield item):**
11. Fuzz `debug_command` random walks (`:n`/`:s`/`:until`/`:finish`/`:c` +
    random breakpoints incl. conditional ones) over the *same generated
    programs*, with two oracles: no exception escapes from JuliaInterpreter's
    own frames, and final observations agree with plain interpretation. This
    targets `commands.jl`/`breakpoints.jl`, which have zero systematic
    testing and the densest fix history.
12. Same idea over `eval_code` (evaluate random in-scope expressions at
    random pause points; write-back paths for locals/static params are a
    known fix hotspot) and `ExprSplitter` (feed it the generated toplevel
    sections plus adversarial nestings of `module`/`begin`/`if` at toplevel).
13. Corpus track: run real test files (Base tests, this repo's own tests,
    popular packages') under the stepping/no-internal-error oracle above —
    tree-splicer-style value without needing stream equality on real code.

**P4 — stronger oracles (research-y, high ceiling):**
14. EMI mode: per-candidate executed-statement profile from the interpreter,
    dead-statement deletion/insertion mutants, assert interp(P)==interp(P′)
    (and compiled(P)==compiled(P′) for free cross-checking).
15. Compiled-mode boundary stress: `--modes cmp` with breakpoints set inside
    callees (forces the recurse/compiled boundary decisions in
    `evaluate_call!`), and world-age/redefinition scenarios (method
    redefinition mid-program is currently excluded wholesale; a scoped,
    deterministic version — define, call, redefine, call — targets
    `f83049b`/`161d6a0`-class world/cache bugs).

Throughput note (multiplies everything): reuse a pool of pre-warmed modules,
skip the second lowering (hand `ExprSplitter` the already-lowered exprs),
consider `--modes cmp`-only for high-volume runs (rec-mode Base
interpretation is the main per-candidate cost), and shard campaigns across
processes with distinct seeds.

## What was done (2026-08-02)

Measured with `fuzz/metrics.jl`, which reports the generated distribution
without executing anything. Baseline figures are from the generator at
`0b326ce` over the same seeds.

**P0 — mechanical unblocking** (commit "P0: unblock nesting…"):

- The `blockdepth < 2` gate became a configurable cap plus a per-level weight
  decay. Function bodies now start at depth 0 and toplevel statements at
  depth 1. Program size held constant (33.1 → 32.6 statements, 61.1 → 61.0
  rendered lines) while `try` inside a loop went 4.8% → 8.5% of programs and
  **try-in-a-loop-in-a-function 0% → 2%** — it was structurally ungenerable.
- Found and fixed while doing it: a `while` at module toplevel was broken.
  The fuel counter is a global there and the loop body is a soft scope, so
  `fuel -= 1` declared a new local and threw `UndefVarError` reading it,
  killing the rest of the program. Only reachable once toplevel statements
  could nest.
- Oracle: observation streams were compared with `isequal`, which holds
  across types (`isequal(1, 1.0)`), so an interpreter returning a Float where
  compiled Julia returns an Int compared *equal*. Now type-sensitive. All
  live bindings are observed at program end rather than the last three, and
  function-valued bindings are observed by calling them under a guard.
- Dedup: exception-class verdicts fingerprinted as `(class, refexc, intexc)`
  only, so every interp-only `UndefVarError` shared one bucket and the first
  one reported masked all later ones. Salted with the last observation's
  shape — deliberately *not* the stream length or divergence index, which
  move under shrinking and would make the shrinker reject nearly every edit.
- `Cfg` is reachable from the CLI at all now (`--big`, `--maxblockdepth`, …);
  `maxblockstmts` was declared but never read.

**P1 — distribution shaping** (commit "P1+P3: swarm masks…"):

- Swarm masking: `try` occurrences 331 → 539 and exits crossing a try
  boundary 45 → 85, while P(program contains try) *fell* 50.8% → 45.8%.
  Fewer programs have the feature; those that do have much more of it.
- Policies, forced one at a time against uniform: `exceptions` raises
  exit-through-try 6.4× and try-in-loop 3×; `builtins` raises probe density
  3.2×; `mutation` raises struct aliasing 2.4×.
- Non-scalar values now cross function boundaries (previously impossible),
  and struct-valued bindings — which gate every struct rule — are created far
  more often under the policies that target them: field writes 5.5% → 29%,
  aliasing 24.5% → 57%, atomic modifies 1% → 4.5%.

**P3 — the stepping axis** (`--engine step`): described in `DESIGN.md`.
Yield so far: on its first 400-program campaign it produced 3 reports, of
which triage showed **two were false positives in my own oracle** and one
exposed a **real generator bug**:

- `vararg` was tracked per *function* but only the signature built by
  `genfundef` renders a `va...`; a call that picked a different method still
  appended trailing arguments and matched no method. The differential axis
  never reported these — both sides throw `MethodError`, so they classify as
  agreement — they just quietly wasted candidates.
- False positive 1: `frame.world` must be refreshed on toplevel frames, which
  the interpreter's own toplevel loop does and `debug_command` does not.
- False positive 2: deciding "is this throw a bug" from whether the backtrace
  mentions JuliaInterpreter is wrong — program-thrown exceptions unwind
  through interpreter frames too. Now decided by comparing against plain
  interpretation of the same program.
- The `nonterminating` class was also measuring the wrong thing: with
  break-on-error armed, `:c` stops at every throw, and these programs throw on
  purpose, so a large command count is normal. Replaced with direct
  non-advancement detection (the same (framecode, pc) surviving
  `STUCK_LIMIT` consecutive commands), which is the actual historical bug
  shape; budget exhaustion is now tracked, not reported.

A third calibration followed: `step_stuck` initially counted *any* repeated
`(framecode, pc)`, but with break-on-error armed a statement that always
throws re-triggers the same error breakpoint every time it is retried, so
execution legitimately does not advance until the user unwinds. Every report
from that round was a walk parked on an error breakpoint. Only no-ops that
return a *normal* pc count now.

The general lesson, worth keeping in mind for P2/P4: **a new axis's first
reports are usually about the axis, not the system under test.** Budget for
calibration before believing yield numbers. Concretely, of the first six
reports the stepping axis produced, five were oracle miscalibrations and one
was a generator bug — and finding that out took a diagnostic
(`fuzz/diag_stuck.jl`) that answers "what is it actually stuck on", because
the campaign-level signal ("this took 80,000 commands") could not distinguish
a hang from a large program.

## Where things stand

Campaign results after the above (Julia 1.11.9, this branch):

- differential axis, 700 programs: 696 agreed, 4 aborted, **0 discarded**
  (every generated program still valid by construction), 0 findings.
- stepping axis, 500 programs: agreement once the oracle was calibrated.

So: no new interpreter bugs from these runs, on a widened grammar that now
reaches compositions it previously could not. That is a real (negative)
result for the differential axis and consistent with the analysis above — the
run-to-completion surface is genuinely hardened, which is why the plan puts
new surfaces ahead of more inputs.

The highest-value remaining work is unchanged: **P2** (semantic coverage of
the interpreter, first as an offline grammar-gap report, then as
corpus-admission feedback) and **P3 items 12–13** (`eval_code` and
`ExprSplitter` axes — `utils.jl`/`construct.jl` carry the two densest fix
histories in the package and neither is fuzzed yet), then **P4** (EMI).

## The first long run

Five sharded axes (`fuzz/longrun.sh`), restart-looping. What it produced:

**One real bug, in Julia rather than in JuliaInterpreter.** `julia` aborts
inside its own LLVM allocation-optimization pass (`llvm-alloc-opt.cpp`,
`moveToStack`) while compiling a generated program. It surfaced on the
*reference* side — plain `Core.eval` — so the interpreter is not involved.
Two shards hit it independently with identical backtraces. Recovered by
deterministic replay to seed 5000644 and reduced from 69 to 29 lines; see
`findings/julia-codegen-abort-allocopt/`.

That the harness finds compiler bugs is a side effect worth naming: it
compiles every generated program as its reference, so it is a codegen fuzzer
for free, on exactly the type-unstable deeply-nested input that stresses
escape analysis. The AFL work on the Julia binary found a comparable class.

**Four harness bugs, which is the more useful output of a first long run.**
Each was killing batches or manufacturing findings, and none was reachable by
short campaigns:

- Observation slots can be *unassigned*, not merely absent: `push!` grows the
  array then stores, so an interpretation stopping in between leaves a live
  element that was never written. Reading it killed whole batches — sometimes
  `UndefRefError`, sometimes a segfault, both inside the comparator.
- `inlocal` counts *generation* scopes, which are pushed for `if` blocks too,
  but `if` introduces no runtime scope. Runtime scopes are now tracked
  separately; without that, a `while` fuel counter written inside a toplevel
  `if` silently never decremented.
- The parse gate lowered the whole program in one call, so a per-statement
  scope error slipped through and then failed on *both* sides with different
  exception types — reported as an exception divergence. One generator mistake
  of this shape produced 32 spurious findings in a single run.
- The journal's seed history was flushed only when the per-candidate fsync was
  on, so a killed shard lost its history exactly when it was wanted.

The crashed-candidate recovery path also had a hole: the journal holds the
program that was executing, but the *next* batch overwrote it immediately, so
a crash destroyed its own reproducer. Fixed by setting it aside on restart.

**Still no JuliaInterpreter bug.** The interpreter-facing axes ran clean. Given
the fix-history argument above, the most likely reading is that they need
hours rather than that they are pointed wrong — but that is a hypothesis, not
a result, and it stays untested until a run goes the distance on fixed code.

## On "bigger programs" vs "splice real code"

Both were raised as ways to attack the same problem. They are not equally
valuable, and the difference is worth stating because it changes where effort
goes.

**Bigger programs are the weaker lever.** Program length does not change which
interpreter code paths are reachable — the grammar's *vocabulary* does. A
200-statement program built from the same rules as a 30-statement one visits
the same `step_expr!` arms, just more times. What length buys is deeper
feature *interaction*, which is real but already addressed more cheaply by the
nesting fix (P0.1) and swarm concentration (P1.1): both raised interaction
rates with program size held flat. Length also costs throughput and raises the
abort rate, since `RecursiveInterpreter` burns budget interpreting Base. It is
supported (`--big`, ~65 statements/program) and worth running as a background
variant, but it is not where the next bug is.

**Real code is the stronger lever, for a specific reason:** it contains
constructs the grammar will never invent. Generators, `do` blocks,
broadcasting, `where` clauses with constraints, iteration protocols, macros
expanding to arbitrary lowered forms — no one is going to write grammar rules
for all of that, and each is a distinct path through `construct.jl` and
`interpret.jl`. This is the tree-splicer/icemaker result: derive inputs from a
corpus instead of growing a grammar forever.

**But it cannot use the differential value oracle**, and that is the part
worth being careful about. Real code does I/O, calls `rand` and `time`,
iterates dictionaries, depends on machine state — comparing observation
streams against compiled Julia would produce endless false positives. That is
precisely why the grammar excludes all of it by construction. Splicing real
code into the *existing* axis would not "spice up" the differential fuzzer; it
would break its oracle.

The resolution is to pair real code with an oracle that needs no determinism.
`--engine corpus` compares **failure mode only**: if `Core.eval` cannot run
the fragment, discard it; if compiled Julia ran it and the interpreter did
not, that is a finding. Plus the stepping invariants, which never needed
determinism either. Note that this became possible only *because* the stepping
axis was built first — before that there was no determinism-free oracle to
attach a corpus to.

So the honest ordering is: real code yes, and it is now built; bigger programs
are a cheap background variant, not a priority; and the thing neither idea
addresses — knowing *which* constructs are missing rather than guessing — is
still P2, which is why it remains the top remaining item.

## Campaign results, all axes

Julia 1.11.9, this branch, all with `--fresh`:

| axis | cases | outcome |
|---|---|---|
| differential (`native`) | 700 | 696 agreed, 4 aborted, 0 discarded, 0 findings |
| stepping (`step`) | 500 | 498 agreed, 2 aborted, 0 findings |
| eval_code (`evalcode`) | 400 | 400 agreed, 0 findings |
| corpus (`corpus`) | 200 | 99 executed, 101 discarded as junk, 0 findings |

No interpreter bugs from any of them. Three *generator* bugs were found and
fixed along the way (toplevel `while` fuel in a soft scope, the missing
`StructT` branch in `genex_inner`, per-method vararg tracking), the last of
which the differential axis structurally could not report.

That is a real negative result, and it is worth stating plainly rather than
dressing up: the run-to-completion surface is hardened, and the new axes are
calibrated but have not yet been run at the scale where they would be expected
to produce anything. These campaigns are hundreds to low thousands of cases;
the systems in the literature that find interpreter bugs run 10^8 and up. The
value delivered here is that four axes now exist, three of them cover surfaces
that had no systematic testing at all, and each has been shown to actually
exercise what it claims — 1076 eval_code checks across 56 distinct variables,
99 real fragments reaching the interpreter per 200 corpus cases. The next
thing to do with them is run them long, not build a fifth.

## References

- Fuzzilli: https://github.com/googleprojectzero/fuzzilli (Docs/HowFuzzilliWorks.md)
- Jit-Picking (CCS 2022): https://publications.cispa.saarland/3773/1/2022-CCS-JIT-Fuzzing.pdf
- Swarm testing (ISSTA 2012): https://agroce.github.io/issta12.pdf
- YARPGen (OOPSLA 2020): https://users.cs.utah.edu/~regehr/yarpgen-oopsla20.pdf ; v2 (PLDI 2023): https://users.cs.utah.edu/~regehr/pldi23.pdf
- EMI survey: https://arxiv.org/pdf/2306.06884 ; Bug Histories as Mutators: https://arxiv.org/pdf/2510.07834
- Nautilus (NDSS 2019): https://www.ndss-symposium.org/wp-content/uploads/2019/02/ndss2019_04A-3_Aschermann_paper.pdf
- Zest (ISSTA 2019): https://arxiv.org/pdf/1812.00078 ; JQF: https://github.com/rohanpadhye/jqf
- DIE / aspect-preserving mutation (Oakland 2020): https://taesoo.kim/pubs/2020/park:die.pdf
- tree-splicer/tree-crasher: https://crates.io/crates/tree-crasher ; fuzz-rustc: https://github.com/dwrensha/fuzz-rustc ; rustc fuzzing guide: https://rustc-dev-guide.rust-lang.org/fuzzing.html
- AFL + C-Reduce on Julia: https://www.juliabloggers.com/bugs-in-julia-with-afl-and-c-reduce/ ; TypeFuzz.jl: https://discourse.julialang.org/t/typefuzz-jl-fuzz-testing-of-the-julia-type-system/3786
- Supposition.jl: https://github.com/Seelengrab/Supposition.jl
