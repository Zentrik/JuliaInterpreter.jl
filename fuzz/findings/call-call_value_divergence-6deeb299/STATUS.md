# Status: REAL but low-value divergence — intrinsic error-type (jl_f_intrinsic_call vs codegen)

Found by the `call` axis on the `-O1` campaign (2026-08-03).
`reprocall(SRC, 1511666922561067042)`:
`f13/0: native=(:__thrown, :ErrorException) interp=(:__thrown, :ConcurrencyViolationError)`.
Divergent expression: `Base.atomic_fence(:unordered)` — an INVALID memory ordering
for a fence.

## Verified mechanism (this is NOT the 8a9f8dee compiler-vs-runtime class)

- `Base.atomic_fence === Core.Intrinsics.atomic_fence` (an intrinsic).
- **Every native path throws `ErrorException`**: top-level eval, inside a
  `@noinline` function at `-O1`, and a direct `Core.Intrinsics.atomic_fence(:unordered)`
  call. Native is *consistent* here — so this is unlike `8a9f8dee`, where native
  itself disagreed (codegen TypeError vs runtime ErrorException).
- **The interpreter throws `ConcurrencyViolationError`** in all forms
  (`@interpret` on `Core.Intrinsics.atomic_fence` and on `Base.atomic_fence`).

So the interpreter genuinely diverges from native in every context. Root cause:
`RecursiveInterpreter` evaluates intrinsics through `ccall(:jl_f_intrinsic_call, …)`
(`src/builtins.jl`, the generic intrinsic path), which validates `atomic_fence`'s
ordering argument at runtime and raises `ConcurrencyViolationError`; native code
always **codegens** the intrinsic, and codegen's ordering validation raises
`ErrorException`. The only way to reach `ErrorException` is the codegen path, which
the interpreter (by design, for speed) does not use for intrinsics.

## Disposition

- **Real, observable divergence** (a debugger/interpreter user catching exceptions
  around `atomic_fence` would see a different type than compiled Julia). NOT
  dismissed as harness noise.
- **But low value and not a cheap/safe `src/` fix**: it is an exception-*type*
  nuance for an *invalid* atomic ordering (a programmer error either way — the
  interpreter still throws), and it is inherent to the `jl_f_intrinsic_call`
  dispatch that `RecursiveInterpreter` uses for ALL intrinsics. Matching codegen's
  exact error type per-intrinsic would be brittle; the interpreter is otherwise
  faithfully running Julia's runtime intrinsic evaluator.
- Recommended handling, in order: (1) call-axis **three-way adjudication** (JI-vs-C
  via Julia's own interpreter) would absorb this whole intrinsic error-type class,
  as it already does on the differential axis; (2) a broader "intrinsic error-type
  parity" pass in `src/builtins.jl` if exact parity is ever wanted (low priority).
- Call axis tally: still 0 *high-value* interpreter bugs; this and `8a9f8dee` are
  the intrinsic error-type family, `700181ab` was unreset-globals, `370cc475` was
  native UB. Reinforces the three-way-adjudication recommendation for the axis.
