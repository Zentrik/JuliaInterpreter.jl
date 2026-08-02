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
julia --project=fuzz fuzz/run.jl --engine native --modes rec --n 10000  # recursive-interp only
julia --project=fuzz fuzz/run.jl --engine step --n 5000         # debugger/stepping axis
julia --project=fuzz fuzz/run.jl --engine evalcode --n 2000      # eval_code at paused frames
julia --project=fuzz fuzz/run.jl --engine corpus --n 5000        # real Julia source, spliced
julia --project=fuzz fuzz/run.jl --engine native --n 5000 --big --fresh  # larger programs, re-report known buckets
julia --project=fuzz fuzz/metrics.jl --n 500                    # what the generator actually produces
```

Generator size is configurable from the CLI (`--big`, `--maxblockdepth`,
`--maxblockstmts`, `--maxdepth`, `--maxloop`, `--bodystmts LO:HI`);
`fuzz/metrics.jl` reports the resulting distribution without executing
anything, which is the fast way to check whether a grammar change did what
you meant. `--fresh` stops pre-seeding the dedup set from `findings/` (coarse
buckets otherwise let an already-reported finding mask new ones), `--patience
K` keeps a Supposition campaign going for K consecutive empty rounds, and
`--nosync` drops the per-candidate journal fsync for throughput.

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

Wave-3 grammar (aimed at the historically bug-rich interpreter surfaces the
earlier waves designed out):

- **control-flow exits**: conditional `break`/`continue` in loops and early
  `return` in function bodies — including through `try`/`catch`/`finally`,
  which is the `:enter`/`:leave`/`EnterNode` and exception-frame-unwinding
  machinery (`src/interpret.jl`), classically the most bug-dense part of an
  interpreter. Conditional `rethrow()` inside catch handlers. Exits are never
  generated inside `finally` blocks (lowering restrictions + signal drowning).
  Termination is preserved: the `while` fuel decrement renders *before* the
  body, so `continue` cannot skip it;
- **the undefined-variable dimension**: validity-by-construction previously
  made reads of possibly-undefined variables ungenerable — precisely the
  `NewvarNode`/`Expr(:isdefined,...)` surface. Now generated as *guarded,
  expected* observations: `maybeundef` (conditionally-assigned binding, then
  `@isdefined` + a guarded read observing `UndefVarError`) and `loopundef`
  (a fixed template asserting per-iteration slot reset: a body-local must be
  undefined again on iteration 2 even though iteration 1 assigned it);
- **`const` globals** (never reassigned; the 1.12 binding-strictness surface),
  **typed globals** (`global g::Int64 = 0` — every later write goes through
  convert + typeassert against the binding type), **typed locals**
  (`local x::T = v`);
- **`@atomic` struct fields**: atomic get/set/`+=` lower to the
  ordering-carrying `getfield`/`setfield!`/`modifyfield!` builtin arities that
  `src/builtins.jl` hand-dispatches. Probe dictionary extended with the whole
  atomics field family (`swapfield!`/`modifyfield!`/`replacefield!`/
  `setfieldonce!`, right and wrong arities, ordering violations on non-atomic
  fields), `invoke`/`invokelatest`, opaque closures (`:new_opaque_closure` is
  a dedicated interpreter path), and `Memory` basics;
- **`try`/`catch`/`else`** (distinct 1.8+ lowering); struct aliasing (mutation
  through one name observed through another); mixed Int/Float arithmetic
  (promotion); **wrong-typed guarded calls** into generated functions
  (MethodError construction / localmethtable misses, and errors thrown deep
  inside interpreted callees propagating through interpreted frames).

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
`Frame(mod, ex)` — under a statement budget: a trimmed port of
`evaluate_limited!` from `test/utils.jl`. Each candidate runs under **two
interpreter configurations** (`--modes`, default `both`): `rec`
(`RecursiveInterpreter`, everything interpreted) and `cmp` (Compiled mode /
`NonRecursiveInterpreter`: toplevel statements stepped, calls execute
natively — a materially different path through `evaluate_call!` and builtin
dispatch, and nearly free since callees run compiled). The reference runs
once per candidate; findings from the second mode are tagged `cmp-` in their
fingerprint. Verdict classes:

| class | meaning |
|---|---|
| `value_divergence` | observation streams differ at index k |
| `exception_divergence` | both threw, different exception types (messages are allowed to drift) |
| `interp_only_throw` / `ref_only_throw` | one side threw, the other completed |
| `aborted` | interp budget exhausted, observation prefix consistent → discard (tracked) |

A mismatched observation *prefix* on an aborted run is still a
`value_divergence`. Dedup fingerprints are `(class, ref exc, interp exc,
ref obs-shape, interp obs-shape)` — the shape signatures (guarded-exception
name for `(:__thrown, ...)` observations, type name otherwise) keep unrelated
value divergences from collapsing into one bucket, where the first finding
ever reported would mask all future value bugs as duplicates. Still excluded:
messages (drift across Julia versions) and the divergence index (moves under
shrinking). `SUPPRESSIONS` in `driver.jl` holds predicates for known-reported
findings so reruns only surface news.

### The stepping axis (`stepfuzz.jl`)

A second axis with a different target and a different oracle. The differential
axis above tests run-to-completion semantics — the surface `test/juliatests.jl`
(Julia's own test suite under the interpreter) and every Debugger.jl/Revise
user already exercise heavily. The *debugger* machinery is not covered by any
of that, and it is where this package's bugs historically are: counting fix
commits per file, `construct.jl` (9), `utils.jl`/`eval_code` (7),
`commands.jl` (3) and `breakpoints.jl` (3) against `interpret.jl` (4) and
`builtins.jl` (2).

`--engine step` generates the same programs, then drives each `ExprSplitter`
fragment through a **random `debug_command` walk** (`:n :s :c :finish :nc :se
:si :until :sl :sr`, including the thinly-tested "advanced" commands, with
`:until` sometimes given an out-of-range line, and break-on-error armed half
the time) instead of running it. Stepping has no compiled counterpart to diff
against, so the oracle is the set of invariants a debugger must satisfy
whatever the user types:

| class | meaning |
|---|---|
| `step_divergence` | stepping to completion produced different observations than plain interpretation: the debugger executed or skipped the wrong statements |
| `step_only_throw` | stepping threw where plain interpretation of the same program completed |
| `step_exception_divergence` | stepping threw a different exception than plain interpretation |
| `step_stuck` | a command left execution at the same `(framecode, pc)` `STUCK_LIMIT` times running, having returned a normal pc each time |

The third is the subtle one and the reason this axis exists: several past
fixes (`next_line!` stopping on assignment-only lines, the
argument-destructuring preamble, self-field-access wrappers) are all "the
debugger ran the wrong statements", which nothing detects without comparing
the stepped observation stream against the plain one.

`step_internal_error` fingerprints are salted with the innermost
JuliaInterpreter function in the backtrace, so distinct internal errors don't
collapse into one dedup bucket.

One harness obligation worth knowing: the walk refreshes `frame.world` on
toplevel frames before each command, mirroring what the interpreter's own
toplevel loop does (`src/interpret.jl`) and what the differential executor
does. `debug_command` has no toplevel loop of its own, so without this every
method the program defines at runtime — including the harness's `__obs__` in
the fresh module — is "too new" for the frame's world.

### The eval_code axis (`evalcodefuzz.jl`)

`--engine evalcode`. `eval_code(frame, "x")` is what a debugger's prompt calls
when you type a variable name at a pause, and `eval_code(frame, "x = 3")` is
what it calls when you assign one. Making that work means building a `let`
around the frame's locals, evaluating in it, and writing results *back* into
the right slots — including static parameters and captured closure variables.
`utils.jl` carries the second-densest fix history in the package (7 commits),
one of them literally "Fix eval_code writing static parameters back to the
wrong slots", and nothing tests it beyond ~33 hand-written cases.

Programs are stepped to a series of pause points; at each one:

| class | meaning |
|---|---|
| `evalcode_read_mismatch` | `eval_code(frame, name)` disagrees with the value `locals(frame)` reports — the debugger is lying about program state |
| `evalcode_write_lost` | after `eval_code(frame, "x = v")`, reading `x` back does not give `v` |
| `evalcode_collateral_write` | that assignment changed a *different* local — the shape of the static-parameter bug |
| `evalcode_internal_error` | `eval_code`/`locals` threw from inside JuliaInterpreter |

No determinism is required, so this works at any pause in any frame.

### The corpus axis (`corpus.jl`)

`--engine corpus`. A grammar only emits constructs someone wrote a rule for;
real Julia uses generators, `do` blocks, broadcasting, parametric constraints,
iteration protocols, and macros expanding to anything at all. This axis draws
fragments from real source — Julia's own `test/` directory, the stdlib, and
this repo's tests — and splices `1:maxsplice` of them into one module,
producing combinations that exist in no file.

Real code is neither deterministic nor terminating, so the differential
*value* oracle cannot be used on it. The oracle is differential on **failure
mode only**: run the fragment with `Core.eval`; if that throws, the fragment
does not stand alone (a snippet lifted out of a test file references names its
file imported) and the case is discarded as junk. Only "compiled Julia ran
this and the interpreter did not" is reported, plus the stepping invariants
from the axis above. Comparing whether execution failed, never what it
computed, is what makes nondeterministic real code usable as input.

Two things that matter in practice: a denylist keeps fragments with side
effects (I/O, processes, threads, `ccall`) and unbounded blocking out of the
corpus, and definitions of another module's methods are skipped since they
would leak between cases. The sandbox module imports `Test`, `Random`,
`LinearAlgebra`, `Dates` and `Printf` — without that prelude, 128 of 150 cases
were discarded for missing names; with it, roughly half of all cases execute.
The `ran` vs `discarded_junk` counters exist so that ratio stays visible: a
campaign that discards everything would otherwise report a perfect
100%-agreed line while testing nothing.

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
- **Out-of-range `unsafe_trunc`.** The result is an *unspecified value*
  (LLVM poison under compilation vs. the runtime intrinsic under
  interpretation), so `unsafe_trunc(Int8, 300.0)` may legally differ across
  the two engines. The probe now uses an in-range argument; the same rule
  bars any future probe whose contract says "unspecified" (fptosi of NaN,
  etc.).

## Sources of legitimate divergence (excluded or normalized)

Excluded from the grammar: I/O, `eval`/`include`, `ccall`/pointers/`unsafe_*`,
tasks/threads (see roadmap), timing, `objectid`, method redefinition.
Normalized away: module names, closure/struct type identity, function values.
Handled: RNG (both sides could seed identically; the grammar currently
doesn't call `rand`), stack depth (fueled recursion keeps it shallow;
`StackOverflowError` asymmetries would classify as `exception_divergence`
and belong in `SUPPRESSIONS` if hit).

## Roadmap

- **M2 — widen the grammar** (done, see wave-2 above).
- **M2.5 — wave 3** (done, see wave-3 above): control-flow exits through
  try/finally, the undefined-variable dimension, const/typed globals, typed
  locals, `@atomic` fields + atomics/opaque-closure/invoke probes,
  try/catch/else, wrong-typed guarded calls, the `cmp` (Compiled-mode)
  differential axis, and shape-salted fingerprints. Still open from M2:
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
