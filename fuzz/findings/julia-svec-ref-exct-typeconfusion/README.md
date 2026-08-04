# Upstream Julia soundness bug: wrong `exct` for `Core._svec_ref` → catch-block type confusion, garbage errors, segfault

Status: **CONFIRMED upstream Julia bug (1.12.6; code identical on master as of
2026-08-04). NOT a JuliaInterpreter bug — the interpreter is the correct side
in every observed divergence.** Unreported upstream as far as searching could
tell; worth filing against JuliaLang/julia.

This resolves the "candidate upstream Julia UB" left unanalyzed in
`fuzz/NEXT.md` (finding `call-call_value_divergence-370cc475`, the corrupted
exception / `showerror` segfault the triage bot hit), two of the class-U
findings the agent filed in the `fuzz/findings/julia/` stream, and three of
the 2026-08-04 nightly-run findings on Julia 1.12.6 — all one bug:

- `370cc475`: `Core._svec_ref(x)` (1 arg) — native claimed `UndefVarError`,
  interp `ArgumentError`; triage bot saw a "corrupted exception" whose
  `showerror` segfaulted.
- `e4f68a3d`: `Core._svec_ref(0, Symbol)` — native `BoundsError`, interp
  `TypeError`.
- `5f97b637`: `Core._svec_ref(::String, ::Symbol)` — native `UndefVarError`,
  interp `TypeError`.
- `julia/julia-julia_engine_divergence-1ca00f6b`: `Core._svec_ref()` (0 args)
  — compiled `BoundsError`, runtime/interp `ArgumentError`.
- `julia/julia-julia_engine_divergence-5ada7c05`: `Core._svec_ref(a, b, c)`
  (3 args, on untyped globals in a compiled top-level thunk) — compiled
  `UndefVarError`, runtime/interp `ArgumentError`. Replayed end-to-end via its
  committed `repro.jl` and reduced to the 4-line `repro_undefvar_label.jl`.
  (The third `julia/`-stream finding, `a56e191f`, is the separate
  `atomic_fence` intrinsic error-type nuance already triaged in `6deeb299`.)

## Root cause (in Julia's compiler, not in codegen and not in this package)

`Compiler/src/tfuncs.jl`:

```julia
function builtin_exct(𝕃::AbstractLattice, @nospecialize(f::Builtin), argtypes::Vector{Any}, @nospecialize(rt))
    if isa(f, IntrinsicFunction)
        return intrinsic_exct(𝕃, f, argtypes)
    elseif f === Core._svec_ref
        return BoundsError          # ← unconditional
    end
    return Any
end
```

Inference declares that `Core._svec_ref` can only throw `BoundsError`,
regardless of arity or argument types. The runtime builtin
(`jl_f__svec_ref`, `src/builtins.c`) actually throws:

- `ArgumentError` for wrong arity ("_svec_ref: too few arguments (expected 2)"),
- `TypeError` for a non-`SimpleVector` first argument or non-`Int` index,
- `BoundsError` only for a genuinely out-of-bounds index.

So for a statically visible malformed call, a compiled `catch` block is
inferred with `e::BoundsError` while the runtime object is an
`ArgumentError`/`TypeError`. Everything downstream of that wrong type is
unsound:

1. **`typeof(e)` / `isa` constant-fold wrong.** `code_typed` shows the catch
   block of `try g() catch e; nameof(typeof(e)) end` compiling to a literal
   `return :BoundsError` — the object is never inspected. `e isa
   ArgumentError` folds to `false` for an actual `ArgumentError`, so user
   error-handling silently takes the wrong branch.
2. **`showerror` devirtualizes to the `BoundsError` method** and reads the
   fields `.a`/`.i` from an object of a different layout:
   - against a `TypeError` (4 fields — reads stay inside the object): garbage
     output such as `BoundsError: attempt to access Symbol at index [""]`;
   - against an `ArgumentError` (1 field — the `.i` read strides past the
     object): **segfault** at `errorshow.jl:62` (`ex.i isa AbstractRange`, an
     `isa` on a garbage pointer). Deterministic at `-O0`, `-O1` and default
     `-O2` on 1.12.6 (`repro_segfault.jl`, 9 lines, no `unsafe`, no
     `compilerbarrier`).

3. **Union-split mislabeling — where the `UndefVarError` claims come from.**
   When the `try` block can also throw something real (e.g. non-const global
   reads, whose exct is `UndefVarError`), the catch variable is inferred
   `Union{BoundsError, UndefVarError}` — `BoundsError` from the wrong exct,
   with the true `ArgumentError`/`TypeError` **excluded** from the union.
   `nameof(typeof(e))` then compiles to a union-split
   (`isa(e, BoundsError) ? :BoundsError : :UndefVarError`); the runtime
   `ArgumentError` fails the `isa`, falls into the else branch, and is
   reported as `:UndefVarError`. `code_typed` on `repro_undefvar_label.jl`'s
   `f` shows exactly this IR. `builtin_exct` is consulted even when the call's
   arity (0, 1, or 3) is outside the tfunc's declared 2..2 range, so every
   malformed-call shape is affected.

This also explains the earlier triage-bot observations on `370cc475`
("native exception type varies by call site", "corrupted exception",
"showerror segfaulted"): the claimed type is whatever inference folded or
union-split, the real object is whatever the runtime threw, and the crash
depends on the relative layouts and heap contents — classic type-confusion
symptoms, not randomness.

Why the harness kept surfacing it: the fuzz programs observe
`nameof(typeof(__e))` inside compiled native code (folded → `:BoundsError`, or
further-degraded garbage like `:UndefVarError`), while JuliaInterpreter calls
the runtime builtin and reports the true exception. Every such divergence was
the interpreter being right.

## Repros (Julia 1.12.6, no JuliaInterpreter involved)

`repro_typeconfusion.jl` — prints the confusion without crashing:

```
repro1 (compiled view): (BoundsError, true, false)   # typeof, isa BoundsError, isa ArgumentError
repro1 (truth):         ArgumentError
repro2 (compiled view): BoundsError
repro2 (truth):         TypeError
```

`repro_segfault.jl` — segfaults at every `-O` level:

```
signal 11 (1): Segmentation fault
showerror at ./errorshow.jl:62
```

## JuliaInterpreter behavior (verified, all correct and stable)

```
@interpret Core._svec_ref(:c)      → ArgumentError: _svec_ref: too few arguments (expected 2)
@interpret Core._svec_ref(1, :x)   → TypeError: in _svec_ref, expected Core.SimpleVector, got a value of type Int64
@interpret Core._svec_ref("s", :e) → TypeError: in _svec_ref, expected Core.SimpleVector, got a value of type String
```

## Disposition

- **No `src/` change in this package.**
- **File upstream** against JuliaLang/julia with `repro_segfault.jl` +
  `repro_typeconfusion.jl`. Suggested fix there: make `builtin_exct` return
  `BoundsError` only when the call is well-formed (2 args, `argtypes[1] ⊑
  SimpleVector`, `argtypes[2] ⊑ Int`), and
  `Union{ArgumentError,TypeError,BoundsError}` (or `Any`) otherwise —
  mirroring `_svec_ref_nothrow`'s conditions. Master's `tfuncs.jl` has the
  identical code, so the bug is live there too.
- **Harness**: mark the `_svec_ref`-with-malformed-args signature as a known
  native-side unsoundness (the confirm gate will keep re-deriving these
  findings every night until the generator's `_svec_ref` probe is restricted
  to well-typed calls or the signature is denylisted like the other
  native-UB entries).
