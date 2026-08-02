# Why FuzzJI's yield is low, and what to do about it

Status: analysis, 2026-08-02. Companion to `DESIGN.md`. Sources: an audit of
`fuzz/src/` as of `0b326ce`, the repo's own bug-fix history, and a survey of
interpreter/compiler fuzzing literature (Fuzzilli, Jit-Picking, YARPGen, swarm
testing, EMI, Nautilus/Zest, tree-splicer; links at the end).

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
