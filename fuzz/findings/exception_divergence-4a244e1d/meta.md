# exception_divergence (exception_divergence-4a244e1d)

- seed: `5300004`
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel38`: fuel38 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel38`: fuel38 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
mutable struct S1
    @atomic fld2::Vector
    @atomic fld3::Bool
    @atomic fld4::Bool
end
mutable struct S5
    fld6::Symbol
    @atomic fld7::Int64
end
g8 = ((418 - ((-6) + (-3))) != 1)
g9 = ((5 % (-3)) + ((((g8 ? 10 : (-2)) - (0 + (-9223372036854775808))) - 0) + 52))
sv10 = S1([1.7976931348623157e308, -8.51], true, g8)
sv11 = S5(:b, g9)
function f12()
    nothing
    return S5((sv11).fld6, g9)
end
function f13()
    v14 = (5.45, :c, :c)
    v15 = ("βb1xβ!!α", 6.75)
    return "∀0 x∀1yyb"
end
function f16()
    nothing
    return ("0 αβy", -6.62)
end
function f17(a18, a19::Float64, a20::Float64, va21...; kw22 = 0, kw23 = -3)
    if (a19 isa Any)
        v24 = S1([a19], false, g8)
        __obs__(string((sv11).fld6, (string(string((2 + (-8)), false, (g9 * g9)), (g8 ? ("αyxa!0" === " yy∀0 1∀") : g8)) == "0🐛b ayy")))
        v25 = f12()
        v26 = ((((a20 - kw23) * (a19 - abs(7.22))) + ((a19 + (2.2250738585072014e-308 - 0.81)) / a20)) / a19)
    else
        __obs__((9, "y"))
        local t27::Int64 = ((-5.8 < a20) ? 684 : g9)
        local t28::Float64 = a19
    end
    fuel29 = 2
    while (a20 >= (9.2 + ((@atomic (sv10).fld3) ? (-2.9 + -9.35) : ((a20 + g9) + (-9.49 / a19))))) && (fuel29 > 0)
        fuel29 -= 1
        __obs__(((S5((sv11).fld6, kw23) isa Bool) || (!true)))
        v30 = f12()
    end
    return sv10
end
function f31(a32, a33, a34, va35...)
    local t36::Float64 = -6.12
    return -9.66
end
for i37 in 1:3
    (("b" != string(max(((true ? 8 : (-93)) * 7), ((i37 + g9) % 1)), f13(), f13()))) && break
