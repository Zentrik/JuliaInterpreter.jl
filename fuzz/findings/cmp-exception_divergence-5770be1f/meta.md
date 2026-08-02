# exception_divergence (cmp-exception_divergence-5770be1f)

- seed: `5300841`
- interp mode: `cmp`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel37`: fuel37 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel37`: fuel37 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
struct S1
    fld2::Float64
end
mutable struct S3
    @atomic fld4::Int64
    fld5::Int64
end
g6 = string(((S3(5, (true ? 8 : 9)) isa Any) isa Number), string((((true === true) ? (-8.19 * 0.1) : 4.77) >= 3.67), true))
global g7::Int64 = (-5)
g8 = g7
g9 = string(:e, (("🐛" == g6) ? ((!(4 < g7)) ? g6 : (false ? g6 : g6)) : "🐛αby0!bx🐛!"), :d)
function f10(a11)
    nothing
    return (-390)
end
if ("1!α🐛αxα∀" < g6)
    u12 = ((!(string(g9, g9) != string((false === false), :e, length(g6)))) ? -8.87 : min(6.92, min((max(0.1, 8.99) * (false ? 8.06 : 0.1)), Inf)))
end
__obs__(@isdefined(u12))
__obs__(try; u12; catch __e; (:__undef, nameof(typeof(__e))) end)
__obs__((g8, "∀y∀ β"))
__obs__((try Base.donotdelete(1) catch __e; (:__thrown, nameof(typeof(__e))) end))
let
    __obs__("αβ0α1xbyab")
    if ((try Base.arrayref(true, [1,2,3], 4) catch __e; (:__thrown, nameof(typeof(__e))) end) isa String)
        u13 = g8
    end
    __obs__(@isdefined(u13))
    __obs__(try; u13; catch __e; (:__undef, nameof(typeof(__e))) end)
    v18 = (((g8 - f10(((p14, p15) -> (-6)))) + (g8 + length(g9))) - (((length(g9) * f10(((p16, p17) -> Inf))) ÷ (-3)) + (abs((-3)) + ((g7 % (-3)) + (g7 ÷ 2)))))
    v19 = string("", g9, :b)
    v20 = [2.99, -0.0]
    local t21::Int64 = (-10)
    if (((min(min(2.39, -6.89), (-1.66 - -8.37)) + (-1.04 + (-3.56 * 3.68))) / 9.24) <= ((abs(f10(((p23, p24) -> "aβ yb"))) === (-7)) ? (((false ? -6.8 : -1.14) / (true ? -4.26 : -4.41)) + (("! y!010βα∀" != g9) ? 7.68 : (-5.35 - 0.1))) : (((true ? -1.12 : -8.12) * (g7 - v18)) + f10(((p25, p26) -> false)))))
        u22 = (string(true, string(g9, (((-3) ÷ (-1)) < g7), ((v19 < "🐛a1yyαx∀1") ? "x!1β" : v19)), (!(string("🐛αb0bαβ0b", :e, true) isa Int64))) < ((get(v20, f10(((p27, p28) -> "a 🐛")), get(v20, 880, 2.220446049250313e-16)) isa Float64) ? g6 : string("1a🐛 0 x1", ((7.99 * NaN) == (9.33 + (-1))), (("a🐛y" isa Bool) ? string(v18, :a, "10b 🐛abaay") : (true ? g6 : v19)))))
    end
    __obs__(@isdefined(u22))
    __obs__(try; u22; catch __e; (:__undef, nameof(typeof(__e))) end)
    v29 = [g7]
    v30 = S1(get(v20, ((-10) + ((true && false) ? get(v29, t21, (-7)) : (v18 + g8))), -8.25))
    v31 = length(g9)
    let l32 = (1 != t21), l33 = -1.87
        v34 = Any[t21, v31]
        if ((!(!((v31 % 2) <= ((-4) - 2)))) ? (!(string(length(v29), (!l32)) != string(:c, (l33 > l33), string(v31, "βα0b 0b0α")))) : ((try nfields((1, 2, 3)) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Any))
            u35 = (l33 - length(v34))
        end
        __obs__(@isdefined(u35))
        __obs__(try; u35; catch __e; (:__undef, nameof(typeof(__e))) end)
        v36 = S1(l33)
        __obs__(:a)
    end
    fuel37 = 6
    while ("!1∀ya!bα" != g9) && (fuel37 > 0)
        global fuel37 -= 1
        __obs__((((!(min(-2.56, -8.1) isa String)) ? ((g7 >= t21) ? ((true ? true : false) ? ("y∀aβy0ba∀β" != v19) : (3 < (-2))) : (false === (!true))) : (!(!(7.2 > 1.7976931348623157e308)))) || (((4.62 + (v30).fld2) < (0.61 - 2.2250738585072014e-308)) ? (min((-0.0 / -6.35), get(v20, v31, -0.2)) isa Float64) : (:b === :a))))
        v38 = "a10 ∀y0b∀y"
        fuel39 = 3
        while (string((((v30).fld2 isa Bool) ? "y0β " : "∀yα0"), v18) == string((min((true ? v31 : v18), f10(((p40, p41) -> true))) <= f10(((p42, p43) -> p42))), (((t21 >= v31) || (564 isa Integer)) || (!false)), v38)) && (fuel39 > 0)
            fuel39 -= 1
            for i44 in 1:4
                v47 = ((p45, p46) -> ((((false ? 7.7 : -2.67) > (v30).fld2) ? get(v20, (v18 % 2), 0.0) : 4.99) - (v18 + get(v29, ((-4) % (-1)), (-3)))))
                v48 = [NaN]
            end
            try; v29[g7] = g7; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        end
    end
    if (-7.27 >= min(((v30).fld2 / ((v30).fld2 + get(v20, g7, -7.41))), abs(get(v20, 2, (true ? -2.62 : -7.87)))))
        u49 = (((v18 - f10(((p50, p51) -> v19))) isa Number) ? (v30).fld2 : min((((-3) isa Integer) ? ((-0.06 - 6.39) / 6.38) : (-8.02 * (false ? 6.72 : 0.0))), (2.48 - (6.48 + (v30).fld2))))
    end
    __obs__(@isdefined(u49))
    __obs__(try; u49; catch __e; (:__undef, nameof(typeof(__e))) end)
    __obs__((g7, "xxy "))
    push!(v20, (-1.38 * ((string((false ? g9 : "aα!α"), :b, (false ? 9 : 9)) == string(string(false, :d), :d)) ? ((v19 == string(v18, g9, g6)) ? ((false ? 8.17 : -6.64) + (-0.06 + -9.98)) : (v30).fld2) : (2.220446049250313e-16 * ((t21 * v31) + (false ? v31 : (-3)))))))
    fuel52 = 5
    while (((-6.69 - length(g9)) / (v30).fld2) > ((false ? ((1.5 isa Any) && false) : true) ? get(v20, ((!true) ? length(v29) : ((-9) * t21)), -2.5) : -6.11)) && (fuel52 > 0)
        global fuel52 -= 1
        try; v29[v18] = (-1); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        __obs__((((((v30).fld2 / -2.5) / (-6)) / (((v31 != (-8)) ? (-6.12 * -0.12) : (0.67 / 0.34)) * (v30).fld2)) - -6.77))
        v53 = S1((v30).fld2)
        push!(v20, ((!((false || (:d === :e)) || false)) ? ((((v53).fld2 >= (-6.67 - -7.9)) || (string(g6, "yaxaα") < "01αyx ")) ? (min((-2.08 * g7), -2.5) * ((-4.73 / -2.54) / -2.7)) : ((v53).fld2 - -6.02)) : 1.03))
    end
    al54 = v20
    v56 = Float64[7.88 for c55 in 1:3 if (!false)]
    local t57::Int64 = (get(v29, (7 - ((true ? g7 : g8) + (-5))), t21) ÷ (-3))
    v58 = true
    al59 = al54
    __obs__(al59)
    __obs__(v58)
    __obs__(t57)
    __obs__(v56)
    __obs__(al54)
    __obs__(v31)
    __obs__(v30)
    __obs__(v29)
    __obs__(t21)
    __obs__(v20)
    __obs__(v19)
    __obs__(v18)
    __obs__(g9)
    __obs__(g8)
    __obs__(g7)
    __obs__(g6)
end

```

## Original program

```julia
struct S1
    fld2::Float64
end
mutable struct S3
    @atomic fld4::Int64
    fld5::Int64
end
g6 = string(((S3(5, (true ? 8 : 9)) isa Any) isa Number), string((((true === true) ? (-8.19 * 0.1) : 4.77) >= 3.67), true))
global g7::Int64 = (-5)
g8 = g7
g9 = string(:e, (("🐛" == g6) ? ((!(4 < g7)) ? g6 : (false ? g6 : g6)) : "🐛αby0!bx🐛!"), :d)
function f10(a11)
    nothing
    return (-390)
end
if ("1!α🐛αxα∀" < g6)
    u12 = ((!(string(g9, g9) != string((false === false), :e, length(g6)))) ? -8.87 : min(6.92, min((max(0.1, 8.99) * (false ? 8.06 : 0.1)), Inf)))
end
__obs__(@isdefined(u12))
__obs__(try; u12; catch __e; (:__undef, nameof(typeof(__e))) end)
__obs__((g8, "∀y∀ β"))
__obs__((try Base.donotdelete(1) catch __e; (:__thrown, nameof(typeof(__e))) end))
let
    __obs__("αβ0α1xbyab")
    if ((try Base.arrayref(true, [1,2,3], 4) catch __e; (:__thrown, nameof(typeof(__e))) end) isa String)
        u13 = g8
    end
    __obs__(@isdefined(u13))
    __obs__(try; u13; catch __e; (:__undef, nameof(typeof(__e))) end)
    v18 = (((g8 - f10(((p14, p15) -> (-6)))) + (g8 + length(g9))) - (((length(g9) * f10(((p16, p17) -> Inf))) ÷ (-3)) + (abs((-3)) + ((g7 % (-3)) + (g7 ÷ 2)))))
    v19 = string("", g9, :b)
    v20 = [2.99, -0.0]
    local t21::Int64 = (-10)
    if (((min(min(2.39, -6.89), (-1.66 - -8.37)) + (-1.04 + (-3.56 * 3.68))) / 9.24) <= ((abs(f10(((p23, p24) -> "aβ yb"))) === (-7)) ? (((false ? -6.8 : -1.14) / (true ? -4.26 : -4.41)) + (("! y!010βα∀" != g9) ? 7.68 : (-5.35 - 0.1))) : (((true ? -1.12 : -8.12) * (g7 - v18)) + f10(((p25, p26) -> false)))))
        u22 = (string(true, string(g9, (((-3) ÷ (-1)) < g7), ((v19 < "🐛a1yyαx∀1") ? "x!1β" : v19)), (!(string("🐛αb0bαβ0b", :e, true) isa Int64))) < ((get(v20, f10(((p27, p28) -> "a 🐛")), get(v20, 880, 2.220446049250313e-16)) isa Float64) ? g6 : string("1a🐛 0 x1", ((7.99 * NaN) == (9.33 + (-1))), (("a🐛y" isa Bool) ? string(v18, :a, "10b 🐛abaay") : (true ? g6 : v19)))))
    end
    __obs__(@isdefined(u22))
    __obs__(try; u22; catch __e; (:__undef, nameof(typeof(__e))) end)
    v29 = [g7]
    v30 = S1(get(v20, ((-10) + ((true && false) ? get(v29, t21, (-7)) : (v18 + g8))), -8.25))
    v31 = length(g9)
    let l32 = (1 != t21), l33 = -1.87
        v34 = Any[t21, v31]
        if ((!(!((v31 % 2) <= ((-4) - 2)))) ? (!(string(length(v29), (!l32)) != string(:c, (l33 > l33), string(v31, "βα0b 0b0α")))) : ((try nfields((1, 2, 3)) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Any))
            u35 = (l33 - length(v34))
        end
        __obs__(@isdefined(u35))
        __obs__(try; u35; catch __e; (:__undef, nameof(typeof(__e))) end)
        v36 = S1(l33)
        __obs__(:a)
    end
    fuel37 = 6
    while ("!1∀ya!bα" != g9) && (fuel37 > 0)
        global fuel37 -= 1
        __obs__((((!(min(-2.56, -8.1) isa String)) ? ((g7 >= t21) ? ((true ? true : false) ? ("y∀aβy0ba∀β" != v19) : (3 < (-2))) : (false === (!true))) : (!(!(7.2 > 1.7976931348623157e308)))) || (((4.62 + (v30).fld2) < (0.61 - 2.2250738585072014e-308)) ? (min((-0.0 / -6.35), get(v20, v31, -0.2)) isa Float64) : (:b === :a))))
        v38 = "a10 ∀y0b∀y"
        fuel39 = 3
        while (string((((v30).fld2 isa Bool) ? "y0β " : "∀yα0"), v18) == string((min((true ? v31 : v18), f10(((p40, p41) -> true))) <= f10(((p42, p43) -> p42))), (((t21 >= v31) || (564 isa Integer)) || (!false)), v38)) && (fuel39 > 0)
            fuel39 -= 1
            for i44 in 1:4
                v47 = ((p45, p46) -> ((((false ? 7.7 : -2.67) > (v30).fld2) ? get(v20, (v18 % 2), 0.0) : 4.99) - (v18 + get(v29, ((-4) % (-1)), (-3)))))
                v48 = [NaN]
            end
            try; v29[g7] = g7; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        end
    end
    if (-7.27 >= min(((v30).fld2 / ((v30).fld2 + get(v20, g7, -7.41))), abs(get(v20, 2, (true ? -2.62 : -7.87)))))
        u49 = (((v18 - f10(((p50, p51) -> v19))) isa Number) ? (v30).fld2 : min((((-3) isa Integer) ? ((-0.06 - 6.39) / 6.38) : (-8.02 * (false ? 6.72 : 0.0))), (2.48 - (6.48 + (v30).fld2))))
    end
    __obs__(@isdefined(u49))
    __obs__(try; u49; catch __e; (:__undef, nameof(typeof(__e))) end)
    __obs__((g7, "xxy "))
    push!(v20, (-1.38 * ((string((false ? g9 : "aα!α"), :b, (false ? 9 : 9)) == string(string(false, :d), :d)) ? ((v19 == string(v18, g9, g6)) ? ((false ? 8.17 : -6.64) + (-0.06 + -9.98)) : (v30).fld2) : (2.220446049250313e-16 * ((t21 * v31) + (false ? v31 : (-3)))))))
    fuel52 = 5
    while (((-6.69 - length(g9)) / (v30).fld2) > ((false ? ((1.5 isa Any) && false) : true) ? get(v20, ((!true) ? length(v29) : ((-9) * t21)), -2.5) : -6.11)) && (fuel52 > 0)
        global fuel52 -= 1
        try; v29[v18] = (-1); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        __obs__((((((v30).fld2 / -2.5) / (-6)) / (((v31 != (-8)) ? (-6.12 * -0.12) : (0.67 / 0.34)) * (v30).fld2)) - -6.77))
        v53 = S1((v30).fld2)
        push!(v20, ((!((false || (:d === :e)) || false)) ? ((((v53).fld2 >= (-6.67 - -7.9)) || (string(g6, "yaxaα") < "01αyx ")) ? (min((-2.08 * g7), -2.5) * ((-4.73 / -2.54) / -2.7)) : ((v53).fld2 - -6.02)) : 1.03))
    end
    al54 = v20
    v56 = Float64[7.88 for c55 in 1:3 if (!false)]
    local t57::Int64 = (get(v29, (7 - ((true ? g7 : g8) + (-5))), t21) ÷ (-3))
    v58 = true
    al59 = al54
    __obs__(al59)
    __obs__(v58)
    __obs__(t57)
    __obs__(v56)
    __obs__(al54)
    __obs__(v31)
    __obs__(v30)
    __obs__(v29)
    __obs__(t21)
    __obs__(v20)
    __obs__(v19)
    __obs__(v18)
    __obs__(g9)
    __obs__(g8)
    __obs__(g7)
    __obs__(g6)
end

```
