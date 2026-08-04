# Lane-findings triage report — "run #8" artifacts (v112 + pre), 2026-08-04

## Headline provenance fact (changes the whole picture)

Every NEW finding in both artifacts carries a seed of the form `1000006xxxxxxxxx`.
`SEED_BASE = 1000000 + github.run_number` (fuzz-nightly.yml), so these findings were
produced by **run #6**, not run #8. Run #6 (2026-08-03 17:15 UTC) checked out the
fuzzing branch at **`ab06a8d`** (17:14 UTC) — which predates **all five** of the first
session's interpreter fixes (`7d05ccf`, `3a323e8`, `b5e7fa7`, …, committed 19:16–20:08 UTC).
Run #8 proper (21:19 UTC, commit `4ef089d`, fixes included) would have used
`SEED_BASE=1000008`; no finding here carries such a seed.

Consequence: the two headline "value divergences on the supported release" are the
**already-fixed compilerbarrier-validation bug** re-derived on a pre-fix checkout.
Verified both directions: each reproduces at `ab06a8d` and does NOT reproduce at
`4ef089d` or current HEAD (the only src/ delta between those two is an unrelated
`utils.jl` 1.14 TypeEgal gate — the fix was already present at `4ef089d`).

Method note: naive re-runs of the repros at "the run's commit" (head_sha `4ef089d`)
showed NO divergence, which initially looked like an unexplainable process-state
artifact. The seed decode is what resolved it — worth remembering: **head_sha of a
nightly run is not the campaign's checkout; the workflow pins a branch ref, and the
seed encodes which run actually generated the program.**

---

## Priority 1 — v112: `value_divergence-e34e4a46` + `cmp-value_divergence-e34e4a46` (Julia 1.12.6)

- **Divergence**: obs[8] = `v33 = try Core.compilerbarrier(Base.compilerbarrier(:const, :fld1), Base.compilerbarrier(:const, nothing)) catch ...`
  — ref `(:__thrown, :ErrorException)` (native validates the barrier setting at
  runtime and rejects `:fld1`), interp `nothing` (the interpreter returned the value).
