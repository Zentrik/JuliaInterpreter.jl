# FuzzJI: differential fuzzing of JuliaInterpreter against compiled Julia

> **Picking this up?** Start with [`NEXT.md`](NEXT.md): current state of each
> axis, the ranked work list, and the calibration traps that cost the most
> time. This file explains how the harness works; `yield-analysis.md` explains
> why it is built this way.

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
julia --project=fuzz fuzz/run.jl --engine split --n 5000          # adversarial toplevel forms (ExprSplitter)
julia --project=fuzz fuzz/run.jl --engine native --n 5000 --big --fresh  # larger programs, re-report known buckets
julia --project=fuzz fuzz/metrics.jl --n 500                    # what the generator actually produces
julia --project=fuzz fuzz/coverage.jl --n 400 --engine native,step,evalcode,corpus --modes rec,cmp
                                                                # what a campaign actually reaches in src/
```

Generator size is configurable from the CLI (`--big`, `--maxblockdepth`,
`--maxblockstmts`, `--maxdepth`, `--maxloop`, `--bodystmts LO:HI`);
`fuzz/metrics.jl` reports the resulting distribution without executing
anything, which is the fast way to check whether a grammar change did what
you meant, and `fuzz/coverage.jl` reports what a campaign of those programs
actually reaches inside `src/` (line coverage of the interpreter via julia's
own `--code-coverage`, mapped onto `builtins.jl` dispatch arms and enclosing
functions; writes `fuzz/coverage-report.md`) — which is the slower but more
decisive check on the same question. `--fresh` stops pre-seeding the dedup set from `findings/` (coarse
buckets otherwise let an already-reported finding mask new ones), `--patience
K` keeps a Supposition campaign going for K consecutive empty rounds, and
`--nosync` drops the per-candidate journal fsync for throughput. `--noshrink`
reports findings unminimized on every axis; `--shrinkruns N` / `--shrinksecs S`
move the per-finding shrink budget.

Findings land in `fuzz/findings/<class>-<fingerprint>/` as a standalone
`repro.jl` (runs with `julia --project=fuzz repro.jl`) plus `meta.md` with the
original and shrunk programs. For long unattended runs wrap `run.jl` in a
restart loop; `fuzz/journal/current.jl` always holds the candidate that was
executing, written and fsync'd *before* execution, so even a segfault leaves a
reproducer.

`fuzz/triage.jl` is the first thing to run on any of them:

```sh
julia --project=fuzz fuzz/triage.jl fuzz/findings/<dir>/     # or any candidate .jl
```

It runs each side alone in its own `julia` under a timeout, so *which side
broke* is answered by exit status rather than by reading a backtrace, and — if
the reference side is what broke — re-runs it under the newest installed Julia
(`julia +release`) to answer "already fixed upstream?" before anyone starts
minimizing. A reference-side crash is a **Julia** bug, not a JuliaInterpreter
one. Given a findings directory it also writes `triage.md` there.

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
                  dedup (fingerprint) → shrink (predicate-driven) → report
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

- a **reflection-driven builtins/intrinsics prober** (`probes.jl`, see below),
  always guarded so the exception *type* is oracle data — aimed directly at
  `src/builtins.jl`;
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
  `src/builtins.jl` hand-dispatches. The prober carries recipes for the whole
  atomics field family (`swapfield!`/`modifyfield!`/`replacefield!`/
  `setfieldonce!`, right and wrong arities, ordering violations on non-atomic
  fields), for `invoke`/`invokelatest`, and fixed templates for opaque
  closures (`:new_opaque_closure` is a dedicated interpreter path) and
  `Memory` basics;
- **`try`/`catch`/`else`** (distinct 1.8+ lowering); struct aliasing (mutation
  through one name observed through another); mixed Int/Float arithmetic
  (promotion); **wrong-typed guarded calls** into generated functions
  (MethodError construction / localmethtable misses, and errors thrown deep
  inside interpreted callees propagating through interpreted frames).

Determinism-unlock grammar (`determinism.md` §3/§4; gated by the `:rng`/`:dict`/
`:vtime` swarm features and a `:determinism` policy):

- **explicit RNG.** `const __RNG__ = Xoshiro(seed)` is baked into the rendered
  program as a *literal* seed (`Program.rngseed`, `render.jl`) — not a harness
  global — so both engines seed identically and run the same pure-Julia Xoshiro
  transitions, agreeing bit-for-bit (`SETUP_SRC` gains `using Random`). Rules
  `rand(__RNG__, Int)`, `rand(__RNG__, 1:n)`, `rand(__RNG__, Bool)`,
  `rand(__RNG__)`, `randn(__RNG__)` feed the Int/Float/Bool expression menus, so
  rand-derived values reach guarded indices, `if`/`while` conditions, and a
  rand-derived `for` trip count (`for i in 1:rand(__RNG__, 0:maxloop)`) —
  data-dependent control flow the guarded rules previously lacked. Termination
  stays by construction: rand supplies loop *counts* (capped at `maxloop`),
  never while-fuel;
- **content-keyed `Dict`/`Set`** (new `DictT`/`SetT`/`CharT` summaries), keyed
  by the content-hashed whitelist — Int/String/Symbol/Char/Bool and tuples of
  those — whose `hash` is identical across the two engines, so iteration order
  is too and the *full value oracle* applies (not the failure-mode one). Rules
  for construction, `get`/`get!`/`haskey`/`in`/`length`, `setindex!`
  (`d[k]=v`)/`delete!`/`push!`, and `keys`/`values`/whole-container/`length`
  observations; `__fjnorm__` normalizes `AbstractDict`/`AbstractSet` to sorted
  normalized contents. Mutable/objectid-keyed containers (class X) are
  unreachable — the key menus never offer a mutable summary;
- **virtual clock.** `__vtime__()` (a monotone counter in `SETUP_SRC`) is in the
  Int menu, so deadline/elapsed-shaped control flow (`while __vtime__() < N`,
  fuel still governing termination) becomes generable. Deterministic because
  both sides call it the same number of times in the same order. The ENV/fs
  doubles from `determinism.md` §3 are deferred (NEXT.md item 5).

### The builtins prober (`probes.jl`)

`src/builtins.jl` is itself *generated*, by `bin/generate_builtins.jl`, which
enumerates every `Core.Builtin` and every `Core.Intrinsics` function by
reflection and emits one dispatch arm per callable. The prober consumes the
same enumeration from the other side, so the fuzzer's notion of "what the
interpreter special-cases" cannot drift from the interpreter's:

- **Enumerate**, at harness load, every builtin-valued name in
  `names(Core; all=true)`, every intrinsic in `names(Core.Intrinsics; all=true)`,
  and the Base-level entry points that are builtins on some versions
  (`invokelatest`, `invoke_in_world`, `isdefinedglobal`). Every lookup is
  `isdefined`-guarded, so the target list is version-relative. Both spellings
  of a callable are kept (`getfield` and `Core.getfield`) because they lower
  differently — a direct `GlobalRef` versus a `getproperty` chain that puts an
  SSA value in function position, two different routes into
  `maybe_evaluate_builtin`. On 1.11.9 this is 269 spellings, 210 of them
  probeable.
- **Arity sweep** from the compiler's own `T_FFUNC_VAL`/`T_IFUNC` tables — the
  same tables `generate_builtins.jl` uses to decide how many per-arity clauses
  to emit — with off-by-one and outright malformed arities mixed in for
  builtins.
- **Arguments from the generator**: in-scope generated values (structs,
  vectors, closures, tuples, symbols) mixed with adversarial literals, atomic
  orderings, and type literals. *Intrinsic* argument lists are the exception:
  they are always shaped by name (integers to the integer ops, floats to the
  float ops, width-valid pairs to the casts) because a wrong operand *kind* of
  the right width corrupts the heap silently — see below. Recipes
  (`PROBE_RECIPES`, ~120 argument shapes over ~45 builtins) give the
  high-value ones — `getfield`/`setfield!`/
  `apply_type`/`fieldtype`/`isdefined`/`tuple`/`_apply_iterate`/`invoke`/
  `invokelatest`/the atomics field family/the global-binding family —
  *plausible* shapes some of the time, so probes exercise success paths and
  not only the MethodError/TypeError arms. `FIXED_PROBES` keeps the curated
  templates that are not a plain `callee(args...)` call (opaque closures,
  `Memory` basics, `first(Core.modifyfield!(...))`).
- **A safety denylist** (`PROBE_BANS`) with a reason string per entry, because
  a bad probe does not produce a finding — it kills the worker or poisons the
  oracle. `:all` entries are never rendered; `:arbitrary` entries are
  reachable only through a vetted recipe. See "known false-positive and
  worker-death classes" below for the measurements behind them.

`fuzz/metrics.jl` reports enumerated / allowed / denylisted counts, the recipe
inventory, and probe density plus distinct-callable coverage under the
`builtins` policy — the numbers that say whether a grammar change silently
starved the prober (157 of 210 callables reached across 500 programs).

Calibrating a denylist entry is not a code-reading exercise: every reason
above was *measured*, by executing probe-heavy candidates in a **subprocess**
with the journal armed and reading back the candidate that was running when
the process died — the same restart-loop-plus-journal discipline `longrun.sh`
uses for campaigns. Do that before widening the target set, never in-process:
the failure mode being hunted is precisely the one that takes the worker down
with it. In the 1.5k-candidate soak that closed this work, the three remaining
process deaths were all reference-side *Julia* defects reachable from
`@atomic` struct code with no probe involved: two aborts in the known 1.11
`llvm-alloc-opt` pass (`findings/julia-codegen-abort-allocopt`, reproduced on
the pre-prober checkout as well) and one segfault inside `gc_mark_obj8` during
a collection, which did not reproduce when the same 718-candidate range was
replayed in a fresh process — delayed, nondeterministic heap corruption of the
same family. Probe-attributable deaths (SIGILL from a `Type` in a module slot,
segfaults from empty-argument `_call_latest`/`_apply_pure`, heap corruption
from float intrinsics with integer operands) were all found and closed by this
same loop.

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
| `nondet_discard` | a divergence one of the two sides did not reproduce when re-run → discard (tracked) |

A mismatched observation *prefix* on an aborted run is still a
`value_divergence`. Dedup fingerprints are `(class, ref exc, interp exc,
ref obs-shape, interp obs-shape)` — the shape signatures (guarded-exception
name for `(:__thrown, ...)` observations, type name otherwise) keep unrelated
value divergences from collapsing into one bucket, where the first finding
ever reported would mask all future value bugs as duplicates. Still excluded:
messages (drift across Julia versions) and the divergence index (moves under
shrinking). `SUPPRESSIONS` in `driver.jl` holds predicates for known-reported
findings so reruns only surface news.

**Confirm-on-divergence.** One run of each side is what the oracle consumes; it
is not what a *finding* rests on. When `classify` produces a finding, the gate
(`confirm`/`confirmed`, `classify.jl`) re-runs the reference and compares it
against the reference outcome the verdict was built from — same status, same
exception name, same observation stream elementwise and in length. If the
reference disagrees with *itself*, the candidate is nondeterministic and the
verdict says nothing about the interpreter: `nondet_discard`, tracked next to
`aborted`, never deduped, shrunk or written. If the reference is stable, the
interpreted side is re-run in the same mode and judged the same way. Only
stable divergences continue. After shrinking, the program about to be written
is confirmed once more (fingerprint *and* stability); if it fails, the
pre-shrink program is tried, and if that fails too the candidate is discarded
rather than reported. Cost lands only on the divergence path, so agreement —
every candidate but a handful — pays nothing. Both engines gate at every point
a finding is produced, and `nondet_discard` counts are printed with the
campaign stats. This is `determinism.md` §6, and it is the safety net that lets
future grammar work fail *loudly-but-harmlessly*: a nondeterminism mistake
becomes a tracked discard instead of a false finding.

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

Each candidate's walk runs on its own `Xoshiro(walkseed)`, independent of the
generator's stream, so `(src, walkseed)` fully describes a run — that is what
makes findings on this axis shrinkable and replayable against a *shrunk*
program (see Shrinking, above). `walkseed` is recorded in every finding and can
be replayed by hand with `fuzz/diag_stuck.jl SEED MAXCMDS WALKSEED`.

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

### The ExprSplitter axis (`splitfuzz.jl`)

`--engine split`. `src/construct.jl` has the densest fix history in the package
(9 fix commits), and nearly all of it is `ExprSplitter`: how a chunk of source
is carved into `(module, expression)` pairs that `Frame` can each evaluate.
Every other axis exercises it *incidentally* — the IR generator emits one flat
module, so nested `module` blocks, `baremodule`, toplevel macros, docstrings and
odd declarations never appear, and none of the machinery the fix history is
about ever runs.

This axis therefore does not use the IR grammar at all. It is a **template
combinator** over a seeded RNG that emits toplevel *shapes*: nested `module` and
`baremodule` blocks (with and without `using Base`), bare `begin` blocks —
including the `local`-declaring kind `ExprSplitter` must refuse to descend into
(issue #427) — `if` at toplevel wrapping definitions, macros defined *in the
program* that expand to several statements or to an `Expr(:toplevel, ...)` or to
a bare `global` declaration, `const`/`global`/typed-global declarations in odd
positions, definitions inside nested modules, qualified cross-module references
(`M1.M2.f()`) reached through relative imports, docstrings on
functions/consts/structs/modules, and empty/comment-only sections. Programs
terminate by construction: no loops and no recursion are generated at all.

The oracle is differential against compiled Julia (`Core.eval` per toplevel
statement in a fresh module), in two halves:

| class | meaning |
|---|---|
| `split_internal_error` | compiled Julia ran the program; the `ExprSplitter` path threw, and the throw surfaced inside JuliaInterpreter's own code |
| `split_only_throw` | same, but the throw surfaced outside the package |
| `eval_only_throw` | `Core.eval` threw and the `ExprSplitter` path completed |
| `split_exception_divergence` | both threw, different exception types |
| `split_missing_effect` | both ran (or both threw the same thing) but the resulting **module state** or the observation stream differs |
| `aborted` | statement or fragment budget exhausted → tracked discard |

`split_missing_effect` is the reason this axis exists in its own file. Programs
here mostly *define* things rather than compute them, so the observation stream
is a weak oracle; the strong one is the module tree. After both runs,
`modstate` walks every name defined in the root module and recursively in the
submodules the program created, and normalizes each value the way `SETUP_SRC`'s
`__fjnorm__` does — module, function and type *identity* scrubbed to bare names,
scalars/strings/symbols compared structurally, struct instances compared by type
name plus fields. Excluded: everything starting with `#` (closure/`struct` type
names and the docsystem's gensym'd META binding), each module's automatic
`eval`/`include`/self-binding, and the harness prelude (`__OBS__`, `__obs__`,
`__fjnorm__`). A definition the interpreted path silently skipped — the
historical `ExprSplitter` failure mode — surfaces as a name present on one side
and absent on the other rather than as nothing at all.

