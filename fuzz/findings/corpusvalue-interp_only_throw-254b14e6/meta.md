# interp_only_throw (corpusvalue-interp_only_throw-254b14e6)

- seed: `1785779695500300657`
- walk seed: `1317783753263174656`
- interp mode: `corpusvalue`
- julia: `1.12.6`
- divergent observation index: 0
- ref exception: `none`  interp exception: `ErrorException`

## Detail

```
interp threw ErrorException: invalid redefinition of constant Future
```

## Shrunk program

```julia
using Random
using Base.Threads
using Base: Experimental
using Base: n_avail
using Distributed
using Serialization
import Base.MPFR
import Base.MPFR: clear_flags, had_underflow, had_overflow, had_divbyzero, had_nan, had_inexact_exception, had_range_exception
#= none:3 =# Core.@doc "The `Future` module implements future behavior of already existing functions,\nwhich will replace the current version in a future release of Julia." module Future
    #= none:5 =#
    #= none:7 =#
    using Random
    #= none:14 =#
    #= none:14 =# Core.@doc "    Future.copy!(dst, src) -> dst\n\nCopy `src` into `dst`.\n\n!!! compat \"Julia 1.1\"\n    This function has moved to `Base` with Julia 1.1, consider using `copy!(dst, src)` instead.\n    `Future.copy!` will be deprecated in the future.\n" copy!(dst::AbstractSet, src::AbstractSet) = begin
                #= none:23 =#
                Base.copy!(dst, src)
            end
    #= none:24 =#
    copy!(dst::AbstractDict, src::AbstractDict) = begin
            #= none:24 =#
            Base.copy!(dst, src)
        end
    #= none:25 =#
    copy!(dst::AbstractArray, src::AbstractArray) = begin
            #= none:25 =#
            Base.copy!(dst, src)
        end
    #= none:30 =#
    #= none:30 =# Core.@doc "    randjump(r::MersenneTwister, steps::Integer) -> MersenneTwister\n\nCreate an initialized `MersenneTwister` object, whose state is moved forward\n(without generating numbers) from `r` by `steps` steps.\nOne such step corresponds to the generation of two `Float64` numbers.\nFor each different value of `steps`, a large polynomial has to be generated internally.\nOne is already pre-computed for `steps=big(10)^20`.\n" function randjump(r::MersenneTwister, steps::Integer)
            #= none:39 =#
            #= none:40 =#
            j = Random._randjump(r, Random.DSFMT.calc_jump(steps))
            #= none:41 =#
            j.adv_jump += 2 * big(steps)
            #= none:42 =#
            j
        end
    end
#= none:624 =# @testset "Timer properties" begin
        #= none:625 =#
        t = Timer(1.0, interval = 0.5)
        #= none:626 =#
        #= none:626 =# @test t.timeout == 1.0
        #= none:627 =#
        #= none:627 =# @test t.interval == 0.5
        #= none:628 =#
        close(t)
        #= none:629 =#
        #= none:629 =# @test !(isopen(t))
        #= none:630 =#
        #= none:630 =# @test t.timeout == 1.0
        #= none:631 =#
        #= none:631 =# @test t.interval == 0.5
    end
#= none:39 =# Core.@doc "    firstdayofweek(dt::TimeType) -> TimeType\n\nAdjusts `dt` to the Monday of its week.\n\n# Examples\n```jldoctest\njulia> firstdayofweek(DateTime(\"1996-01-05T12:30:00\"))\n1996-01-01T00:00:00\n```\n" function firstdayofweek end
#= none:1033 =# @testset "precision base" begin
        #= none:1034 =#
        setprecision(53) do
            #= none:1035 =#
            #= none:1035 =# @test precision(Float64, base = 10) == precision(BigFloat, base = 10) == 15
        end
        #= none:1037 =#
        for (p, b) = ((100, 10), (50, 100))
            #= none:1038 =#
            setprecision(p, base = b) do
                #= none:1039 =#
                #= none:1039 =# @test precision(BigFloat, base = 10) == 100
                #= none:1040 =#
                #= none:1040 =# @test precision(BigFloat, base = 100) == 50
                #= none:1041 =#
                #= none:1041 =# @test precision(BigFloat) == precision(BigFloat, base = 2) == 333
            end
            #= none:1043 =#
        end
    end
```

## Original program

```julia
using Random
using Base.Threads
using Base: Experimental
using Base: n_avail
using Distributed
using Serialization
import Base.MPFR
import Base.MPFR: clear_flags, had_underflow, had_overflow, had_divbyzero, had_nan, had_inexact_exception, had_range_exception
#= none:3 =# Core.@doc "The `Future` module implements future behavior of already existing functions,\nwhich will replace the current version in a future release of Julia." module Future
    #= none:5 =#
    #= none:7 =#
    using Random
    #= none:14 =#
    #= none:14 =# Core.@doc "    Future.copy!(dst, src) -> dst\n\nCopy `src` into `dst`.\n\n!!! compat \"Julia 1.1\"\n    This function has moved to `Base` with Julia 1.1, consider using `copy!(dst, src)` instead.\n    `Future.copy!` will be deprecated in the future.\n" copy!(dst::AbstractSet, src::AbstractSet) = begin
                #= none:23 =#
                Base.copy!(dst, src)
            end
    #= none:24 =#
    copy!(dst::AbstractDict, src::AbstractDict) = begin
            #= none:24 =#
            Base.copy!(dst, src)
        end
    #= none:25 =#
    copy!(dst::AbstractArray, src::AbstractArray) = begin
            #= none:25 =#
            Base.copy!(dst, src)
        end
    #= none:30 =#
    #= none:30 =# Core.@doc "    randjump(r::MersenneTwister, steps::Integer) -> MersenneTwister\n\nCreate an initialized `MersenneTwister` object, whose state is moved forward\n(without generating numbers) from `r` by `steps` steps.\nOne such step corresponds to the generation of two `Float64` numbers.\nFor each different value of `steps`, a large polynomial has to be generated internally.\nOne is already pre-computed for `steps=big(10)^20`.\n" function randjump(r::MersenneTwister, steps::Integer)
            #= none:39 =#
            #= none:40 =#
            j = Random._randjump(r, Random.DSFMT.calc_jump(steps))
            #= none:41 =#
            j.adv_jump += 2 * big(steps)
            #= none:42 =#
            j
        end
    end
#= none:624 =# @testset "Timer properties" begin
        #= none:625 =#
        t = Timer(1.0, interval = 0.5)
        #= none:626 =#
        #= none:626 =# @test t.timeout == 1.0
        #= none:627 =#
        #= none:627 =# @test t.interval == 0.5
        #= none:628 =#
        close(t)
        #= none:629 =#
        #= none:629 =# @test !(isopen(t))
        #= none:630 =#
        #= none:630 =# @test t.timeout == 1.0
        #= none:631 =#
        #= none:631 =# @test t.interval == 0.5
    end
#= none:39 =# Core.@doc "    firstdayofweek(dt::TimeType) -> TimeType\n\nAdjusts `dt` to the Monday of its week.\n\n# Examples\n```jldoctest\njulia> firstdayofweek(DateTime(\"1996-01-05T12:30:00\"))\n1996-01-01T00:00:00\n```\n" function firstdayofweek end
#= none:1033 =# @testset "precision base" begin
        #= none:1034 =#
        setprecision(53) do
            #= none:1035 =#
            #= none:1035 =# @test precision(Float64, base = 10) == precision(BigFloat, base = 10) == 15
        end
        #= none:1037 =#
        for (p, b) = ((100, 10), (50, 100))
            #= none:1038 =#
            setprecision(p, base = b) do
                #= none:1039 =#
                #= none:1039 =# @test precision(BigFloat, base = 10) == 100
                #= none:1040 =#
                #= none:1040 =# @test precision(BigFloat, base = 100) == 50
                #= none:1041 =#
                #= none:1041 =# @test precision(BigFloat) == precision(BigFloat, base = 2) == 333
            end
            #= none:1043 =#
        end
    end
```
