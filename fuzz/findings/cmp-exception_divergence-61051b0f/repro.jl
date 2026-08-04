# FuzzJI reproducer — exception_divergence (interp mode: cmp)
# seed: 747
# julia: 1.11.9
# detail: ref threw MethodError (MethodError: no method matching -(::Tuple{Symbol, Symbol}, ::Float64) The function `-` exists, but no method is defined for this combination of argument types.  Closest candidates are:   -(!Matched::BigFloat, ::Union{Float16, Float32, Float64})    @ Base mpfr.jl:565   -(!Matched::Complex{Bool}, ::Real)    @ Base complex.jl:329   -(!Matched::Missing, ::Number)    @ Base missing.jl:123   ... ); interp threw ErrorException (rethrow() not allowed outside a catch block)
# Run with: julia --project=<repo>/fuzz <this file>
include(joinpath(@__DIR__, "..", "..", "reprolib.jl"))
const SRC = "function f5(a6, a7)\n    try\n        try\n            ((((2 + 1) ÷ 1) != (((true && true) ? a6 : ((-12) ÷ (-3))) * a6))) && return (try (max(0, (a6 - (a6 % (-1)))) % a6) catch __e; (:__thrown, nameof(typeof(__e))) end)\n        catch err10\n            nothing\n        end\n    catch err8\n        nothing\n    finally\n        nothing\n    end\n    return a7\nend\nlet\n    try\n        __obs__((f5(0, f5(0, 0.0)) - 0.0))\n    catch err18\n        if (:b === :b)\n            u20 = (0 - 0)\n        end\n        __obs__(@isdefined(u20))\n        __obs__(try; u20; catch __e; (:__undef, nameof(typeof(__e))) end)\n        (((((!true) ? (-8) : (0 % 3)) < 0) ? (0 == 1) : (!(\"yb🐛ab\" < string((-10), \"\"))))) && rethrow()\n    else\n        nothing\n    end\nend\n"
reprorun(SRC; compiled=true)
