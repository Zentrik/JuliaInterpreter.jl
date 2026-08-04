# Status: RESOLVED — NOT an interpreter bug (compiler-vs-interpreter exception-type nuance)

Triaged + verified 2026-08-03. The earlier "kwsorter" hypothesis is **disproven**.

## What it actually is

`f8`'s body runs `Base.checked_udiv_int(kw10, kw10)` where the synthesized
`kw10` is a non-primitive value (`:a`, a Symbol). `checked_udiv_int` is a
`Core.IntrinsicFunction`. The divergence is:
`native=(:__thrown, :TypeError) interp=(:__thrown, :ErrorException)`.

The kwarg path is a red herring — it only delivers a non-primitive value into
the intrinsic. The exception-type split is between **compiled native codegen**
and **the interpreter's runtime intrinsic dispatch** (`src/builtins.jl:634`,
`ccall(:jl_f_intrinsic_call, …)`), which throws `ErrorException` for a
non-primitive argument. Julia's own runtime intrinsic evaluator throws the same
`ErrorException`; only *compiled* codegen for the intrinsic throws `TypeError`.

## Verification (this is the important part)

The intrinsic's native exception type is **optimization-context-dependent**, and
the interpreter's is stable:
- At top level (`julia -e 'Base.checked_udiv_int(:a,:a)'`): native throws
  `ErrorException` — i.e. it AGREES with `@interpret`.
- Inside a `@noinline` function at `-O1`: still `ErrorException` = interp.
- Only in the fuzzer's fully-compiled `Core.eval` context does native throw
  `TypeError`.

So the interpreter faithfully mirrors Julia's runtime/interpreter semantics; the
native side's exception *type* varies with how the intrinsic call gets compiled.
That is a **compiler-vs-interpreter divergence**, exactly the class the main
differential axis absorbs via the three-way (`run_ji`/`threeway`) oracle — not a
JuliaInterpreter defect.

## Disposition

- **No `src/` change.** Forcing native `TypeError` parity would require
  replicating Julia's per-intrinsic primitive-type contract in the interpreter —
  brittle, and it would make the interpreter *disagree* with Julia's own runtime
  intrinsic evaluator to match codegen.
- **Real harness gap:** the `call` axis has **no three-way adjudication**, so it
  reports compiler-vs-interpreter exception-type differences as findings. The fix
  is on the harness: give the call axis the same JI-vs-C three-way absorption the
  differential axis has, or compare intrinsic/type-error exceptions
  type-agnostically. Until then this class is call-axis noise. (Combined with
  `700181ab` and `370cc475`, the call axis is 0-for-3 on real interpreter bugs —
  a data point for downweighting it or adding three-way before trusting it.)
