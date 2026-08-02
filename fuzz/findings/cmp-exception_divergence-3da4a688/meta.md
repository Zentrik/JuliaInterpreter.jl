# exception_divergence (cmp-exception_divergence-3da4a688)

- seed: `1200107`
- interp mode: `cmp`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel25`: fuel25 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel25`: fuel25 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
struct S1
    fld2::Symbol
end
mutable struct S3
    @atomic fld4::Int64
end
g5 = true
const g6 = (-7)
global g7::Int64 = (0 - g6)
sv8 = S3((-1))
function f9(a10::Tuple)
    if (:e === :b)
        v11 = ((true ? (("0" != "β!") || ("b" != "a∀")) : (9.18 < -8.21)) ? "" : "a!βx")
    else
        v13 = Float64[-0.0 for c12 in 1:0]
    end
    return (0.92, (-8), :b)
end
function f14(a15::Int64, a16, a17)
    v18 = (@atomic (sv8).fld4)
    @atomic sv8.fld4 = g6
    ((false ? g5 : (!((1 > 10) && (g5 || g5))))) && return a17
    return a17
end
v19 = f14((@atomic (sv8).fld4), [358], f14(((g5 ? g5 : true) ? g6 : (6 - 0)), [1, 1], f14(g6, [g6, 1, 7], f14(g7, [(-9)], "!"))))
@atomic sv8.fld4 = (length(v19) - ((:c === :d) ? (@atomic (sv8).fld4) : (("1b🐛xβ" == v19) ? ((-7) - g6) : (g5 ? g6 : g7))))
__obs__((try Core.modifyfield!(Ref(2), :x, +) catch __e; (:__thrown, nameof(typeof(__e))) end))
let
    v21 = Float64[(-4.43 / c20) for c20 in 1:0]
    @atomic sv8.fld4 = (@atomic (sv8).fld4)
    v23 = ((p22) -> f14(((g5 ? g6 : 10) % (-1)), [g7, g7], f14((@atomic (sv8).fld4), [g7, g6], (g5 ? v19 : "y   "))))
    if ((:e === :b) && (((3 * (-3)) * g6) == g6))
        v24 = (8.35, -2.5, g7)
    end
    fuel25 = 4
    while (min(abs((2.21 + 5.13)), get(v21, g6, (-2.95 + g7))) > -0.0) && (fuel25 > 0)
        global fuel25 -= 1
        v27 = Int64[(g5 ? 2 : ((-9) + (g7 - (c26 - 7)))) for c26 in 1:3 if (0.0 == (-2.5 - ((-0.52 - 6.85) * (-7.81 / 0.33))))]
        v28 = ((length(v19) % 2) - (((@atomic (sv8).fld4) + (@atomic (sv8).fld4)) - ((@atomic (sv8).fld4) * ((-7) - (-7)))))
    end
    push!(v21, 4.2)
    al29 = sv8
    @atomic sv8.fld4 = (@atomic (sv8).fld4)
    push!(v21, get(v21, g6, 9.37))
    v30 = f14((@atomic (al29).fld4), [7], f14((@atomic (sv8).fld4), [g7, (-993), g7], string(f14(1, [(-430)], "ax0α0"), f14(3, [594, 10, g6], v19), f14(g6, [8, (-9)], "β1βax"))))
    __obs__(v30)
    __obs__(al29)
    __obs__((try v23(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v21)
    __obs__(v19)
    __obs__(sv8)
    __obs__(g7)
    __obs__(g6)
    __obs__(g5)
end

```

## Original program

```julia
struct S1
    fld2::Symbol
end
mutable struct S3
    @atomic fld4::Int64
end
g5 = true
const g6 = (-7)
global g7::Int64 = (0 - g6)
sv8 = S3((-1))
function f9(a10::Tuple)
    if (:e === :b)
        v11 = ((true ? (("0" != "β!") || ("b" != "a∀")) : (9.18 < -8.21)) ? "" : "a!βx")
    else
        v13 = Float64[-0.0 for c12 in 1:0]
    end
    return (0.92, (-8), :b)
end
function f14(a15::Int64, a16, a17)
    v18 = (@atomic (sv8).fld4)
    @atomic sv8.fld4 = g6
    ((false ? g5 : (!((1 > 10) && (g5 || g5))))) && return a17
    return a17
end
v19 = f14((@atomic (sv8).fld4), [358], f14(((g5 ? g5 : true) ? g6 : (6 - 0)), [1, 1], f14(g6, [g6, 1, 7], f14(g7, [(-9)], "!"))))
@atomic sv8.fld4 = (length(v19) - ((:c === :d) ? (@atomic (sv8).fld4) : (("1b🐛xβ" == v19) ? ((-7) - g6) : (g5 ? g6 : g7))))
__obs__((try Core.modifyfield!(Ref(2), :x, +) catch __e; (:__thrown, nameof(typeof(__e))) end))
let
    v21 = Float64[(-4.43 / c20) for c20 in 1:0]
    @atomic sv8.fld4 = (@atomic (sv8).fld4)
    v23 = ((p22) -> f14(((g5 ? g6 : 10) % (-1)), [g7, g7], f14((@atomic (sv8).fld4), [g7, g6], (g5 ? v19 : "y   "))))
    if ((:e === :b) && (((3 * (-3)) * g6) == g6))
        v24 = (8.35, -2.5, g7)
    end
    fuel25 = 4
    while (min(abs((2.21 + 5.13)), get(v21, g6, (-2.95 + g7))) > -0.0) && (fuel25 > 0)
        global fuel25 -= 1
        v27 = Int64[(g5 ? 2 : ((-9) + (g7 - (c26 - 7)))) for c26 in 1:3 if (0.0 == (-2.5 - ((-0.52 - 6.85) * (-7.81 / 0.33))))]
        v28 = ((length(v19) % 2) - (((@atomic (sv8).fld4) + (@atomic (sv8).fld4)) - ((@atomic (sv8).fld4) * ((-7) - (-7)))))
    end
    push!(v21, 4.2)
    al29 = sv8
    @atomic sv8.fld4 = (@atomic (sv8).fld4)
    push!(v21, get(v21, g6, 9.37))
    v30 = f14((@atomic (al29).fld4), [7], f14((@atomic (sv8).fld4), [g7, (-993), g7], string(f14(1, [(-430)], "ax0α0"), f14(3, [594, 10, g6], v19), f14(g6, [8, (-9)], "β1βax"))))
    __obs__(v30)
    __obs__(al29)
    __obs__((try v23(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v21)
    __obs__(v19)
    __obs__(sv8)
    __obs__(g7)
    __obs__(g6)
    __obs__(g5)
end

```
