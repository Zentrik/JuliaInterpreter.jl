# Status: FIXED

Found by the stepping axis (`--engine step`, Julia 1.12.6) during the
large-scale campaign launch. `debug_command(:sl)` calls
`more_calls_on_current_line` (src/commands.jl), which destructured
`whereis(frame)` without guarding the `nothing` it returns when a pc carries
no line info (a toplevel-surface or compiler-generated statement) — a
`MethodError: no method matching iterate(::Nothing)` where plain interpretation
completed. Fixed by guarding both `whereis` calls in `more_calls_on_current_line`.
`repro.jl` now reports NO DIVERGENCE. This is untested debugger machinery
(`commands.jl` has one of the densest fix histories in the package) and the
first bug the stepping axis produced at scale.
