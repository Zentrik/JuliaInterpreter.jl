# Status: candidate real JuliaInterpreter bug — needs root-cause triage

MethodError (compiled) vs UndefVarError (RecursiveInterpreter) at obs[11],
seed from the 1.12 large-scale campaign. Adjudicated GENUINE by the three-way
oracle during the campaign: run_ji (Julia's built-in interpreter) did not match
JuliaInterpreter, so JuliaInterpreter is the outlier (both Julia engines agree,
the interpreter diverges) — a name/method-resolution difference, not class-U.
The parallel session (claude/julia-fuzzing-strategy-bmh692) independently saw
the same MethodError-vs-UndefVarError class, which corroborates it.

Standalone `repro.jl` confirmation was inconclusive under campaign CPU
contention: reprorun executes unbudgeted under RecursiveInterpreter and this
program (recursive multi-method fr3/fr4/fr7, sets, closures) did not finish in
400s (SIGTERM, not a crash). Re-run without a running campaign, or triage with
reshrink.jl to minimize first:
  julia --project=fuzz fuzz/reshrink.jl --seed <seed from meta.md> --mode rec
