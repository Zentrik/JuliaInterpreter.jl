"""
FuzzJI: differential fuzzing of JuliaInterpreter against compiled Julia.

See fuzz/DESIGN.md for the architecture. Entry point: `FuzzJI.campaign(...)`,
or the CLI in fuzz/run.jl.
"""
module FuzzJI

using Random: Xoshiro, AbstractRNG

include("typesum.jl")
include("ir.jl")
include("env.jl")
include("rules.jl")
include("render.jl")
include("execute.jl")
include("classify.jl")
include("shrink.jl")
include("journal.jl")
include("driver.jl")
include("supposition.jl")

export campaign, supposition_campaign, genprogram, render, run_both, classify, shrink, Cfg, ProgramGen

end
