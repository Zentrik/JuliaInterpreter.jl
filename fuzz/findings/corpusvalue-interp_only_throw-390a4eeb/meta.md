# interp_only_throw (corpusvalue-interp_only_throw-390a4eeb)

- seed: `1785779695504300010`
- walk seed: `3248280453104291902`
- interp mode: `corpusvalue`
- julia: `1.12.6`
- divergent observation index: 0
- ref exception: `none`  interp exception: `FallbackTestSetException`

## Detail

```
interp threw FallbackTestSetException: Test.FallbackTestSetException("There was an error during testing")
```

## Shrunk program

```julia
using Serialization, Base.StackTraces
let bt, topline = #= none:147 =# @__LINE__()
    #= none:148 =#
    try
        #= none:149 =#
        let x = 1
            #= none:150 =#
            y = 2x
            #= none:151 =#
            z = 2z - 1
        end
    catch
        #= none:154 =#
        bt = stacktrace(catch_backtrace())
    end
    #= none:156 =#
    #= none:156 =# @test (bt[1]).line == topline + 4
end
```

## Original program

```julia
using Serialization, Base.StackTraces
let bt, topline = #= none:147 =# @__LINE__()
    #= none:148 =#
    try
        #= none:149 =#
        let x = 1
            #= none:150 =#
            y = 2x
            #= none:151 =#
            z = 2z - 1
        end
    catch
        #= none:154 =#
        bt = stacktrace(catch_backtrace())
    end
    #= none:156 =#
    #= none:156 =# @test (bt[1]).line == topline + 4
end
```
