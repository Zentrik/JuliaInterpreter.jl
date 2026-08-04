# Triage: nightly CI fuzz findings (run 30854168537, `fuzz-findings-julia-nightly`)

Scope: the ~20 new `corpusvalue-interp_only_throw-*` entries,
`corpus-corpus_internal_error-6eea3f32`, and `step-step_divergence-7e03896b`.
Entries already present in `fuzz/findings/` (254b14e6, 938d349c, d4a272b3) were
skipped as known; all `call-*` entries were out of scope per instructions.

Environments used for triage:

- findings produced on **Julia 1.14.0-DEV.2866**; re-run on **1.14.0-DEV.2867** (`julia +nightly`)
- current release check on **Julia 1.12.6** (`julia --project=fuzz`)

Every "repro" below is the finding's own `repro.jl` executed as written
(temporarily staged under `fuzz/findings/`, since the artifact lives outside the
repo; staging removed afterwards).

**Bottom line: nothing in scope is a current-release (1.12) interpreter bug.**
One real, fixable JuliaInterpreter incompatibility with the Julia-nightly
TypeEgal change accounts for 17 of the 23 entries (early warning, one-line fix
identified and validated); the remaining 6 are two known harness-artifact
classes.

## Table: finding → group → verdict

| finding dir | interp exception | group | repro on nightly | repro on 1.12 | verdict |
|---|---|---|---|---|---|
| corpusvalue-interp_only_throw-2e995e2e | FieldError (TypeEgal.name) | G1 | REPRODUCED | clean | nightly-only early warning |
| corpusvalue-interp_only_throw-369a1a15 | FieldError (TypeEgal.name) | G1 | REPRODUCED | — | nightly-only early warning |
| corpusvalue-interp_only_throw-38d8f680 | FieldError (TypeEgal.name) | G1 | REPRODUCED | — | nightly-only early warning |
| corpusvalue-interp_only_throw-3e490a20 | FieldError (TypeEgal.name) | G1 | REPRODUCED | — | nightly-only early warning |
| corpusvalue-interp_only_throw-4296f9bb | FieldError (TypeEgal.name) | G1 | (by signature; same `@test_deprecated SubString` fragment as 2e995e2e) | — | nightly-only early warning |
| corpusvalue-interp_only_throw-68772a40 | FieldError (TypeEgal.name) | G1 | (by signature; same fragment as 2e995e2e) | — | nightly-only early warning |
| corpusvalue-interp_only_throw-8570a4e1 | TestSetException (wraps StackOverflowError) | G1 | REPRODUCED | clean | nightly-only early warning |
| corpusvalue-interp_only_throw-8251c76c | TestSetException (wraps StackOverflowError) | G1 | REPRODUCED | clean | nightly-only early warning |
| corpusvalue-interp_only_throw-1118e055 | TestSetException (wraps SOE) | G1 | REPRODUCED (repro process dies SIGSEGV, exit 139) | — | nightly-only early warning |
| corpusvalue-interp_only_throw-4d01f95f | TestSetException (wraps SOE) | G1 | SOE loop observed; repro wedges | — | nightly-only early warning |
| corpusvalue-interp_only_throw-29b68608 | StackOverflowError | G1 | SOE loop observed; repro wedges | — | nightly-only early warning |
| corpusvalue-interp_only_throw-681a52c7 | StackOverflowError | G1 | REPRODUCED (SIGSEGV, exit 139) | — | nightly-only early warning |
| corpusvalue-interp_only_throw-9a474084 | StackOverflowError | G1 | SOE loop observed; repro wedges | clean | nightly-only early warning |
| corpusvalue-interp_only_throw-95f4c45e | StackOverflowError | G1 | under-reproduces standalone (missing corpus prelude); grouped by signature | — | nightly-only early warning |
| corpusvalue-interp_only_throw-5ef206a9 | StackOverflowError | G1 | under-reproduces standalone; grouped by signature | — | nightly-only early warning |
| corpusvalue-interp_only_throw-4a71d7bd | TestSetException | G1 | under-reproduces standalone (Dates prelude missing); grouped by signature | — | nightly-only early warning (unconfirmed member) |
| corpusvalue-interp_only_throw-4e46a47b | TestSetException | G1 | under-reproduces standalone; identical testset to 8251c76c which reproduced | — | nightly-only early warning |
| corpusvalue-interp_only_throw-6bebe5e8 | FallbackTestSetException | G1? | under-reproduces standalone (`@doc` probe interpreted OK in isolation) | — | unconfirmed; expected to clear with the G1 fix — re-check on next nightly run |
| corpusvalue-interp_only_throw-44cfda26 | FallbackTestSetException | G2 | both sides UndefVar (shrunk lost `using Test`) | both sides UndefVar | harness artifact (already filtered) |
| corpusvalue-interp_only_throw-d408c513 | FallbackTestSetException | G2 | (identical shrunk program to 44cfda26) | — | harness artifact (already filtered) |
| corpusvalue-interp_only_throw-7ebe3317 | FallbackTestSetException | G2 | test evaluated `[:child,:parent,:grandparent] == [:bypass_builtins, :evaluate_call!, :evaluate_call!]` | — | harness artifact (already filtered) |
| corpus-corpus_internal_error-6eea3f32 | FallbackTestSetException "in maybe_evaluate_builtin (builtins.jl:464)" | G2 | both sides UndefVar standalone; same stacktrace fragment as 44cfda26 | — | harness artifact (already filtered) + misattributed site |
| step-step_divergence-7e03896b | none (observation mismatch) | G3 | REPRODUCED | REPRODUCED (same artifact, not an interp bug) | harness artifact (normalization gap) |

