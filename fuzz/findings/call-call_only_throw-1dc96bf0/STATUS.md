# Status: KNOWN call-axis harness FALSE POSITIVE (unreset program global → control-flow divergence)

Found by the `call` axis (`-O1`, 2026-08-03).
`f10/1: interp threw MethodError (push!(::Bool, ::Float64)) where native completed`.

## Why it is NOT an interpreter bug

`f10(a11)`'s `push!(a11, 8.03)` sits in the `else` branch of
`if ("11" < (false ? … : string((6 - g4), :d, :b)))`, gated on the program global
`g4`. The synthesized `a11` is a `Bool` (its `setindex!` on the first line also
fails and is caught). Native takes the `if` branch (skips `push!`) and completes;
the interpreter takes the `else` branch and hits `push!(::Bool, ::Float64)`.

The two sides diverge only because `g4` differs between the native and interpreted
calls: the call axis's `resetstate!` restores `__LCG__`/`__VTIME__` but NOT the
program's own globals (`callfuzz.jl:290-301`, the documented accepted masking),
so `g4` drifts across the three calls and flips the branch. Same class as
`700181ab`.

## Disposition

No `src/` change. This is the 6th call-axis candidate to resolve to
harness/compiler/UB rather than a real interpreter bug (700181ab unreset-globals,
8a9f8dee & 6deeb299 intrinsic error-type, 370cc475 native UB, and this one).
Durable fixes: reset ALL program globals between the three calls (fresh module
per call), and/or add three-way (JI-vs-C) adjudication. Until then the call axis
is a noise source and a candidate to downweight in longrun.sh.