Which throw is a finding is decided *only* by the differential, never by the
backtrace (a program-thrown exception unwinds through interpreter frames too);
the innermost JuliaInterpreter function is used solely to split internal errors
into their own dedup buckets. Two harness obligations are worth knowing:
`Base.invokelatest` wraps both `ExprSplitter` and `Frame` construction, because
both expand macros — and the program's own macros, like the prelude's `__obs__`,
were defined after the harness function's world; and the *reference* side is run
first, so a program that is not valid Julia at all (a syntax error) is discarded
rather than compared.

Two divergences are known-legitimate and designed out of the generator rather
than suppressed (suppressing them would also hide a real bug of the same shape):
duplicate `module M` names in one parent, where `find_or_create_module`
deliberately *reuses* the existing module while `Core.eval` replaces it
(documented in the `ExprSplitter` docstring — so every module gets a unique
name); and `module`/bare `global`/define-and-invoke-a-macro inside a
`begin`/`if`, all of which Julia itself rejects, so `ExprSplitter`'s greater
permissiveness there is about invalid input rather than about the interpreter.

### The corpus axis (`corpus.jl`)

`--engine corpus`. A grammar only emits constructs someone wrote a rule for;
real Julia uses generators, `do` blocks, broadcasting, parametric constraints,
iteration protocols, and macros expanding to anything at all. This axis draws
fragments from real source — Julia's own `test/` directory, the stdlib, and
this repo's tests — and splices `1:maxsplice` of them into one module,
producing combinations that exist in no file.

