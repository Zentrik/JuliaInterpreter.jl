# Status: FIXED (real JuliaInterpreter bug)

Found by the `native`/rec differential axis on the 2026-08-03 reweighted
campaign (seed 100102954), triaged and fixed the same session.

## The bug

A malformed `invoke` whose signature argument is a `Type` but **not a tuple
type** — e.g. `invoke(Int, Char, ...)` — raised
`ErrorException("expected tuple type")` under `RecursiveInterpreter` where
compiled Julia raises a clean `TypeError`. The divergent observation was
`obs[4]: ref=(:__thrown, :TypeError) interp=(:__thrown, :ErrorException)`.

Minimal reproducer:

```julia
invoke(Int, Char, (8, "x"), DataType, sv7)   # Char is a Type, not a tuple type
# compiled:     TypeError: in invoke, expected Type{T} where T<:Tuple, got Type{Char}
# interpreter:  ErrorException: expected tuple type
```

## Root cause

`src/interpret.jl`, the `invoke` handling in `evaluate_call!`. The guard
admitted any `argtypes isa Type` and then called
`Base.signature_type(f, argtypes)` in the plain-Type branch. For a non-tuple
type that call raises a bare `ErrorException` from Base's own
`to_tuple_type`, instead of the `TypeError` native `invoke` raises after its
own tuple-type check.

## The fix

Defer a non-tuple `argtypes` to native `invoke` (the same "let native invoke
raise the real error" pattern the surrounding malformed-shape checks use):

```julia
Base.unwrap_unionall(argtypes) <: Tuple || return invoke(fargs[2:end]...)
```

Regression test added to `test/interpret.jl`'s `invoke` testset
(`@test_throws TypeError @interpret invoke(ferr, Char, 3)` plus a
well-formed-invoke guard). This is the same family as the three earlier
invoke/invokelatest exception-type fixes: the interpreter's hand-written
`invoke` rewrite diverging from native on a malformed call.