- **Repro status**:
  - `ab06a8d` (run #6's actual checkout, pre-fix), 1.12.6, `-O1`: **DIVERGENCE REPRODUCED** (interp obs[8]=`nothing`).
  - `4ef089d` (run #8's checkout) and current HEAD, 1.12.6, `-O1` and `-O2`, rec and cmp: **no divergence** (interp now throws `ErrorException`, matching native).
- **Verdict**: **already-fixed interpreter bug** — the compilerbarrier
  setting-validation fix in commit `3a323e8`. Root cause (historical): the
  `f === Core.compilerbarrier` arm of `maybe_evaluate_builtin`
  (`/home/user/JuliaInterpreter.jl/src/builtins.jl:160-171`) used to call
  `Core.compilerbarrier(args...)` directly from compiled harness code, where the
  optimizer elides the barrier to its value, silently accepting an invalid setting;
  the fix delegates through `invoke_in_world(frame.world, Core.compilerbarrier, …)`
  so the runtime builtin validates. **No action needed** beyond noting the artifact
  provenance. NOT a new 1.12 bug.

## Priority 2 — pre: `value_divergence-6774d88c` + `cmp-value_divergence-6774d88c` (Julia 1.13.0-rc1)

- **Divergence**: obs[3] = same construct,
  `Core.compilerbarrier(<runtime :not_a_field_zzz>, [g5, -5])` — ref throws
  `ErrorException`, interp returned `Any[-6, -5]`.
- **Repro status**: reproduced at `ab06a8d` on 1.13.0-rc1 (`-O1`); **no divergence**
  at current HEAD on 1.13.0-rc1 **or** 1.12.6, rec and cmp.
- **Verdict**: **same already-fixed bug** (`3a323e8`), same root cause, derived on the
  same pre-fix checkout. Does not upgrade anything: on 1.12 it is also fixed.

## Priority 3 — pre lane classifications

### `corpusvalue-interp_only_throw-febe8161` (1.13.0-rc1)
- interp threw `ArgumentError: invalid type for argument dt in method definition for -`
  after a fragment defines `function Date(period::Period, …)` (with `Date` a
  using-imported *type*) and then `function -(dt::Date, z::Month)`.
- **Not** the G2 backtrace class — this is the **method-def type-shadowing bug**
  (fix #2 in `3a323e8`, `evaluate_methoddef` in `src/interpret.jl`): pre-fix, a method
  named after a using-imported type created a fresh function shadowing the type, so
  the later use of `Date` in a signature was a Function, not a Type.
- Verified with a minimal direct trigger (Frame over
  `function Date(p::Period, …) … end; function -(dt::Date, z::Month) … end` in a
  module with `using Dates`): at `ab06a8d` on 1.13 it throws exactly the recorded
  `ArgumentError`; at current HEAD it interprets cleanly and the method works
  (`Date(2020,1,5) - Month(1) == 42`). (The finding's own `repro.jl` is inconclusive
  on the current harness — it predates the repro-fidelity fix and replays without the
  corpus prelude, so both sides die on `@test` being undefined.)
- **Verdict**: **already-fixed interpreter bug** (`3a323e8`). Closed.

### `step-step_only_throw-55ec98bb` (1.13.0-rc1)
- `AssertionError: is_leaf(frame)` in `step_expr!` during a `debug_command` walk over
  a program whose divergent function takes keyword args, with real breakpoints armed.
- Old repro.jl calls `reprorun` (never steps — under-reproduces by construction), so
  re-derived from the recorded seed instead: step engine, seed `1000006200001284`.
  At `ab06a8d` on 1.13: **re-derives the identical fingerprint `55ec98bb`**
  (AssertionError). At current HEAD on 1.13: 3/3 agreed, no finding.
- **Verdict**: **already-fixed debugger crash** — the `is_leaf` breakpoint-in-kwarg
  frame-corruption fix, commit `b5e7fa7` (`src/commands.jl`). Closed.

## Priority 4 — call-axis findings: NOT the unreset-global class; all four are reference-side Julia inconsistencies

All four **still reproduce on the current harness** (per-call global reset in), so the
expected "closed by the reset" verdict is wrong for every one of them. Each was then
isolated to a **pure-Julia divergence between compiled code and the runtime
builtin/intrinsic — no JuliaInterpreter involved**. The interpreter side always
matches the *runtime* (dynamic-call) semantics; the native side is compiled codegen
disagreeing with Julia's own runtime. The call axis has no three-way JI adjudication
(the reset was built instead), which is why this class leaks through there.

### `v112/call-call_value_divergence-e4f68a3d` (1.12.6) and `pre/call-call_value_divergence-60669c38` (1.13.0-rc1)
Same seed (`1000006400200657`), same program, same detail on both versions:
`f3/2: native=BoundsError interp=TypeError` from
`Core._svec_ref(compilerbarrier(:const, Float32(1.5)), compilerbarrier(:const, 'c'))`.
Minimal pure-Julia trigger (1.12.6 AND 1.13.0-rc1, -O1 and -O2):
```julia
h1() = try; Core._svec_ref(Base.compilerbarrier(:const, Float32(1.5)),
                           Base.compilerbarrier(:const, 'c')); catch e; typeof(e); end
h1()                                   # BoundsError   (compiled, call inside try)
f = Base.inferencebarrier(Core._svec_ref); f(Float32(1.5), 'c')  # TypeError (runtime builtin)
```
Notably the compiled exception flips to `TypeError` when the call is NOT inside a
`try` block — the specialized `_svec_ref` codegen path inside a try raises a bounds
error before/instead of the svec typecheck. **Verdict: reference-side Julia class-U
inconsistency (upstream-reportable); not an interpreter bug.**

### `pre/call-call_value_divergence-32ddbaec` (1.13.0-rc1)
`f2/1 kw: native=TypeError interp=ErrorException` from
`Core.Intrinsics.checked_udiv_int(compilerbarrier(:const, 1), compilerbarrier(:const, UInt32(6)))`
(mismatched operand widths). Pure Julia, both 1.12.6 and 1.13.0-rc1: the verbatim
function compiled natively returns `(:__thrown, :TypeError)`; the dynamic runtime
intrinsic raises `ErrorException("checked_udiv_int: types of a and b must match")`.
**Verdict: reference-side Julia class-U (compiled type-check vs runtime intrinsic
error); not an interpreter bug.** (Same genus as the documented
`sametype_intargs` barrier class — the checked_* family with *mismatched* operand
types still diverges through the barrier.)

### `pre/call-call_value_divergence-957cff62` (1.13.0-rc1)
`f10/2: native=true interp=false` — a **silent value divergence** from
`Base.ctlz_int(compilerbarrier(:const, a12))` with `a12::Bool`. Pure Julia, both
1.12.6 and 1.13.0-rc1:
```julia
c(x) = Base.ctlz_int(Base.compilerbarrier(:const, x))
c(false) == true; c(true) == false          # compiled: treats Bool as i1
g = Base.inferencebarrier(Base.ctlz_int)
g(false) == false; g(true) == true          # runtime intrinsic: treats Bool as i8
```
Compiled codegen and the runtime intrinsic disagree on the bit-width of `Bool` for
`ctlz_int` (i1 vs i8), producing opposite Bool results. **Verdict: reference-side
Julia inconsistency — the most upstream-report-worthy of the four (silent wrong
value, no exception); not an interpreter bug.**

### `pre/call-call_value_divergence-c67d3bbf` (1.13.0-rc1)
`f17/1: native=BoundsError interp=ArgumentError` from a **3-argument**
`Core._svec_ref(v20, closure, dict)` (wrong arity; `v20` is a boxed Int). Verbatim
function compiled natively: `BoundsError` (on 1.13; also reproducible on 1.12 in the
full-function form); dynamic runtime builtin:
`ArgumentError("_svec_ref: too many arguments (expected 2)")`. Same `_svec_ref`
specialized-codegen-inside-try family as e4f68a3d. **Verdict: reference-side Julia
class-U; not an interpreter bug.**

**Recommended harness follow-up for all four:** either add the three-way JI-vs-C
adjudication to the call axis, or extend the probe/argument constraints
(`PROBE_BANS`/recipes analog for generated in-body builtin calls) so
`_svec_ref`/mismatched-checked-intrinsics/Bool-intrinsic shapes are excluded or
adjudicated. Until then these four fingerprints will keep re-deriving.

## Already-triaged classes — confirmation runs on the current harness

### `pre/corpusvalue-interp_only_throw-44cfda26` (G2, backtrace introspection)
The fragment asserts `@test bt[1].line == topline + 4` over
`stacktrace(catch_backtrace())`. Re-derived from its seed (`1000006500500059`) on the
current harness (1.13): **3/3 fragments discarded at admission** (`discarded_junk`),
0 findings — the `corpus_ok` frame-introspection filter catches it. **Closed by the
G2 admission filter.** (Like febe8161, its old repro.jl replays without the prelude
and is inconclusive; the seed re-derivation is the meaningful check.)

### `pre/step-step_divergence-7e03896b` — **still re-derives; G3 fix does NOT cover it**
Re-run from seed `1000006301800887` on the current harness (1.13):
**same fingerprint re-derives**. The divergent observation is a string containing
`repr(MemoryRef)`, which embeds raw `Ptr{Nothing}(0x…)` addresses; the plain
interpreted run and the stepped run allocate at different addresses, so the strings
can never match while the actual data (`[7,7,7,7]`) agrees. This is a
**pointer-address-in-string normalization gap** — same genus as the G3
module-name-in-string class but a different species, and `a0f61fe` (module-prefix
strip) does not touch it. **Verdict: harness FP (not an interpreter bug), OPEN** —
fix by normalizing `Ptr{…}(0x[0-9a-f]+)` in observed strings in `__fjnorm__` (or by
excluding MemoryRef repr from string observations). This is the one new piece of
harness work the artifacts surface.

---

## Verdict table

| finding | lane / julia | old harness (ab06a8d) | current harness | verdict |
|---|---|---|---|---|
| value_divergence-e34e4a46 (+cmp) | v112 / 1.12.6 | reproduces | clean | fixed-interp-bug (compilerbarrier validation, `3a323e8`) |
| value_divergence-6774d88c (+cmp) | pre / 1.13-rc1 | reproduces | clean (1.13 & 1.12) | same fixed bug (`3a323e8`) |
| corpusvalue-interp_only_throw-febe8161 | pre / 1.13-rc1 | reproduces (direct trigger) | clean | fixed-interp-bug (method-def type-shadowing, `3a323e8`) |
| step-step_only_throw-55ec98bb | pre / 1.13-rc1 | re-derives from seed | clean (3/3 agreed) | fixed-debugger-crash (`b5e7fa7`) |
| call-…-e4f68a3d | v112 / 1.12.6 | — | **still reproduces** | Julia class-U: `_svec_ref` compiled-in-try BoundsError vs runtime TypeError |
| call-…-60669c38 | pre / 1.13-rc1 | — | **still reproduces** | same program/class as e4f68a3d |
| call-…-32ddbaec | pre / 1.13-rc1 | — | **still reproduces** | Julia class-U: `checked_udiv_int` mismatched types, TypeError vs ErrorException |
| call-…-957cff62 | pre / 1.13-rc1 | — | **still reproduces** | Julia inconsistency: `ctlz_int(::Bool)` i1-vs-i8, silent wrong value (upstream-worthy) |
| call-…-c67d3bbf | pre / 1.13-rc1 | — | **still reproduces** | Julia class-U: 3-arg `_svec_ref`, BoundsError vs ArgumentError |
| corpusvalue-…-44cfda26 | pre / 1.13-rc1 | (G2 class) | rejected at admission | closed by G2 corpus filter |
| step-step_divergence-7e03896b | pre / 1.13-rc1 | (derived run #6) | **still re-derives** | harness FP, OPEN: pointer-address-in-string normalization gap |

No genuine, unfixed JuliaInterpreter bug exists in either artifact.

## Housekeeping notes

- All temporary copies under `/home/user/JuliaInterpreter.jl/fuzz/findings/` were
  removed; the directory matches the committed baseline again. Temporary worktrees
  (`old-harness` at 4ef089d, `run6-tree` at ab06a8d) removed.
- `juliaup` channel `1.13` (1.13.0-rc1) was installed for this triage.
- Observed but not mine and left untouched: `test/interpret.jl` gained a stray `end`
  (line ~1635) at 09:21 UTC from some concurrent process in this checkout — it is
  not from the fuzz harness (which only reads `test/`) and should be checked by
  whoever owns that edit; the file currently does not parse as a balanced testset.
- The nightly artifact labeled "run #8" contains run-#6 campaign output for these
  lanes. Worth re-checking how the artifacts were extracted; run #8's own v112/pre
  lanes (post-fix checkout `4ef089d`) would be expected to be clean of the four
  fixed-bug fingerprints, consistent with everything measured here.

---

# Run #9 section — 2026-08-04 (SEED_BASE=1000009 confirmed; checkout = `3f2b13e`, branch head at 06:03 UTC)

Run #9's campaign checkout was `claude/fuzzing-effectiveness-review-92ph29` at
**`3f2b13e`** (23:48 Aug 3): it INCLUDES all five session-1 interpreter fixes but
NOT the session-2 per-call global reset. All new seeds decode to `1000009…`.

## 1. `pre/value_divergence-c6f2ab08` — **REAL, LIVE INTERPRETER BUG at current HEAD** (1.12.6 AND 1.13.0-rc1)

- **Divergence**: obs[3] = `try Core._apply_iterate(Base.compilerbarrier(:const, Base.iterate), Base.compilerbarrier(:const, :d), Base.compilerbarrier(:const, (1, 2))) catch …`
  — ref `(:__thrown, :MethodError)` (a Symbol is not callable), interp
  `(:__thrown, :UndefVarError)` (`UndefVarError: d`).
- **Repro status**: reproduces at run #9's checkout `3f2b13e` (1.13-rc1) AND at
  **current HEAD** of `claude/false-positive-fussing-improvements-igts2c` on
  **both 1.13.0-rc1 and 1.12.6** (`-O1`; rec mode). No `cmp-` twin exists and none
  is expected: `NonRecursiveInterpreter` takes the `!expand` branch (direct native
  `_apply_iterate` call) and agrees with the reference — the bug is
  RecursiveInterpreter-only.
- **Root cause** (`/home/user/JuliaInterpreter.jl/src/builtins.jl:104-119`, and the
  generator template `/home/user/JuliaInterpreter.jl/bin/generate_builtins.jl:285`;
  present on `master` — long-standing upstream JuliaInterpreter defect, not
  branch-introduced): the `Core._apply_iterate` expand path rebuilds the flattened
  call as
  ```julia
  new_expr = Expr(:call, argswrapped[2])   # callee inserted BARE
  …
  for x in argsflat
      push!(new_expr.args, QuoteNode(x))   # arguments correctly QuoteNode-wrapped
  end
  return maybe_recurse_expanded_builtin(interp, frame, new_expr)
  ```
  The *arguments* are QuoteNode-wrapped but the *callee value* is not. For a
  non-builtin callee, `maybe_recurse_expanded_builtin` (`src/builtins.jl:14-21`)
  returns `new_expr` to `evaluate_call!`/`eval_rhs`, where a bare `Symbol` in call
  position is resolved as a **name** (slot/global lookup in the frame's module)
  instead of being used as a value. This is byte-for-byte the same defect fixed for
  `Core._call_latest`/`invokelatest` in the `value_divergence-142a17f7` episode
  ("QuoteNode-wrap the callee"); the `_apply_iterate` expand path was missed. The
  analogous fix is `Expr(:call, QuoteNode(argswrapped[2]))` in both files (not
  applied — analysis only, per instructions).
- **Minimal trigger** (ordinary user-reachable splat syntax, no Core spelunking):
  ```julia
  using JuliaInterpreter
  g1() = (:d)((1, 2)...)     # native: MethodError.  RecursiveInterpreter: UndefVarError(:d)
  g2() = (:sin)((1.0,)...)   # native: MethodError.  RecursiveInterpreter: SILENTLY returns 0.8414709848078965
  frame = JuliaInterpreter.enter_call(g1); JuliaInterpreter.finish_and_return!(frame)
  ```
  The `g2` form is the severe variant: when the Symbol happens to name a reachable
  binding, the interpreter **silently calls the wrong function and returns a value**
  where compiled Julia raises `MethodError`. Verified on 1.12.6 and 1.13.0-rc1 at
  HEAD. This is the highest-value outcome of the run-#9 artifacts: a genuine
  supported-release interpreter bug with a one-line reproducer.

## 2. `v112/call-call_value_divergence-ae541ea7` (1.12.6) — NOT unreset-global; pure-Julia Bool-width class

Same seed/program as `pre/call-…-d312d19e` (`1000009400600907`), detail
`f2/1: native=0xffffffffffffffff interp=0x0000000000000001` from
`Core.Intrinsics.sext_int(UInt64, compilerbarrier(:const, true))`.
Still reproduces under the CURRENT harness (per-call reset active), and isolates to
pure Julia on both versions:
```julia
c() = Core.Intrinsics.sext_int(UInt64, Base.compilerbarrier(:const, true))  # compiled: 0xffffffffffffffff (Bool as i1, sign-extended)
Base.inferencebarrier(Core.Intrinsics.sext_int)(UInt64, true)               # runtime: 0x0000000000000001 (Bool as i8)
```
**Verdict: reference-side Julia inconsistency — the `ctlz_int(::Bool)` i1-vs-i8
family, second silent-wrong-value shape.** Not an interpreter bug (interp matches
the runtime intrinsic).

## 3. pre call-axis entries — all still reproduce on the current harness; all pure-Julia; none unreset-global

| finding | probe | native (compiled) | interp (= runtime) | class |
|---|---|---|---|---|
| d312d19e | `sext_int(UInt64, ::Bool)` | `0xffffffffffffffff` | `0x1` | Bool i1-vs-i8, **silent wrong value** (same program as ae541ea7) |
| 8373f5b2 | `sitofp(Float32, ::Bool)` | `-1.0f0` (i1 signed = -1) | `1.0f0` | Bool i1-vs-i8, **silent wrong value** — third shape in the family |
| 90fa3b0a | `_svec_ref(Vector, ::Float64)` | `BoundsError` | `TypeError` | `_svec_ref` compiled-specialization (e4f68a3d family) |
| ebae47ec | `atomic_fence(:unordered)` | `ErrorException` | `ConcurrencyViolationError` | atomics ordering-validation exception-type split (re-derivation of the 6deeb299 class) |
| bef121f6 | `_svec_ref(::Any, ::Any)` (untyped-global args) | **bogus `UndefVarError: `_svec_ref` not defined in Core.SimpleVector scope`** | `TypeError` | `_svec_ref` compiled path, NEW shape — nonsense error, UB-flavored |

All verified in pure Julia on BOTH 1.12.6 and 1.13.0-rc1 (`-O1`; the exact
native/interp values of every finding match the compiled/dynamic pair). The
interpreter side always equals the runtime builtin/intrinsic semantics; the native
side is Julia codegen disagreeing with Julia's own runtime. **None of these is an
interpreter bug and none is the unreset-global harness class** (the per-call reset
neither causes nor cures them — they re-derive under the current harness and will
keep doing so until the call axis gets three-way adjudication or probe exclusion).

### Updated upstream-report shortlist (pure-Julia, compiled vs runtime)

1. **Bool intrinsic width family (i1 vs i8) — silent wrong values**: `ctlz_int(::Bool)`
   (957cff62), `sext_int(T, ::Bool)` (ae541ea7/d312d19e), `sitofp(T, ::Bool)`
   (8373f5b2). One coherent upstream issue: compiled intrinsics treat `Bool` as i1,
   the runtime intrinsics as i8, with opposite/different results and no error.
2. **`_svec_ref` compiled specialization on non-svec inputs**: BoundsError instead
   of TypeError (e4f68a3d/60669c38/90fa3b0a), BoundsError instead of ArgumentError
   on wrong arity (c67d3bbf), heap-garbage payloads
   (`BoundsError: attempt to access Symbol at index [""]`) and a nonsense
   `UndefVarError: _svec_ref not defined in Core.SimpleVector scope` (bef121f6) —
   the last two look like the compiled path reads memory it should have typechecked
   first, i.e. UB, which upgrades this from cosmetic to report-worthy.
3. Exception-type splits: `checked_udiv_int` mismatched widths TypeError vs
   ErrorException (32ddbaec); `atomic_fence` invalid ordering ErrorException vs
   ConcurrencyViolationError (ebae47ec).

## Run #9 verdict table

| finding | lane / julia | current harness | verdict |
|---|---|---|---|
| value_divergence-c6f2ab08 | pre / 1.13-rc1 | **reproduces at HEAD, also on 1.12.6** | **REAL interp bug**: `_apply_iterate` expand path leaves callee un-QuoteNoded (`src/builtins.jl:112`); Symbol callee re-resolved as a name — wrong exception, or silently wrong value |
| call-…-ae541ea7 | v112 / 1.12.6 | reproduces | pure Julia: `sext_int(UInt64, ::Bool)` i1-vs-i8, silent wrong value |
| call-…-d312d19e | pre / 1.13-rc1 | reproduces | same program/class as ae541ea7 |
| call-…-8373f5b2 | pre / 1.13-rc1 | reproduces | pure Julia: `sitofp(Float32, ::Bool)` i1-vs-i8, silent wrong value |
| call-…-90fa3b0a | pre / 1.13-rc1 | reproduces | pure Julia: `_svec_ref` BoundsError-vs-TypeError |
| call-…-ebae47ec | pre / 1.13-rc1 | reproduces | pure Julia: `atomic_fence(:unordered)` exception-type split |
| call-…-bef121f6 | pre / 1.13-rc1 | reproduces | pure Julia: `_svec_ref(Any,Any)` bogus UndefVarError (new UB-flavored shape) |
| 32ddbaec / 60669c38 / 44cfda26 re-derivations | pre | as predicted | previously classified; no change |

Cleanup: all run-#9 temp copies removed from `fuzz/findings/` (19 baseline entries
remain); `run9-tree` worktree removed; repo untouched. (The stray
`test/interpret.jl` edit noted in the run-8 section has since been resolved by its
owner — `git status` is clean.)