Real code is neither deterministic nor terminating, so the differential
*value* oracle cannot be used on it *in general*. But determinism is a
per-fragment, *measurable* property, so this axis now has **two** oracle paths,
chosen per case by a self-agreement certification step (`determinism.md` §6):

- **Certified → full value oracle.** Before anything else, seed the sandbox RNG
  (`Random.seed!`) and run the fragment under `Core.eval` **twice** in two fresh
  modules, auto-observing its comparable top-level bindings at the end (real
  fragments don't call `__obs__`; only bindings whose normalized value is
  content-comparable are observed — the conservative direction). If the two
  reference runs agree (`outcomeeq`), the fragment is certified observationally
  deterministic *on this input*, and it graduates to the full differential value
  oracle: the interpreted side is run (seeded + observed the same way),
  `classify` compares the streams, and the confirm-on-divergence gate,
  fingerprinting, dedup, shrinking (`corpus_value_keep`) and `writefinding`
  (`reprocorpus` repro) all apply exactly as on the differential axis. A
  seeded-`rand`/`sum` fragment thus becomes a value-compared test of interpreted
  `rand`+`sum` against compiled — which it could not be before.
- **Uncertified → failure-mode oracle (as before).** If the reference disagrees
  with itself (address-derived values, clocks, stdlib-global mutation — the
  deterministic-but-not-idempotent cases), the fragment falls back to the
  **failure-mode-only** oracle: run the fragment with `Core.eval`; if that
  throws, the fragment does not stand alone (a snippet lifted out of a test file
  references names its file imported) and the case is discarded as junk; only
  "compiled Julia ran this and the interpreter did not" is reported, plus the
  stepping invariants from the axis above. Comparing whether execution failed,
  never what it computed, is what makes nondeterministic real code usable.

