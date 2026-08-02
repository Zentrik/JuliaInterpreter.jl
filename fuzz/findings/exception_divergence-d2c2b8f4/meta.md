# exception_divergence (exception_divergence-d2c2b8f4)

- seed: `1200020`
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel10`: fuel10 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel10`: fuel10 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
mutable struct S1
    @atomic fld2::Int64
    @atomic fld3::Int64
end
global g4::Int64 = 5
g5 = string(:b, true, "∀α!0")
sv6 = S1((-2), 3)
if ((((-5.43 * 9.2) - g4) isa Int64) ? false : (min(3, g4) < (@atomic (sv6).fld3)))
    u7 = ((true ? 2.29 : ((-0.0 + -9.78) + 5.13)) * 6.9)
end
__obs__(@isdefined(u7))
__obs__(try; u7; catch __e; (:__undef, nameof(typeof(__e))) end)
let
    v9 = ((p8) -> g4)
    fuel10 = 3
    while false && (fuel10 > 0)
        global fuel10 -= 1
        @atomic sv6.fld3 += length(g5)
    end
    v11 = ("yx ", -Inf, g4)
    @atomic sv6.fld3 -= ((!((-2.5 + (-3)) == (8.11 * g4))) ? ((abs(g4) - g4) - (max(g4, (-3)) - length(g5))) : 4)
    v12 = (1.48, true, 10)
    v9 = ((p13) -> (@atomic (sv6).fld3))
    if (:a === :d)
        v14 = (3, g4, :d)
        if ((-3.61 * ((g4 != (-5)) ? g4 : (-4))) < (1.1 * (false ? -4.64 : abs(4.6))))
            v12 = v12
            v15 = max(1, 6)
        end
        @atomic sv6.fld2 += (-4)
    else
        __obs__(abs(0.1))
    end
    @atomic sv6.fld3 += g4
    v16 = ((@atomic (sv6).fld2) ÷ 1)
    local t17::Float64 = min(((!true) ? ((3.28 / -2.5) + length(g5)) : ((-4.7 / 4.13) + (false ? 7.12 : -4.22))), ((1.5 - (-7.51 * -5.18)) - (-6.72 + -2.5)))
    __obs__((@atomic (sv6).fld2))
    __obs__((9, "∀"))
    v18 = Any[g4]
    __obs__(v18)
    __obs__(t17)
    __obs__(v16)
    __obs__(v12)
    __obs__(v11)
    __obs__((try v9(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(sv6)
    __obs__(g5)
    __obs__(g4)
end

```

## Original program

```julia
mutable struct S1
    @atomic fld2::Int64
    @atomic fld3::Int64
end
global g4::Int64 = 5
g5 = string(:b, true, "∀α!0")
sv6 = S1((-2), 3)
if ((((-5.43 * 9.2) - g4) isa Int64) ? false : (min(3, g4) < (@atomic (sv6).fld3)))
    u7 = ((true ? 2.29 : ((-0.0 + -9.78) + 5.13)) * 6.9)
end
__obs__(@isdefined(u7))
__obs__(try; u7; catch __e; (:__undef, nameof(typeof(__e))) end)
let
    v9 = ((p8) -> g4)
    fuel10 = 3
    while false && (fuel10 > 0)
        global fuel10 -= 1
        @atomic sv6.fld3 += length(g5)
    end
    v11 = ("yx ", -Inf, g4)
    @atomic sv6.fld3 -= ((!((-2.5 + (-3)) == (8.11 * g4))) ? ((abs(g4) - g4) - (max(g4, (-3)) - length(g5))) : 4)
    v12 = (1.48, true, 10)
    v9 = ((p13) -> (@atomic (sv6).fld3))
    if (:a === :d)
        v14 = (3, g4, :d)
        if ((-3.61 * ((g4 != (-5)) ? g4 : (-4))) < (1.1 * (false ? -4.64 : abs(4.6))))
            v12 = v12
            v15 = max(1, 6)
        end
        @atomic sv6.fld2 += (-4)
    else
        __obs__(abs(0.1))
    end
    @atomic sv6.fld3 += g4
    v16 = ((@atomic (sv6).fld2) ÷ 1)
    local t17::Float64 = min(((!true) ? ((3.28 / -2.5) + length(g5)) : ((-4.7 / 4.13) + (false ? 7.12 : -4.22))), ((1.5 - (-7.51 * -5.18)) - (-6.72 + -2.5)))
    __obs__((@atomic (sv6).fld2))
    __obs__((9, "∀"))
    v18 = Any[g4]
    __obs__(v18)
    __obs__(t17)
    __obs__(v16)
    __obs__(v12)
    __obs__(v11)
    __obs__((try v9(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(sv6)
    __obs__(g5)
    __obs__(g4)
end

```