## Group G1 — JuliaInterpreter dispatch broken by Julia nightly's TypeEgal kind change (17 findings)

**Verdict: nightly-only early warning. Real JuliaInterpreter bug against 1.14-DEV, absent on 1.12. Fix in src/, one line.**

### Root cause

On Julia 1.14 nightlies `Type{T}` is its own kind (`Core.TypeEgal`,
JuliaLang/julia#61915): a `Type{...}` value is a `TypeEgal` instance,
`typeof(Type{Int})` is `TypeEq`, and `.name`/`.body` access on such objects is
served by deprecation shims dispatching on `::TypeEq`
(`getproperty(x::TypeEq, s::Symbol)` at `deprecated.jl:607`).

JuliaInterpreter builds the dispatch signature for every interpreted call with

```julia
# src/utils.jl:27
_Typeof(x) = isa(x, Type) ? Type{x} : typeof(x)
```

For a `Type{...}` receiver `recv` (a TypeEgal instance), `_Typeof(recv)`
produces old-style `Type{recv}` — which on the TypeEgal nightly **no longer
subtypes `TypeEq`**, so `whichtt`/`prepare_call` resolves methods that dispatch
on `::TypeEq` to the *generic fallback* instead. Measured on 1.14.0-DEV.2867:

```
which(getproperty, Tuple{Type{Core.TypeEgal{SubString{String}}}, Symbol}) → Base_compiler.jl:52   (generic getfield fallback — WRONG)
which(getproperty, Tuple{Core.Typeof(recv), Symbol})                      → deprecated.jl:641      (TypeEgal shim — what compiled runs)
```

Two presentations, one cause:

1. **FieldError** — the mis-dispatched fallback executes
   `getfield(::Core.TypeEgal, :name)` →
   `FieldError: type Core.TypeEgal has no field `name`, available fields: `T``.
   Interpreted stack at the error (via `break_on(:error)`):
   `Base.getproperty (Base_compiler.jl:52)` ← `Base.SubString (deprecated.jl:675)`
   — i.e. Base's own `@deprecate`d `SubString{T}(s,i,j,Val(:noshift))`
   constructor accesses `.name` on a `Type{...}` object; compiled Julia hits the
   shim, the interpreter hits the raw-getfield fallback.
2. **StackOverflowError** (surfacing bare, or wrapped in
   `TestSetException`/`FallbackTestSetException` when inside/outside a
   `@testset`) — the same mis-dispatch inside type-manipulating Base code sends
   interpretation into unbounded recursion. Consistent with the existing note in
   `src/packagedef.jl` ("Recursive interpretation … overflows while traversing
   the TypeEgal-based type implementation on Julia 1.14 nightlies"). Two of
   these repros overflow hard enough to kill the julia process (exit 139), and
   several wedge in repeated SOE-recovery — so this class also produces
   harness-side hangs/crashes on the nightly lane.

### Minimal trigger (nightly, no fuzz harness needed)

```julia
using JuliaInterpreter
@interpret SubString{String}("abcd", 0, 1, Val(:noshift))
# ERROR: FieldError: type Core.TypeEgal has no field `name`, available fields: `T`
```

### Fix, validated

`Core.Typeof` computes the correct most-specific type on all versions
(identical to `_Typeof` on ≤1.13; TypeEgal-aware on 1.14-DEV). Replacing the
method in-memory:

```julia
Core.eval(JuliaInterpreter, :(_Typeof(x) = Core.Typeof(x)))
```

- minimal trigger: FieldError → returns `"a"` ✔
- 2e995e2e repro (FieldError group): DIVERGENCE → NO DIVERGENCE ✔
- 8570a4e1 repro (SOE-in-testset group): DIVERGENCE → NO DIVERGENCE ✔
- 8251c76c repro (SOE-in-testset group): DIVERGENCE → NO DIVERGENCE ✔
- (9a474084 with the fix did not finish inside 900 s — its fragment iterates
  every float exponent interpreted — but its unfixed run SOE-loops, and the
  class fix is validated by the three above)

### Repro status

- Nightly (1.14.0-DEV.2867): reproduced for 2e995e2e, 369a1a15, 38d8f680,
  3e490a20 (FieldError) and 8570a4e1, 8251c76c, 1118e055, 681a52c7 (SOE);
  29b68608 / 9a474084 / 4d01f95f visibly SOE-loop; 5 members under-reproduce
  standalone because their shrunk corpus fragments depend on prelude modules
  (`.Main.OffsetArrays`, Dates, `using Test`) the standalone repro can't load —
  they are grouped by exception signature and, for 4e46a47b, by an identical
  testset to a reproducing member.
- 1.12.6: **clean** on every member checked (2e995e2e, 8570a4e1, 8251c76c,
  9a474084) — NOT a current-release bug.

### Recommended action

Fix in `src/`: change `src/utils.jl:27` to use `Core.Typeof` (e.g.
`_Typeof(x) = Core.Typeof(x)` or `const _Typeof = Core.Typeof`), with a
regression test (the minimal trigger above, plus an interpreted
`Base.Rounding.setrounding_raw`/`rounding` round-trip). This is the only
old-style `Type{x}` signature construction in `src/` (all other call sites —
`interpret.jl:409/460`, `construct.jl:393/426`, `breakpoints.jl:155`,
`utils.jl:877` — route through `_Typeof`). No upstream report needed: the
TypeEgal deprecation shims behave as designed; the interpreter was building
pre-TypeEgal dispatch types. After fixing, re-run the nightly lane; expect all
17 to stop re-deriving (and check 6bebe5e8 specifically — see below).

`6bebe5e8` is the one member not confirmed: its `@doc`-comparison fragment
under-reproduces standalone and an isolated interpreted `Docs.doc(Binding)`
probe passed. Its signature (interp-only test *error* on nightly) fits G1;
if it re-derives after the `_Typeof` fix it needs its own look.

## Group G2 — stacktrace-introspection fragments (4 findings: 44cfda26, d408c513, 7ebe3317, 6eea3f32)

**Verdict: harness artifact, already closed at admission. No interpreter bug on any version.**

All four shrunk programs contain the same Julia-testsuite fragment
(`Serialization, Base.StackTraces`; `@noinline child()=stacktrace()` →
`parent` → `grandparent`) asserting frame names/line numbers of a captured
`stacktrace()`. Under interpretation the captured stack legitimately contains
interpreter frames; 7ebe3317's nightly re-run shows the failing assertion
verbatim:

```
Evaluated: [:child, :parent, :grandparent] == [:bypass_builtins, :evaluate_call!, :evaluate_call!]
```

This is the documented backtrace-introspection false-positive class; the
2026-08-04 session's `corpus_ok` filter (rejecting `stacktrace`/`backtrace`/
`catch_backtrace`/`catch_stack`/`current_exceptions` in call position) already
blocks these fragments at admission, so they cannot re-derive.

`6eea3f32` is the same fragment surfacing through the corpus *failure-mode*
oracle, which labeled it `corpus_internal_error` "in maybe_evaluate_builtin
(builtins.jl:464)". `builtins.jl:464` is the `f === throw` forwarding arm — the
fragment's own `throw` (Test's error rethrow), not interpreter-internal code.
Minor harness improvement worth making: `internalframe` site attribution in
`fuzz/src/corpus.jl` should not credit the `throw` builtin-forwarding line as
an internal-error site.