The confirm-on-divergence gate is the safety net: a certified fragment that is
actually flaky (a stable heap repeating an address-derived value, say) is caught
when the finding fails to re-confirm, and becomes a tracked `nondet_discard`
rather than a false value divergence. A `certified` counter is printed next to
`ran`/`discarded_junk` for the reason those exist — a rate collapse means the
gate broke, not the corpus.

Two mechanisms make this work in practice, both deliberately derived rather
than enumerated:

- **Safety filtering is an AST check, not a text search.** `calls_unsafe`
  walks the expression and looks at what sits in *call position*, reducing
  `f`, `Mod.f` and `f{T}` to a bare name. Substring matching on rendered
  source is wrong in both directions: `myopen(path)` contains `"open("` and
  would be dropped for nothing, while `Base.rm(p)` slips past a search for
  `"rm("`. It is still a policy list, and no static check survives an indirect
  call — the actual guarantee is the crash-safe journal plus a restart loop,
  which already exists for exactly this.
- **Missing imports are recovered from the failure, not guessed.** A fragment
  lifted from Julia's test suite usually does not carry the import it needs,
  because the `runtests.jl` that included it had already done `using Test`. So
  the reference run reads the `UndefVarError`, finds a loaded module that
  exports that name (`supplying_module`), adds the import and retries. No list
  of stdlibs to maintain, and it covers whatever a future corpus directory
  happens to need. Measured on 200 cases: 23% of cases execute using only the
  imports each fragment's own file declared, 49% with repair.

