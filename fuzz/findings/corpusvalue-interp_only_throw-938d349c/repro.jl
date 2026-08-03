# FuzzJI reproducer — interp_only_throw (interp mode: corpusvalue)
# seed: 1785779695500600226
# walk seed: 2813607554556078055
# julia: 1.12.6
# detail: interp threw ArgumentError: ArgumentError: invalid type for argument x in method definition for + at none:77
# Run with: julia --project=<repo>/fuzz <this file>
include(joinpath(@__DIR__, "..", "..", "reprolib.jl"))
const SRC = "import Base: IndexLinear\n#= none:14 =# Core.@doc \"    DateTime(dt::Date) -> DateTime\\n\\nConvert a `Date` to a `DateTime`. The hour, minute, second, and millisecond parts of\\nthe new `DateTime` are assumed to be zero.\\n\" DateTime(dt::TimeType) = begin\n            #= none:20 =#\n            convert(DateTime, dt)\n        end\nx::DateTime + y::Quarter = begin\n        #= none:77 =#\n        x + Month(y)\n    end\nstruct TSlow{T, N} <: AbstractArray{T, N}\n    #= none:35 =#\n    data::Dict{NTuple{N, Int}, T}\n    #= none:36 =#\n    dims::NTuple{N, Int}\nend"
reprocorpus(SRC)