end
__obs__("b∀🐛a")
let
    fuel38 = 1
    while ((string((g9 - g9), (@atomic (sv10).fld4), (sv11).fld6) < "") && g8) && (fuel38 > 0)
        global fuel38 -= 1
        try
            for i40 in 1:3
                ((true && ((true === ((g9 < i40) && ("!yb" == "y! β "))) && (((i40 + i40) - (g9 + (-2))) >= (@atomic (sv11).fld7))))) && break
                v41 = (i40 isa Integer)
            end
        catch err39
            __obs__("!")
        end
        if ((NaN + ((f31(g8, 0.1, g9, -3.11) * Inf) - 0.0)) < -7.06)
            v42 = f16()
            v43 = S1([-8.82, 9.73, 0.1], g8, false)
            if (@atomic (v43).fld3)
                __obs__(((@atomic (sv10).fld4) ? (g9 % (-1)) : (-552)))
            else
                __obs__((try first(Core.modifyfield!(Ref(2), :x, +, 5)) catch __e; (:__thrown, nameof(typeof(__e))) end))
                __obs__(((-1), "xy"))
            end
        else
            __obs__([g9])
            v44 = S5(:b, g9)
        end
        __obs__(((g9 ÷ 1) - (@atomic (sv11).fld7)))
    end
    v45 = ((-2), false, g9)
    al46 = sv10
    al47 = sv10
    let l48 = (((@atomic (sv11).fld7) - 751) * (g9 * min(g9, g9))), l49 = (sv11).fld6
        __obs__(2)
        __obs__(f13())
    end
    v50 = f17(Any[1.5], 7.27, (((max(5.45, -9.77) * (false ? 2.63 : -2.5)) - -0.21) / ((f31(1.05, 6.28, g9) * (g8 ? 5 : g9)) - g9)), ; kw22 = ((((10 - g9) != 4) || (f31(0.1, 6.87, g9) > (5.25 / -2.5))) ? g9 : (-4)))
    for i51 in 1:6
        v52 = ((-2), g9, i51)
        if ((-2.43 >= 4.26) && ((!(7.01 > (6.76 / 5))) ? (@atomic (al46).fld4) : ((-1) >= (i51 + i51))))
            __obs__((g9, "∀"))
        end
        (("1  0x🐛yy y" < string(((@atomic (al47).fld3) || true), (((4.27 > 0.33) ? i51 : (9 + i51)) ÷ 1)))) && break
        if (true || (@atomic (sv10).fld4))
            v54 = Int64[(-10) for c53 in 1:4 if ("" < "b1")]
            v55 = [-0.51, 1.5, -2.5]
            push!(v54, ((@atomic (sv11).fld7) - (min(length(v54), ((g8 ? (-2) : (-8)) + i51)) % 3)))
        end
    end
    local t56::Int64 = 316
    v57 = 0.0
    for i58 in 1:2
        __obs__((@atomic (al47).fld3))
        __obs__((t56, "1"))
        __obs__((t56, "x1"))
    end
    v59 = [t56, (-4)]
    __obs__((sv11).fld6)
    let l60 = (((v57 + v57) * ((5.83 / v57) + (f31(:b, v57, g9) - (-8.1 + v57)))) - (abs(v57) + f31(:d, f31((:e, true), v57, g9, t56), (@atomic (sv11).fld7)))), l61 = (min(length(v59), ((@atomic (sv11).fld7) * (@atomic (sv11).fld7))) ÷ (-1))
        v62 = ((get(v59, (l61 % 7), ((3 * 6) + get(v59, 10, g9))) % 2) * ((@atomic (sv11).fld7) + get(v59, min(((-9) * l61), ((-1) - 10)), ((4 * l61) + (@atomic (sv11).fld7)))))
    end
    try
        fuel64 = 6
        while true && (fuel64 > 0)
            fuel64 -= 1
            try; v59[(@atomic (sv11).fld7)] = max((g9 - get(v59, (g9 - get(v59, t56, g9)), get(v59, ((-10) * g9), get(v59, g9, t56)))), 8); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
            v65 = S5((sv11).fld6, ((@atomic (sv11).fld7) - t56))
            if (4.72 isa AbstractString)
                local t66::Float64 = v57
                v67 = (g8 || (f31(-3.12, ((t66 + 4) / (v57 / t56)), t56, (v59)...) >= v57))
            end
        end
    catch err63
        v70 = ((p68, p69) -> f13())
        __obs__(f13())
    finally
        if ((t56 + ((@atomic (sv11).fld7) - (get(v59, 909, g9) ÷ (-3)))) != abs((@atomic (sv11).fld7)))
            push!(v59, g9)
            try; v59[(-6)] = ((("1αxyα!∀0" != "🐛0") || (@atomic (v50).fld4)) ? (get(v59, t56, ((1 > t56) ? t56 : t56)) + t56) : g9); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
            v72 = ((p71) -> true)
        end
    end
    v73 = Any["!by1∀1βa1"]
    v74 = S1((@atomic (al46).fld2), ((!((-8.02 >= 7.0) || (@atomic (al47).fld4))) && (((false ? v57 : 3.19) <= (false ? 0.35 : v57)) || ((g8 ? (-8) : 10) >= min(427, 6)))), (@atomic (sv10).fld3))
    __obs__([g9])
    __obs__(v74)
    __obs__(v73)
    __obs__(v59)
    __obs__(v57)
    __obs__(t56)
    __obs__(v50)
    __obs__(al47)
    __obs__(al46)
    __obs__(v45)
    __obs__(sv11)
    __obs__(sv10)
    __obs__(g9)
    __obs__(g8)
