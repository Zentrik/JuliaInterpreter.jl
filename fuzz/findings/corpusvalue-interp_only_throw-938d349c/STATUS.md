# Status: FIXED — real interpreter bug (method def shadowed a using-imported type)

Found by the `corpus` axis (`-O1`, 2026-08-03). Interpreter threw
`ArgumentError: invalid type for argument x in method definition for +` where
native completed. Mislabeled an "environment false positive"; it is a real
interpreter bug.

## Root cause + fix

`evaluate_methoddef` (`src/interpret.jl`) ran `Core.eval(mod, Expr(:function,
name))` unconditionally on 1.12, creating a fresh function that SHADOWED a
`using`-imported TYPE. The fragment defines `DateTime(dt::TimeType)=…` under
`using Dates`, which rebound `DateTime` to a function; the next method
`x::DateTime + y::Quarter` then saw a non-type and threw. Fixed by reusing the
existing binding when the name resolves to a `Type` (so the method extends it,
matching native `Core.eval`); non-Type names keep the original path. Test in
`test/toplevel.jl`; selftest 437/437. The "invalid subtyping in definition"
signature (`-254b14e6` family) is the same bug downstream and is also fixed.
