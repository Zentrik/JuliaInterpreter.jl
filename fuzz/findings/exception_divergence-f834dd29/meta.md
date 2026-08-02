# exception_divergence (exception_divergence-f834dd29)

- seed: `1200081`
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel28`: fuel28 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel28`: fuel28 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
mutable struct S1
    @atomic fld2::Symbol
    fld3::Float64
    @atomic fld4::Vector
end
g5 = ((((9 * (-6)) ÷ (-3)) < ((4 % (-3)) - abs((-671)))) ? 5 : 6)
global g6::Int64 = (((!(g5 != (-10))) ? (abs(g5) - g5) : g5) + g5)
g7 = (5 + g5)
sv8 = S1(:d, 7.63, [g6, (-8)])
function f9(; kw10 = -4, kw11 = -3)
    v12 = ((sv8).fld3 == (6.44 - -3.33))
    ((S1((@atomic (sv8).fld2), (-2.03 / -2.11), (@atomic (sv8).fld4)) isa Bool)) && return (sv8).fld3
    return (2.6 / 1.89)
end
function f13(a14, a15::Bool, a16)
    let l17 = a15, l18 = (((true && ("0🐛!" isa Float64)) || (g6 >= max((-2), g7))) ? g5 : g6)
        for i19 in 1:1
            __obs__((@atomic (sv8).fld4))
        end
        l17 = ((g6 - g5) isa Bool)
        local t20::Int64 = g7
    end
    let l21 = ((a15 ? ((a15 && a15) isa Integer) : (:c === :d)) isa Float64)
        v22 = (@atomic (sv8).fld4)
    end
    v23 = (a15 ? string(true, (@atomic (sv8).fld2), (@atomic (sv8).fld2)) : "🐛")
    return Any[g5, a14]
end
v24 = [1.55, -3.48]
__obs__((try (v24)[((g6 + 10) ÷ 3)] catch __e; (:__thrown, nameof(typeof(__e))) end))
let
    local t25::Int64 = ((((true || false) ? g7 : (false ? g6 : g7)) * (((-880) - g7) * (g6 + g7))) % (-3))
    t25 = ((g6 * g5) * (-9))
    if (g7 <= ((g5 + (g5 + g5)) - g5))
        v26 = ((-9), t25, (-5))
        if false
            push!(v24, min((((-0.0 + 8.27) + (sv8).fld3) + ((false && false) ? (-2.03 - g6) : f9())), (get(v24, (g6 ÷ 3), (false ? -0.21 : -1.24)) + f9())))
        else
            local t27::Float64 = 2.68
        end
        fuel28 = 3
        while (!(((true ? t25 : g6) >= (-2)) || ((false ? g7 : (-6)) < (g6 - g6)))) && (fuel28 > 0)
            global fuel28 -= 1
            al29 = sv8
        end
    else
        __obs__((@atomic (sv8).fld2))
    end
    v30 = (false, -5.87, t25)
    try
        __obs__((@atomic (sv8).fld4))
        global g5 = ((true ? (("!yβ∀1" isa Any) ? min(6, g5) : min(t25, g6)) : (g5 * g5)) - (-1))
    catch err31
        v32 = f13((g5 === 0), (false ? false : (f9() == max(5.27, 1.5))), get(v24, ((!true) ? 9223372036854775806 : (true ? g7 : (-2))), get(v24, g6, f9(; kw11 = g5))))
        push!(v24, ((f9() + (-1)) + (-5.82 / g7)))
        ((false && (!((true || false) || (false ? true : true))))) && rethrow()
    else
        v33 = (@atomic (sv8).fld4)
    end
    local t34::Int64 = (((1 - g7) ÷ 1) % 1)
    v35 = f9()
    __obs__(v35)
    __obs__(t34)
    __obs__(v30)
    __obs__(t25)
    __obs__(v24)
    __obs__(sv8)
    __obs__(g7)
    __obs__(g6)
    __obs__(g5)
end

```

## Original program

```julia
mutable struct S1
    @atomic fld2::Symbol
    fld3::Float64
    @atomic fld4::Vector
end
g5 = ((((9 * (-6)) ÷ (-3)) < ((4 % (-3)) - abs((-671)))) ? 5 : 6)
global g6::Int64 = (((!(g5 != (-10))) ? (abs(g5) - g5) : g5) + g5)
g7 = (5 + g5)
sv8 = S1(:d, 7.63, [g6, (-8)])
function f9(; kw10 = -4, kw11 = -3)
    v12 = ((sv8).fld3 == (6.44 - -3.33))
    ((S1((@atomic (sv8).fld2), (-2.03 / -2.11), (@atomic (sv8).fld4)) isa Bool)) && return (sv8).fld3
    return (2.6 / 1.89)
end
function f13(a14, a15::Bool, a16)
    let l17 = a15, l18 = (((true && ("0🐛!" isa Float64)) || (g6 >= max((-2), g7))) ? g5 : g6)
        for i19 in 1:1
            __obs__((@atomic (sv8).fld4))
        end
        l17 = ((g6 - g5) isa Bool)
        local t20::Int64 = g7
    end
    let l21 = ((a15 ? ((a15 && a15) isa Integer) : (:c === :d)) isa Float64)
        v22 = (@atomic (sv8).fld4)
    end
    v23 = (a15 ? string(true, (@atomic (sv8).fld2), (@atomic (sv8).fld2)) : "🐛")
    return Any[g5, a14]
end
v24 = [1.55, -3.48]
__obs__((try (v24)[((g6 + 10) ÷ 3)] catch __e; (:__thrown, nameof(typeof(__e))) end))
let
    local t25::Int64 = ((((true || false) ? g7 : (false ? g6 : g7)) * (((-880) - g7) * (g6 + g7))) % (-3))
    t25 = ((g6 * g5) * (-9))
    if (g7 <= ((g5 + (g5 + g5)) - g5))
        v26 = ((-9), t25, (-5))
        if false
            push!(v24, min((((-0.0 + 8.27) + (sv8).fld3) + ((false && false) ? (-2.03 - g6) : f9())), (get(v24, (g6 ÷ 3), (false ? -0.21 : -1.24)) + f9())))
        else
            local t27::Float64 = 2.68
        end
        fuel28 = 3
        while (!(((true ? t25 : g6) >= (-2)) || ((false ? g7 : (-6)) < (g6 - g6)))) && (fuel28 > 0)
            global fuel28 -= 1
            al29 = sv8
        end
    else
        __obs__((@atomic (sv8).fld2))
    end
    v30 = (false, -5.87, t25)
    try
        __obs__((@atomic (sv8).fld4))
        global g5 = ((true ? (("!yβ∀1" isa Any) ? min(6, g5) : min(t25, g6)) : (g5 * g5)) - (-1))
    catch err31
        v32 = f13((g5 === 0), (false ? false : (f9() == max(5.27, 1.5))), get(v24, ((!true) ? 9223372036854775806 : (true ? g7 : (-2))), get(v24, g6, f9(; kw11 = g5))))
        push!(v24, ((f9() + (-1)) + (-5.82 / g7)))
        ((false && (!((true || false) || (false ? true : true))))) && rethrow()
    else
        v33 = (@atomic (sv8).fld4)
    end
    local t34::Int64 = (((1 - g7) ÷ 1) % 1)
    v35 = f9()
    __obs__(v35)
    __obs__(t34)
    __obs__(v30)
    __obs__(t25)
    __obs__(v24)
    __obs__(sv8)
    __obs__(g7)
    __obs__(g6)
    __obs__(g5)
end

```