Recommended action: none (delete/ignore the findings); optionally the
`internalframe` tweak above.

## Group G3 — step-step_divergence-7e03896b: module name leaks through `string()` observations (1 finding)

**Verdict: harness artifact (observation-normalization gap). Reproduces on nightly *and* 1.12, but the interpreter's behavior is identical on both sides — only the sandbox module's name differs.**

The program observes a string built by interpolating a struct value:
`__obs__(string(-7, …, f9(...)))` where `f9` can return `S1(...)`. `string` of
a struct instance prints its *module-qualified* type and closure names, and the
two sides run in different fresh modules, so the streams differ in exactly one
observation:

```
run=     "-70Main.ReproRef.S1(false, Main.ReproRef.var\"#5#6\"())"
stepped= "-70Main.ReproInterp.S1(false, Main.ReproInterp.var\"#5#6\"())"
```

(campaign form: `Main.FJ2367.…` vs `Main.FJ2368.…`; every other observation in
the 28-element stream is identical). This is the known "normalization gaps hide
in the rare observation branches" class — `__fjnorm__` already strips the
module's own prefix for `x isa Type` observations but passes `String`s through
untouched, and this latent gap affects every axis that compares two fresh
modules (the standalone repro shows the same artifact between its Ref/Interp
modules on both Julia versions).

Recommended action: filter in harness — extend the `__fjnorm__` String branch
(in `SETUP_SRC` in `fuzz/src/render.jl` and its hand-synced copy in
`fuzz/reprolib.jl`) to `replace(x, string(@__MODULE__) * "." => "")`, the same
trick the Type branch already uses. (Alternative: bar struct-valued arguments
from the generator's `string(...)` rule — narrower, fixes only the generated
axes.) Not an interpreter bug; do not file anything in `src/`.

## Notes for the next session

- The G1 fix also de-risks the nightly CI lane operationally: unfixed, several
  repros SIGSEGV (SOE escalation) or wedge in repeated stack-overflow recovery,
  which is the same shape as the batch-timeout pollution the lane previously
  suffered.
- `julia +nightly` is now installed (1.14.0-DEV.2867) and `fuzz/` is
  instantiated for both channels.
- All staged copies of the artifact findings were removed from
  `fuzz/findings/` after triage; the working tree was left untouched.
