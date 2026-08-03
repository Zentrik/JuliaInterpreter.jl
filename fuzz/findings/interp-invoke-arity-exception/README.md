# `invoke` with malformed arguments raises the wrong exception type

**Status: FIXED** — `evaluate_call!` now defers a too-short or non-type
`Core.invoke` to native `invoke` so the same ArgumentError/TypeError is
raised (src/interpret.jl); regression test in test/interpret.jl ("malformed
invoke raises the native error"). `repro.jl` now reports NO DIVERGENCE.

**Class:** `value_divergence` (guarded-exception observation), fingerprint
`value_divergence-b26e4559`. **Side:** JuliaInterpreter. **Severity:** low —
the exception *type* is wrong, no wrong values and no crash. **Found by:** the
reflection-driven builtins prober (`fuzz/src/probes.jl`), arity sweep over
`Core.invoke`, Julia 1.11.9.

Run `julia --project=<repo>/fuzz repro.jl` to see it.

| call | compiled Julia | JuliaInterpreter |
|---|---|---|
| `Core.invoke()` | `ArgumentError` | **`BoundsError`** |
| `Core.invoke(abs)` | `ArgumentError` | **`BoundsError`** |
| `Core.invoke(abs, 1, 2)` | `TypeError` | **`ErrorException`** |
| `Core.invoke(abs, Tuple{Int})` | `TypeError` | `TypeError` (agrees) |
| `Core.invoke(abs, Tuple{Int}, -3)` | `3` | `3` (agrees) |

So the divergence is confined to calls that are *malformed*: fewer than two
arguments, or a second argument that is not a type/tuple-of-types.

## Why

`src/builtins.jl` (generated) rewrites an expandable `invoke` call as

```julia
return Expr(:call, invoke, args[2:end]...)
```

and the interpreter then re-enters its own `invoke` handling, which indexes
the argument list positionally (`args[3]`, the signature) before checking that
it exists — hence `BoundsError` where the runtime builtin would have said
"invoke: not enough arguments". The 2-argument case takes the same path and
reports the argument-type mismatch as a plain `ErrorException` rather than the
runtime's `TypeError`.

An arity/type check in front of that rewrite — falling back to the runtime
builtin, which raises the right error — would make all five rows agree.

## Is it reachable from real code?

Yes: `invoke(f)` is something a user can write (and get wrong) in a debugger
session or in code being stepped. It is not producible by *lowering*, though,
which is why it never showed up before — unlike the two
`_apply_iterate`/`compilerbarrier` divergences recorded in `DESIGN.md`, which
are deliberate interpreter guards on argument shapes lowering cannot emit,
this one is an unchecked index in the interpreter's own rewrite.

## Notes for whoever picks this up

- Campaigns pre-seed their dedup set from *directory names*, and this
  directory is named descriptively (like the existing
  `julia-codegen-abort-allocopt`), not with the fingerprint above — so a
  campaign will report this bucket again. Rename it to
  `value_divergence-b26e4559`, or add a `SUPPRESSIONS` predicate in
  `driver.jl`, once it is confirmed known rather than news.
- Not filed upstream.
