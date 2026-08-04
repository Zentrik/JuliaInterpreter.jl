# Status: FIXED (real JuliaInterpreter bug, campaign-found, three-way-confirmed)

Minimal reproducer (`minimal.jl`): `Core._call_latest(:b)` — and equally
`Base.invokelatest(:b)` — a non-callable Symbol as the first argument.

- compiled Julia: MethodError (a Symbol is not callable)
- Compiled mode (NonRecursiveInterpreter): MethodError (agrees)
- Julia's built-in interpreter (--compile=min): MethodError (agrees)
- RecursiveInterpreter: **UndefVarError** ← the outlier

The three-way oracle confirmed this is a JuliaInterpreter bug (not class-U):
compiled, cmp, and Julia's own built-in interpreter all agree on MethodError;
only RecursiveInterpreter diverged. The parallel session independently saw the
same MethodError-vs-UndefVarError class.

Root cause: `_call_latest`/`invokelatest` in the expand path built
`Expr(:call, args[1])` with the *evaluated first-argument value* placed bare in
function position. A value that looks like an AST name — a Symbol — was then
re-interpreted as a variable reference and threw UndefVarError, where the native
builtin calls the value and raises MethodError. Fixed by QuoteNode-wrapping the
callee (src/builtins.jl), like the other arguments already were. Regression
tests in test/interpret.jl. Original (unshrunk) program in meta.md; `minimal.jl`
is the 25-line delta-debugged form (the seed no longer re-derives it because the
generator changed mid-campaign — the barrier merge shifted seed→program).
