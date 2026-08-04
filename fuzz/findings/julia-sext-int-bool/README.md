# Upstream Julia inconsistency: `sext_int(UInt64, ::Bool)` disagrees between codegen and runtime/const-fold

Status: **confirmed Julia-internal inconsistency (1.12.6). NOT a
JuliaInterpreter bug** — the interpreter agrees with Julia's own runtime
intrinsic dispatch *and* Julia's own constant folder; only LLVM codegen
differs. Explains nightly-run finding `call-call_value_divergence-ae541ea7`
(2026-08-04, `f8/0: native=0xffffffffffffffff interp=0x0000000000000001`).

## Repro (Julia 1.12.6, `repro.jl`)

```
runtime  dispatch: 0x0000000000000001    # Base.sext_int(UInt64, g) with untyped global g=true
compiled codegen : 0xffffffffffffffff    # @noinline f() = sext_int(UInt64, compilerbarrier(:const, true))
const-folded     : 0x0000000000000001    # Base.sext_int(UInt64, true) — literal, folded by inference
@interpret       : 0x0000000000000001    # JuliaInterpreter
```

Codegen truncates `Bool` to `i1` and sign-extends the bit (1 → -1); the
runtime intrinsic (`jl_f_intrinsic_call`) sign-extends the 8-bit storage byte
(0x01 → 1). Since inference's constant folding uses the runtime path, **native
compiled Julia disagrees with its own constant folder on the same
expression**: whether `sext_int(UInt64, x)` for `x::Bool == true` yields `-1`
or `1` depends on whether the call was folded.

## Disposition

- No `src/` change here; matching codegen would make the interpreter disagree
  with Julia's runtime evaluator and const-folder.
- Same class as the `checked_udiv_int`/`atomic_fence` intrinsic error-type
  findings (`8a9f8dee`, `6deeb299`): compiled-vs-runtime intrinsic-semantics
  splits inside Julia itself, which the call axis reports because it lacks
  three-way adjudication. Low priority upstream, but the self-disagreement
  (codegen vs. const-fold) makes it a legitimate JuliaLang/julia report.