end

```

## Original program

```julia
mutable struct S1
    @atomic fld2::Vector
    @atomic fld3::Bool
    @atomic fld4::Bool
end
mutable struct S5
    fld6::Symbol
    @atomic fld7::Int64
end
g8 = ((418 - ((-6) + (-3))) != 1)
g9 = ((5 % (-3)) + ((((g8 ? 10 : (-2)) - (0 + (-9223372036854775808))) - 0) + 52))
sv10 = S1([1.7976931348623157e308, -8.51], true, g8)
sv11 = S5(:b, g9)
function f12()
    nothing
    return S5((sv11).fld6, g9)
end
function f13()
    v14 = (5.45, :c, :c)
    v15 = ("βb1xβ!!α", 6.75)
    return "∀0 x∀1yyb"
end
function f16()
    nothing
    return ("0 αβy", -6.62)
end
function f17(a18, a19::Float64, a20::Float64, va21...; kw22 = 0, kw23 = -3)
    if (a19 isa Any)
        v24 = S1([a19], false, g8)
        __obs__(string((sv11).fld6, (string(string((2 + (-8)), false, (g9 * g9)), (g8 ? ("αyxa!0" === " yy∀0 1∀") : g8)) == "0🐛b ayy")))
        v25 = f12()
        v26 = ((((a20 - kw23) * (a19 - abs(7.22))) + ((a19 + (2.2250738585072014e-308 - 0.81)) / a20)) / a19)
    else
        __obs__((9, "y"))
        local t27::Int64 = ((-5.8 < a20) ? 684 : g9)
        local t28::Float64 = a19
    end
    fuel29 = 2
    while (a20 >= (9.2 + ((@atomic (sv10).fld3) ? (-2.9 + -9.35) : ((a20 + g9) + (-9.49 / a19))))) && (fuel29 > 0)
        fuel29 -= 1
        __obs__(((S5((sv11).fld6, kw23) isa Bool) || (!true)))
        v30 = f12()
    end
    return sv10
end
function f31(a32, a33, a34, va35...)
    local t36::Float64 = -6.12
    return -9.66
end
for i37 in 1:3
    (("b" != string(max(((true ? 8 : (-93)) * 7), ((i37 + g9) % 1)), f13(), f13()))) && break
