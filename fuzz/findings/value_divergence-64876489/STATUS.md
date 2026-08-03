# Status: FIXED — real interpreter bug (compilerbarrier accepted an invalid setting)

Found by the native differential axis on the `-O1` campaign (2026-08-03).
`obs[10]: ref=(:__thrown, :ErrorException) interp=(9, -100)` — the divergent
expression is `Core.compilerbarrier(:b, (9,-100))` with an INVALID barrier
setting `:b`.

## Root cause + fix

The interpreter delegated to a compiled `Core.compilerbarrier(s, x)` where the
optimizer ELIDES the barrier (lowers it to `x`), so an invalid setting was
silently accepted and the value returned, while native eval throws. Fixed in
`src/builtins.jl` (+ its generator `bin/generate_builtins.jl`) by routing through
a dynamic `invoke_in_world` call so Julia itself validates the setting — matching
native exactly: `ErrorException` for an unknown Symbol, `TypeError` for a
non-Symbol, the value for `:const`/`:type`/`:conditional`.

Regression test in `test/interpret.jl` ("compilerbarrier setting validation",
6/6). Note: a bare literal `@interpret Core.compilerbarrier(:b, 1)` bypasses the
interpreter (compiled `unreachable` → SIGILL), so the test routes through an
interpreted helper. Selftest 437/437.
