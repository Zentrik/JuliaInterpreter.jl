# FuzzJI reproducer — interp_only_throw (interp mode: corpusvalue)
# seed: 1785779695504300010
# walk seed: 3248280453104291902
# julia: 1.12.6
# detail: interp threw FallbackTestSetException: Test.FallbackTestSetException("There was an error during testing")
# Run with: julia --project=<repo>/fuzz <this file>
include(joinpath(@__DIR__, "..", "..", "reprolib.jl"))
const SRC = "using Serialization, Base.StackTraces\nlet bt, topline = #= none:147 =# @__LINE__()\n    #= none:148 =#\n    try\n        #= none:149 =#\n        let x = 1\n            #= none:150 =#\n            y = 2x\n            #= none:151 =#\n            z = 2z - 1\n        end\n    catch\n        #= none:154 =#\n        bt = stacktrace(catch_backtrace())\n    end\n    #= none:156 =#\n    #= none:156 =# @test (bt[1]).line == topline + 4\nend"
reprocorpus(SRC)