end
__obs__("b∀🐛a")
let
    fuel38 = 1
    while ((string((g9 - g9), (@atomic (sv10).fld4), (sv11).fld6) < "") && g8) && (fuel38 > 0)
        global fuel38 -= 1
        try
            for i40 in 1:3
                ((true && ((true === ((g9 < i40) && ("!yb" == "y! β "))) && (((i40 + i40) - (g9 + (-2))) >= (@atomic (sv11).fld7))))) && break
                v41 = (i40 isa Integer)
            end
        catch err39
            __obs__("!")
        end
        if ((NaN + ((f31(g8, 0.1, g9, -3.11) * Inf) - 0.0)) < -7.06)
            v42 = f16()
            v43 = S1([-8.82, 9.73, 0.1], g8, false)
            if (@atomic (v43).fld3)
                __obs__(((@atomic (sv10).fld4) ? (g9 % (-1)) : (-552)))
            else
                __obs__((try first(Core.modifyfield!(Ref(2), :x, +, 5)) catch __e; (:__thrown, nameof(typeof(__e))) end))
                __obs__(((-1), "xy"))
            end
        else
            __obs__([g9])
            v44 = S5(:b, g9)
        end
        __obs__(((g9 ÷ 1) - (@atomic (sv11).fld7)))
    end
    v45 = ((-2), false, g9)
    al46 = sv10
    al47 = sv10
    let l48 = (((@atomic (sv11).fld7) - 751) * (g9 * min(g9, g9))), l49 = (sv11).fld6
        __obs__(2)
        __obs__(f13())
    end
    v50 = f17(Any[1.5], 7.27, (((max(5.45, -9.77) * (false ? 2.63 : -2.5)) - -0.21) / ((f31(1.05, 6.28, g9) * (g8 ? 5 : g9)) - g9)), ; kw22 = ((((10 - g9) != 4) || (f31(0.1, 6.87, g9) > (5.25 / -2.5))) ? g9 : (-4)))
    for i51 in 1:6
        v52 = ((-2), g9, i51)
        if ((-2.43 >= 4.26) && ((!(7.01 > (6.76 / 5))) ? (@atomic (al46).fld4) : ((-1) >= (i51 + i51))))
            __obs__((g9, "∀"))
        end
        (("1  0x🐛yy y" < string(((@atomic (al47).fld3) || true), (((4.27 > 0.33) ? i51 : (9 + i51)) ÷ 1)))) && break
        if (true || (@atomic (sv10).fld4))
            v54 = Int64[(-10) for c53 in 1:4 if ("" < "b1")]
            v55 = [-0.51, 1.5, -2.5]
            push!(v54, ((@atomic (sv11).fld7) - (min(length(v54), ((g8 ? (-2) : (-8)) + i51)) % 3)))
        end
    end
    local t56::Int64 = 316
    v57 = 0.0
    for i58 in 1:2
        __obs__((@atomic (al47).fld3))
        __obs__((t56, "1"))
        __obs__((t56, "x1"))
    end
    v59 = [t56, (-4)]
    __obs__((sv11).fld6)
    let l60 = (((v57 + v57) * ((5.83 / v57) + (f31(:b, v57, g9) - (-8.1 + v57)))) - (abs(v57) + f31(:d, f31((:e, true), v57, g9, t56), (@atomic (sv11).fld7)))), l61 = (min(length(v59), ((@atomic (sv11).fld7) * (@atomic (sv11).fld7))) ÷ (-1))
        v62 = ((get(v59, (l61 % 7), ((3 * 6) + get(v59, 10, g9))) % 2) * ((@atomic (sv11).fld7) + get(v59, min(((-9) * l61), ((-1) - 10)), ((4 * l61) + (@atomic (sv11).fld7)))))
    end
    try
        fuel64 = 6
        while true && (fuel64 > 0)
            fuel64 -= 1
            try; v59[(@atomic (sv11).fld7)] = max((g9 - get(v59, (g9 - get(v59, t56, g9)), get(v59, ((-10) * g9), get(v59, g9, t56)))), 8); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
            v65 = S5((sv11).fld6, ((@atomic (sv11).fld7) - t56))
            if (4.72 isa AbstractString)
                local t66::Float64 = v57
                v67 = (g8 || (f31(-3.12, ((t66 + 4) / (v57 / t56)), t56, (v59)...) >= v57))
            end
        end
    catch err63
        v70 = ((p68, p69) -> f13())
        __obs__(f13())
    finally
        if ((t56 + ((@atomic (sv11).fld7) - (get(v59, 909, g9) ÷ (-3)))) != abs((@atomic (sv11).fld7)))
            push!(v59, g9)
            try; v59[(-6)] = ((("1αxyα!∀0" != "🐛0") || (@atomic (v50).fld4)) ? (get(v59, t56, ((1 > t56) ? t56 : t56)) + t56) : g9); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
            v72 = ((p71) -> true)
        end
    end
    v73 = Any["!by1∀1βa1"]
    v74 = S1((@atomic (al46).fld2), ((!((-8.02 >= 7.0) || (@atomic (al47).fld4))) && (((false ? v57 : 3.19) <= (false ? 0.35 : v57)) || ((g8 ? (-8) : 10) >= min(427, 6)))), (@atomic (sv10).fld3))
    __obs__([g9])
    __obs__(v74)
    __obs__(v73)
    __obs__(v59)
    __obs__(v57)
    __obs__(t56)
    __obs__(v50)
    __obs__(al47)
    __obs__(al46)
    __obs__(v45)
    __obs__(sv11)
    __obs__(sv10)
    __obs__(g9)
    __obs__(g8)
end

```
