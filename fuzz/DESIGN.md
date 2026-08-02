# FuzzJI: differential fuzzing of JuliaInterpreter against compiled Julia

Generate random-but-valid Julia programs, run each one twice in the same
process — compiled (`Core.eval`, the reference) and interpreted
(`ExprSplitter` + `Frame`, the system under test) — and compare everything
observable. Divergences are findings against the interpreter.

Prior art: [Fuzzilli](https://github.com/googleprojectzero/fuzzilli) for the
"generate over a typed program representation" idea;
[Rustlantis](https://github.com/cbeuw/rustlantis) (differential fuzzing of
Miri vs. compiled MIR) for the observation-stream oracle and
termination-by-construction. Unlike Fuzzilli, no custom IL toolchain and no
crash/coverage focus: `Expr`/source text is the IL, and the threat model is
*semantic divergence*, not memory safety.

## Quick start

```sh
julia --project=fuzz -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'  # from repo root
julia --project=fuzz fuzz/run.jl --selftest                    # harness acceptance tests
julia --project=fuzz fuzz/run.jl --n 5000                      # Supposition-driven campaign
julia --project=fuzz fuzz/run.jl --engine native --n 10000 --seed 1  # seeded-RNG campaign
```

Findings land in `fuzz/findings/<class>-<fingerprint>/` as a standalone
`repro.jl` (runs with `julia --project=fuzz repro.jl`) plus `meta.md` with the
original and shrunk programs. For long unattended runs wrap `run.jl` in a
restart loop; `fuzz/journal/current.jl` always holds the candidate that was
executing, written and fsync'd *before* execution, so even a segfault leaves a
reproducer.

## Architecture

```
Generator ──► Program IR ──► render ──► source text ──► validity gate (Meta.lower)
 (seeded RNG,                                    │
  environment-directed)                 journal to disk (crash-safe)
                                                 │
                              ┌──────────────────┴──────────────────┐
                              ▼                                     ▼
                     REFERENCE: Core.eval                INTERPRETED: ExprSplitter
                     per toplevel stmt,                  + Frame, budgeted executor
                     fresh Module                        (port of evaluate_limited!),
                              │                          fresh Module      │
                              └──────────────────┬──────────────────┘
                                                 ▼
                            Comparator / Classifier (observation streams)
                                                 ▼
                       dedup (fingerprint) → shrink (greedy + repair) → report
```

All of this lives in `fuzz/src/`; the package's own deps are untouched.

### The IR (`typesum.jl`, `ir.jl`)

Programs are generated over a small typed mini-IR (uniform `Ex`/`St` nodes
with a `kind` tag), then rendered to **source text** — the interchange format
on purpose, so journal entries and repros contain literally the program that
ran, and both sides parse the same text with `Meta.parseall` (file/hard-scope
semantics). Every node carries a *type summary* (`TySum`): a deliberately
imprecise lattice (`Int/Float/Bool/Str/Sym/Nothing`, tuples, vectors,
functions with positional summaries, `Any`). Summaries exist so the generator
can pick compatible operands — and so it can generate *deliberately*
type-unstable code (Any-typed slots, multi-method dispatch), which is where
interpreter dispatch paths get exercised.

Key invariants, chosen so that every difference between the two sides is
signal:

- **Termination by construction.** `for` loops have literal bounds, `while`
  loops carry a decrementing fuel counter, recursion uses the fueled
  `recdef` template. The compiled side therefore always terminates; budget
  exhaustion on the interpreted side is classified, not discarded as noise.
- **Observations, not return values.** Programs push normalized values into a
  per-module `__OBS__` via `__obs__(x)` (see `SETUP_SRC`); the oracle compares
  the streams and pinpoints the first divergent index. Normalization scrubs
  anything module- or identity-dependent (closure type names, struct types)
  so `isequal` on streams is meaningful. `isequal` also means NaN agrees with
  NaN while `0.0`/`-0.0` differences are caught.
- **Guarded partial operations.** Fallible ops (indexing, `÷` by arbitrary
  values, `setindex!`) render as `try ... catch` that *observes the exception
  type* — exception behavior becomes first-class oracle data instead of noise.

### Generation (`env.jl`, `rules.jl`)

Environment-directed: a `Ctx` carries a lexical scope chain of
`(name, TySum)` records plus defined functions with per-method signatures.
Rules only reference bindings the context proves in scope, so programs are
valid by construction (the selftest asserts 0 parse/lowering failures across
300 seeds). Blocks are generated in child generation-scopes conservatively
(runtime `if` doesn't scope, but forgetting its bindings is safe).

Wave-1 grammar: literals (including `typemax`, `NaN`, `-0.0`, unicode
strings), arithmetic/comparison/boolean ops, `===`, `isa` against abstract
types, ternaries, tuples, vectors (`push!`/guarded `setindex!`/aliasing —
identity semantics is a classic interpreter bug class), `if`/`for`/fueled
`while`/`let`/`try-catch-finally`, named functions with typed/untyped params
and **multi-method dispatch** (second method differing in first-param type),
fueled recursion, and **closures** — including the mutating variant
`p -> (cap = cap + p; cap)` that forces captured variables into `Box`es.

Wave-2 grammar (programs are now four sections: module globals + struct
definitions, function definitions, bare toplevel statements, and the `let`
body):

- a curated **builtins/intrinsics edge-case dictionary** (`BUILTIN_PROBES`):
  ~45 verbatim probes of `getfield`/`apply_type`/`Core.Intrinsics.*`/
  `_apply_iterate`/`compilerbarrier`/... with wrong arities and
  odd-but-lowerable arguments, always guarded so the exception *type* is
  oracle data — aimed directly at `src/builtins.jl`;
- **module globals**: created at toplevel and via bare-toplevel statements,
  read everywhere, written from local scopes via `global x = ...`;
- **`struct`/`mutable struct` definitions**: construction, field reads,
  `setfield!` via `x.f = v`, mutable-struct aliasing; observations record
  field values, never instances (type identity differs across the two
  modules by construction);
- **kwargs/defaults/varargs/splat**: keyword params with defaults (random
  subsets passed at call sites — the kwsorter path), trailing positional
  defaults, vararg methods with extra/splatted call-site args;
- **comprehensions** with optional filters (lower to closures + `collect`);
- **bare toplevel statements** between the definitions and the `let`,
  exercising the toplevel-frame path without the `let` wrapper.

Generation is a pure function of its randomness source, consumed through the
`AbstractRNG` interface. Two engines drive it (`--engine`):

- **supposition** (default, `supposition.jl`): a `TCRNG` adapter forwards
  every draw to Supposition.jl's `TestCase` choice recording, and
  `ProgramGen <: Data.Possibility{Program}` replays choice sequences through
  the generator. Counterexamples are therefore shrunk by choice-sequence
  replay — valid by construction, structural, and it reaches the config's
  size floor in practice — then polished by the greedy IR shrinker. Rounds
  continue while new (non-duplicate, non-suppressed) findings appear;
  found fingerprints are filtered inside the property so each round hunts
  news.
- **native** (`driver.jl`): `Xoshiro(seed)` per candidate, so one integer
  reproduces any candidate. The only engine with the crash-safe journal —
  use it when hunting worker crashes.

Either way, shrunk source is the reproducer of a *finding*.

### Execution & oracle (`execute.jl`, `classify.jl`)

Fresh anonymous modules are the reset mechanism (the cheap REPRL analogue).
The interpreted side runs the production toplevel path — `ExprSplitter`,
`Frame(mod, ex)`, `RecursiveInterpreter` — under a statement budget: a
trimmed port of `evaluate_limited!` from `test/utils.jl`. Verdict classes:

| class | meaning |
|---|---|
| `value_divergence` | observation streams differ at index k |
| `exception_divergence` | both threw, different exception types (messages are allowed to drift) |
| `interp_only_throw` / `ref_only_throw` | one side threw, the other completed |
| `aborted` | interp budget exhausted, observation prefix consistent → discard (tracked) |

A mismatched observation *prefix* on an aborted run is still a
`value_divergence`. Dedup fingerprints are `(class, ref exc, interp exc)` —
no messages (drift across Julia versions), no divergence index (moves under
shrinking). `SUPPRESSIONS` in `driver.jl` holds predicates for known-reported
findings so reruns only surface news.

### Shrinking (`shrink.jl`)

Greedy passes: statement removal (any nesting depth), loop-bound zeroing,
subexpression → inert default of the same summary. After every edit a
**repair** pass replaces references to unbound names with defaults and
cascades statement removals — but repair only needs to be *usually* valid:
each candidate re-runs and is kept only if the finding's fingerprint is
preserved, which is the soundness argument. The selftest plants a canary
divergence (interpreter frames are visible in `stacktrace()` — a real,
permanent difference) inside 50+ statements of noise and requires the
shrinker to reduce it while preserving the fingerprint.

## Known false-positive classes found and closed during shakedown

- **`===` on Float operands (NaN payloads).** The fuzzer surfaced a
  `value_divergence` where `min(NaN, NaN) === (NaN + NaN)` evaluated to
  different results under compilation vs. interpretation. Root cause: the
  particular NaN an operation yields (its sign/payload bits) is not part of
  Julia's contract — `min` may return either NaN argument, and compiled
  codegen and the interpreter can pick differently, so a *bitwise* `===`
  between two float expressions is nondeterministic across the two engines.
  Not an interpreter bug. Closed by restricting the `===` rule to
  Int/Sym/Str/Bool operands. Bare-float value observations remain fair, as
  `isequal` treats all NaNs as equal (only `===`/`reinterpret` expose
  payloads, and the sole `reinterpret` probe is on a fixed constant).
- **`Core.Intrinsics.sdiv_int(_, 0)`.** Uncatchable SIGFPE that killed the
  worker; both sides trap identically. Removed from the probe dictionary
  (see the builtins section).

## Sources of legitimate divergence (excluded or normalized)

Excluded from the grammar: I/O, `eval`/`include`, `ccall`/pointers/`unsafe_*`,
tasks/threads (see roadmap), timing, `objectid`, method redefinition.
Normalized away: module names, closure/struct type identity, function values.
Handled: RNG (both sides could seed identically; the grammar currently
doesn't call `rand`), stack depth (fueled recursion keeps it shallow;
`StackOverflowError` asymmetries would classify as `exception_divergence`
and belong in `SUPPRESSIONS` if hit).

## Roadmap

- **M2 — widen the grammar** (done, see wave-2 above, except:)
  destructuring, do-blocks, `@generated` functions, parametric structs,
  inner constructors, defaults referencing earlier params. CI: a time-boxed
  nightly job that uploads `findings/` as artifacts and exits 2 on news.
- **M3 — feedback + debugger axis**: a `CoverageInterp <: Interpreter`
  recording which stmt heads/builtins/intrinsics/dispatch paths each case
  touches (cheap semantic coverage: report grammar gaps, bias seeds);
  fuzz `debug_command` scripts (`:n`/`:s`/`:until`/`:finish` + random
  breakpoints) over the same programs, asserting no internal error and
  final-value agreement. Structured concurrency subset (`@sync`/`@async`,
  `fetch`, bounded `Channel`, `-t1`, observations only from the root task) —
  noting task bodies escape interpretation (the scheduler, not interpreted
  code, invokes them), so the surface is task setup, `@sync` lowering,
  exception propagation, and `:enter`/`:leave` interaction with task
  switches.
- **M4 — pluggable lowerer**: the harness's lowering step as an injectable
  function; a JuliaLowering.jl configuration to flush out flisp-idiom
  assumptions in `construct.jl`/`commands.jl` before Base switches lowerers.

## Design decisions log

- **Why not generate `CodeInfo` directly (full Rustlantis)?** Two reasons:
  synthetic IR pushed through codegen fuzzes Julia's codegen/verifier, not
  the interpreter; and JuliaInterpreter pattern-matches *the idioms flisp
  lowering actually emits*, so synthetic-but-never-emitted IR yields
  unfixable false alarms while missing the real bug class. Surface programs
  + real lowering keep every finding actionable.
- **Why source text as interchange?** Repro/journal files contain literally
  what ran; both sides parse identically; renderer bugs surface as parse
  failures in the selftest, not as silent semantic skew.
- **Why keep the native engine alongside Supposition?** The repairing IR
  shrinker and seeded-RNG loop are needed for journal-recovered crash cases
  (Supposition shrinks in-process, so a candidate that kills the worker
  can't be shrunk by replay), and a single-integer seed is the most robust
  reproducer for "the process died". Supposition is the default engine:
  same generator, routed through a choice-recording `AbstractRNG` adapter,
  which gets Hypothesis-style replay shrinking without a second generator
  implementation.
- **Budget exhaustion is a discard, not a finding, in v1.** With
  `RecursiveInterpreter` even small programs execute large amounts of
  interpreted Base code; distinguishing "expensive" from "interpreter hang"
  needs calibration data first. The `aborted` rate is tracked in campaign
  stats; if it creeps up, raise `--budget` or shrink `Cfg` sizes.