The `ran` vs `discarded_junk` vs `certified` counters exist so those ratios stay
visible: a campaign that discards everything would otherwise report a perfect
100%-agreed line while testing nothing, and a `certified` collapse would mean the
certification gate — not the corpus — broke.

### Shrinking (`shrink.jl`)

**Every axis shrinks before it reports.** What differs between them is the
*property* being preserved, so the shrinker takes it as an argument:
`keep(src::String)::Bool`, "this source still exhibits the finding". The search
strategy is shared; each axis supplies its own oracle.

| axis | `keep` predicate | built by |
|---|---|---|
| `native` / `supposition` | re-run both sides, classify, same fingerprint | `differential_keep` |
| `step` | replay the *same walk seed*, same verdict class + salt | `step_keep` |
| `evalcode` | replay the same pause walk, same check kind | `evalcode_keep` |
| `corpus` (failure-mode) | re-run the fragment, same corpus verdict class | `corpus_keep` |
| `corpus` (certified value) | re-certify + re-run the value oracle, same fingerprint | `corpus_value_keep` |

Two search strategies, both budgeted:

- **`shrink_ir(prog, keep)`** — greedy passes over the generator's IR:
  statement removal (any nesting depth), loop-bound zeroing, subexpression →
  inert default of the same summary. After every edit a **repair** pass
  replaces references to now-unbound names with defaults and cascades
  statement removals — but repair only needs to be *usually* valid: each
  candidate is re-checked against `keep` and rejected if the property is gone,
  which is the soundness argument. `shrink(prog, fp; ...)` is the differential
  axis's entry point, a thin wrapper with `differential_keep`.
