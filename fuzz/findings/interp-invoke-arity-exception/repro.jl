# FuzzJI reproducer — value_divergence (interp mode: rec)
# seed: 0
# julia: 1.11.9
# detail: obs[1]: ref=(:__thrown, :ArgumentError) interp=(:__thrown, :BoundsError)
# Run with: julia --project=<repo>/fuzz <this file>
include(joinpath(@__DIR__, "..", "..", "reprolib.jl"))
const SRC = "let\n    __obs__(try Core.invoke(abs) catch __e; (:__thrown, nameof(typeof(__e))) end)\n    __obs__(try Core.invoke(abs, 1, 2) catch __e; (:__thrown, nameof(typeof(__e))) end)\nend\n"
reprorun(SRC)