- **`ddmin_source(src, keep)`** — delta debugging on *source text*, for
  findings that never had generator IR: corpus fragments, and
  journal-recovered crashes (`crashmin.jl` now drives this same function with
  "the subprocess died by signal" as its property). Chunked deletion at
  toplevel-statement granularity first — a spliced corpus case is several
  fragments and usually only one matters — then recursion into block bodies,
  because a surviving fragment is typically one large `function` or `@testset`.
  Statement granularity rather than crashmin's original line granularity: a
  multi-line `for` is one deletion candidate instead of a run of lines that
  only sometimes cuts on a statement boundary.

**Why the stepping axis needed a seed change first.** The command walk used to
draw from the same RNG the generator had used. That makes the command sequence
a function of the program's size, so deleting one statement changes every later
draw — a shrunk program cannot be replayed and no edit can be judged. Each
candidate now gets its own `walkseed` (drawn from the generator's stream, so a
case still reproduces from its case seed, but consumed through a fresh
`Xoshiro`), which is recorded in the finding's `meta.md`/`repro.jl` and replayed
verbatim on every shrink candidate. The same applies to the eval_code pause walk
and the corpus stepping stage.

Replay does **not** promise an identical command trace: a shorter program has
fewer pause points, so the same draws land on different statements. The
predicate asks for the same verdict *class* and the same fingerprint salt (the
stuck command for `step_stuck`, the innermost JuliaInterpreter function for an
internal error, the divergent observation's shape for `step_divergence`) — which
is what the report is about — never for trace equality.

**Budget.** Shrinking one finding is capped by candidate re-executions *and*
wall clock (`ShrinkBudget`), so a stubborn case cannot stall a campaign; both
loops stop at the cap and return the best candidate so far. `--noshrink`
bypasses shrinking on every axis, `--shrinkruns`/`--shrinksecs` move the caps.
The stepping and eval_code predicates replay a whole command walk per candidate,
so their defaults are lower than the differential axis's.

The selftest covers the search independently of any oracle (a synthetic
string-containment property over a padded program, plus a `ddmin_source`
containment test and budget-cap assertions), keeps the original canary — a
genuine divergence (interpreter frames are visible in `stacktrace()`) planted in
a dozen inert statements, which must shrink to the one divergent observation
while preserving its fingerprint —
and drives one end-to-end step-axis shrink through a deliberately broken oracle
stub, so `generate → step → classify → shrink → writefinding` is exercised
without waiting for a live finding.

## Known false-positive and worker-death classes found and closed

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
- **`Core.Intrinsics.sdiv_int(_, 0)`.** Uncatchable trap that killed the
  worker. Re-measured on 1.11.9 while building the prober: inside a compiled
  toplevel `let` — the shape `render.jl` emits — the raw divides
  (`sdiv_int`/`udiv_int`/`srem_int`/`urem_int`) die with SIGILL ("Unreachable
  reached", exit 132) because codegen lowers the UB to `unreachable`. Denied
  outright. The *checked* family (`checked_sdiv_int` and friends) was measured
  too and does the opposite — DivideError even when compiled — so those stay,
  and they are the intrinsic-level division probe the raw ones cannot be.
- **Out-of-range `unsafe_trunc`.** The result is an *unspecified value*
  (LLVM poison under compilation vs. the runtime intrinsic under
  interpretation), so `unsafe_trunc(Int8, 300.0)` may legally differ across
  the two engines. The probe uses an in-range argument; the same rule bars any
  probe whose contract says "unspecified" — `fptosi`/`fptoui` are recipe-only
  with in-range floats, and the fast-math intrinsics plus `muladd_float`
  (reassociation and fma-contraction licenses) are denied.
- **Wrong-arity *intrinsic* calls abort the process.** A builtin called with
  the wrong number of arguments raises a catchable `ArgumentError`; an
  *intrinsic* call site with the wrong operand count is a codegen error —
  "Internal error: encountered unexpected error during compilation ...
  intrinsic #2 add_int: wrong number of arguments", exit 139 — on the
  reference side, before the interpreter is ever reached. So the prober's
  arity sweep is exact for intrinsics and malformed only for builtins.
- **A float intrinsic handed a same-width integer corrupts the heap.**
  `Core.Intrinsics.ceil_llvm(3)` (and `floor_llvm`, `rint_llvm`, `trunc_llvm`,
  `sqrt_llvm`, `abs_float`, `neg_float`, `add_float`, …) *runs*, returns a
  value on both engines, and then the process dies at the next GC with "GC
  error (probable corruption)". Mismatched operand *widths* are checked and
  raise a catchable error; a mismatched *kind* of the same width is not. This
  is the reason intrinsic arguments are always shaped by name
  (`intrinsic_args`) and never drawn from the generic pool, and the reason an
  intrinsic whose operand kinds are not derivable from its name is withheld
  from the target list rather than probed.
- **Width-relational casts fail at *compile* time, outside the guard.**
  `fptrunc`/`fpext`/`trunc_int`/`sext_int`/`zext_int` check their operand
  widths during compilation when the types are statically known, and that
  error is raised while the enclosing thunk is compiled — outside the
  program's own `try`, so it escapes the guard and shows up as a bogus
  `ref_only_throw`. Every cast shape the prober emits satisfies the relation.
- **Runaway type materialization.** `Core.apply_type(Array, Int, typemax(Int))`
  and `NTuple` with a huge count segfault the runtime, and `typemax(Int)` is in
  the literal menu — so `apply_type` is recipe-only, and the parametric
  constructors whose Int parameter materializes storage (`Array`, `NTuple`,
  `Vararg`, plus `Ptr`) are kept out of the argument pool entirely.
- **Uninitialized `Memory` reads are not deterministic.** `Memory{Int}(undef, n)`
  reads back whatever bytes the allocator handed out, which differs between the
  reference module and the interpreted one — a `value_divergence` made of pure
  heap noise (observed in the first probe soak). The memory recipes fill their
  memory; where an *unset* slot is wanted, they use `Memory{Any}`, whose read
  is a deterministic `UndefRefError`.
- **Unchecked `MemoryRef`s are wild reads and writes.** `memoryrefnew(ref, i,
  false)` with an out-of-range `i` produced a silent out-of-bounds read (and
  `memoryrefset!` a silent out-of-bounds *write*) without crashing — the worst
  kind of failure. The whole `memoryref*` family is recipe-only, every recipe
  passes a literal `true` for the bounds-check flag, and no `MemoryRef` value
  ever enters the generic argument pool.
- **Program-defined types print with their module name.** A probe can return a
  type, and a type the program defined renders as `FJ12.S1` on one side and
  `FJ13.S1` on the other. `__fjnorm__` strips its own module's prefix.
- **Builtins whose argument validity is checked by *codegen*, not by the
  runtime, diverge on invalid arguments.** Two instances, both found by the
  prober and both confined to recipes rather than reported:
  `Core._apply_iterate(f, g, args...)` with `f !== iterate` — compiled Julia
  ignores `f` and applies `g` (`Core._apply_iterate(+, +, (1, 2)) == 3`) while
  `maybe_evaluate_builtin` raises `ErrorException("cannot handle
  `_apply_iterate` with non iterate as first argument")`; and
  `Core.compilerbarrier(:unknown_setting, x)` — an ErrorException from codegen
  compiled, plain `x` from the runtime builtin the interpreter calls. Neither
  argument shape is producible by lowering, so both are known-and-permanent
  rather than news. When probing a builtin whose *compiled* form is a codegen
  special case, expect this class and check what real lowering can actually
  emit before believing the divergence.

## Sources of legitimate divergence (excluded or normalized)

`determinism.md` analyzes this whole area — which exclusions are genuinely
forced (semantic underspecification, cross-engine divergence), which are
cheap to lift (seeded RNG, content-keyed Dicts, API doubles, per-fragment
determinism certification for the corpus axis), and why deterministic-
execution infrastructure (Antithesis-style hypervisors) does not help a
two-engine oracle.

Excluded from the grammar: I/O, `eval`/`include`, `ccall`/pointers/`unsafe_*`,
tasks/threads (see roadmap), timing, `objectid`, method redefinition.
Normalized away: module names, closure/struct type identity, function values,
and the *module prefix of a type name* — `string(T)` is module-qualified, so a
type the program defined reads as `Main.FJ95.ZT` on one side and `Main.FJ96.ZT`
on the other; `__fjnorm__` strips its own module's prefix and keeps the rest
(type parameters included). The split axis produced 16 such false divergences
in 5000 cases before that was fixed.
Handled: RNG — the grammar now calls `rand` through a per-program
`const __RNG__ = Xoshiro(seed)` baked in as a literal, so both engines run the
same Xoshiro transitions and agree bit-for-bit (`determinism.md` §3; the corpus
axis seeds the task-local RNG instead, and certifies per-fragment before value
comparison, §6); content-keyed `Dict`/`Set` and the `__vtime__` virtual clock
are likewise deterministic across the two engines. Stack depth: fueled recursion
keeps it shallow; `StackOverflowError` asymmetries would classify as
`exception_divergence` and belong in `SUPPRESSIONS` if hit.

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
- **M3 — debugger axis** (done): `--engine step` fuzzes `debug_command` walks,
  and `--engine evalcode` fuzzes `eval_code` at paused frames. See the two
  sections above. The *feedback* half of M3 — a `CoverageInterp <: Interpreter`
  recording which statement heads, builtin arms and dispatch paths each case
  touches — is **not** done and is the highest-value remaining item.
- **M3.5 — corpus axis** (done): `--engine corpus` runs and splices real Julia
  source, with an oracle that compares failure mode only so nondeterministic
  code is usable.
- **M3.6 — shrinking on every axis** (done): the greedy IR shrinker takes the
  property as a `keep(src)::Bool` predicate, the stepping/eval_code/corpus
  walks got their own replayable seeds, and corpus findings are minimized by a
  statement-level delta debugger shared with `crashmin.jl`. See Shrinking,
  above. The split axis minimizes with the same delta debugger against a
  same-fingerprint property.
- **M3.7 — ExprSplitter axis** (done): `--engine split` feeds `construct.jl`
  adversarial toplevel forms from a template-combinator generator, with a
  module-tree effect oracle on top of the failure-mode one.
- **Finding-intake hardening** (done, `NEXT.md` item 1, minus the rr step):
  the confirm-on-divergence gate above, and `fuzz/triage.jl` for version-aware
  attribution of what broke.
- Still open, in priority order: semantic coverage (above), throughput, EMI,
  a nightly CI job. Structured
  concurrency (`@sync`/`@async` with observations only from the root task) and
  a **pluggable lowerer** — the lowering step as an injectable function, so a
  JuliaLowering.jl configuration can flush out flisp-idiom assumptions in
  `construct.jl`/`commands.jl` before Base switches lowerers — remain
  unstarted.

**→ See [`NEXT.md`](NEXT.md)** for the full ranked work list, the current
state of each axis, and the calibration traps worth knowing before touching
any of it.

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
