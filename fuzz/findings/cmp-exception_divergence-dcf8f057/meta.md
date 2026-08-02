# exception_divergence (cmp-exception_divergence-dcf8f057)

- seed: `5300100`
- interp mode: `cmp`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global v39`: v39 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global v39`: v39 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
struct S1
    fld2::Float64
    fld3::Float64
    fld4::Bool
end
struct S5
    fld6::Bool
    fld7::Float64
    fld8::Bool
end
g9 = ((-6) + ((((-10) * ((-958) * 444)) % 3) * (0 - ((true && false) ? (-2) : 1))))
g10 = -5.8
const g11 = ((-3) ÷ (-1))
function f12(a13, a14, a15::Float64)
    __obs__(((a13).fld7 / (a13).fld7))
    return min((((-1) - min(6, abs(g11))) - (((1.5 == a15) ? (g11 - (-6)) : (-8)) * g11)), g9)
end
function f16(a17, a18::Int64; kw19 = 5, kw20 = -4)
    __obs__([a18, a18, kw19])
    return f12(S5(false, g10, true), ((-8) - kw20), g10)
end
function f16(a21::S5, a22::Int64)
    nothing
    return (g11 * (a22 - (-7)))
end
function f23(a24, a25)
    nothing
    return -5.32
end
function fr26(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr26(n - 1, acc + abs(g11))
end
v28 = Float64[-0.0 for c27 in 1:3]
__obs__([g11, (-3)])
__obs__(("0a🐛1ββa" != "🐛y∀x0 "))
try; v28[(f16((g9 + g9), ((g11 + g9) - (10 * length(v28)))) * fr26(5, f12(S5((872 != g11), g10, (g10 isa Any)), f12(S5(false, g10, false), (g9 * g9), (g10 + g10)), g10)))] = g10; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
let
    if ("1bα∀yxaa! " != " ")
        v29 = S5((g10 == (min((g10 + 7.61), f23(10, Any[g11, g9, "!1aaββ"])) / -4.1)), g10, true)
        v30 = S5((g9 != (min(f16((-6), (-769), ; kw19 = g11), f12(S5(true, g10, true), 0, g10)) + (g11 + (-7)))), 9.52, ((-9) isa String))
    else
        let l31 = (max((((0 ÷ 1) - g9) - f16(g9, g11)), (-445)) ÷ 3), l32 = " xy🐛1y0"
            v33 = S1(f23(7, Any["", nothing, g11]), f23(((length(l32) * f16(S5(true, 4.26, true), (-8))) * (f16(l31, l31, ; kw19 = 3, kw20 = g9) * (0 - l31))), Any[nothing, l32, v28]), false)
            if ((!(l32 < ((l32 != l32) ? l32 : (false ? "yβαx🐛aβa" : "")))) && ((v33).fld4 ? ((v33).fld4 && (v33).fld4) : ((f16(g9, 714, ; kw20 = (-5)) * ((-6) * (-10))) isa Integer)))
                if true
                    u34 = f16((((false || true) || ((false ? "y🐛" : "1") isa Float64)) ? f12(S5(false, g10, false), g9, (v33).fld2) : (min(g9, abs((-257))) + 2)), g9, ; kw20 = g9)
                end
                __obs__(@isdefined(u34))
                __obs__(try; u34; catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            v35 = v33
        end
        if (!(true ? ((f12(S5(false, g10, true), (-9), g10) * (10 - g11)) === ((false || false) ? (1 ÷ 7) : (-6))) : (((!false) ? (-6) : fr26((-5), 8)) == f12(S5(false, -5.12, true), (g11 ÷ 2), (true ? g10 : -7.86)))))
            u36 = true
        end
        __obs__(@isdefined(u36))
        __obs__(try; u36; catch __e; (:__undef, nameof(typeof(__e))) end)
        try; v28[(g9 * (2 * g9))] = (get(v28, g11, max(f23(g11, Any[g9, true, g10]), 5.99)) / ((((g10 - g10) - (g10 + g10)) * f23((g11 - g9), Any[g11])) - g10)); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        v37 = max((-5), f12(S5(((-2.34 - g10) <= f23(g9, Any[:b])), get(v28, (true ? g11 : g11), g10), ((g10 >= g10) ? ((-10) <= 9) : ("x 🐛yββ∀0" < "β!1aαb0x 0"))), max(length(v28), ((g10 != 1.96) ? (g9 - 1) : f16(g11, g11, ; kw20 = 9))), f23(g11, Any[g11, g9])))
    end
    push!(v28, (f23(g11, Any[v28]) / g10))
    v39 = Float64[2.2250738585072014e-308 for c38 in 1:4 if ("b🐛 βb1α∀" isa String)]
    v40 = (-0.0, g10)
    global g9 = (abs(g9) + fr26(g9, max(((true || true) ? f16(g11, g9, ; kw19 = 0) : min((-7), 9)), f16(S5(false, 7.86, false), max(10, 0)))))
    v42 = Int64[8 for c41 in 1:4]
    global v40 = (g10, -8.41)
    __obs__(f12(S5(true, -4.77, true), (9 % 7), g10))
    try
        global v39 = [g10, 2.81, g10]
        try; v39[g11] = get(v39, g11, (get(v28, fr26((g11 * g11), length(v42)), (f23(4, Any[v40, 460, v42]) - 1.5)) / ((abs(g11) % 7) * g9))); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        v45 = Int64[(f16((g11 * f16(f12(S5(true, g10, true), g11, -2.5), (g11 + g11), ; kw19 = ((-1) % 1))), (fr26((g9 + 816), (g11 - (-894))) - c44)) * (-1)) for c44 in 1:1]
    catch err43
        __obs__((g11, "∀ba0a !αa"))
    end
    push!(v39, ((string(string(:e, " ∀"), :c) != "1") ? get(v39, abs((-9223372036854775808)), 1.59) : f23((g9 - 8), Any[g10])))
    __obs__("111β∀0yby")
    let l46 = g11, l47 = g10
        v48 = S5(("" != "xβ"), NaN, ((((l46 >= g9) && false) ? get(v39, (g11 + l46), (2.64 + 1.5)) : g10) == min(get(v39, (l46 * (-6)), f23(l46, Any[-9.63, v40, g9])), f23((-755), Any[l47]))))
        v49 = (string(((-6) - ((l46 === (-6)) ? ((-501) % (-1)) : l46)), "xα ") isa Int64)
    end
    v50 = v28
    v52 = Float64[8.77 for c51 in 1:2 if ((try f23(f23(((c51 * 5) + 9), Any[nothing]), Any[v50]) catch __e; (:__thrown, nameof(typeof(__e))) end) isa AbstractString)]
    push!(v52, g10)
    fuel53 = 4
    while (f23((2 - f16(g11, g9, ; kw19 = abs(g11))), Any[v28]) <= f23((min(g11, (g11 + g9)) + (f16(10, g9) - g11)), Any[v52, 702])) && (fuel53 > 0)
        global fuel53 -= 1
        ((f16(g9, (length(v28) * g9), ; kw19 = get(v42, g11, (-1))) >= ((("a1byaβ" == (false ? "a🐛" : "y ")) ? (3 - 5) : 4) - fr26((get(v42, 9, 10) * (g11 - g11)), g9)))) && break
        try; v50[(g9 + (false ? (true ? (f16((-10), g9, ; kw20 = g11) * (10 * g11)) : (g11 * g11)) : f12(S5((1.74 < -1.34), (-8.53 / -9.64), (-0.32 <= -4.61)), (f16(S5(true, 7.32, true), g11) % (-1)), ((g10 < g10) ? 1.99 : abs(g10)))))] = (min(f23((max(g11, 12) + f16(g11, g11, ; kw19 = (-2), kw20 = g11)), Any[g11, :c, g10]), f23(((nothing isa Float64) ? length(v42) : get(v42, g11, g9)), Any[v50, v28, g9])) + f23((length(v42) - (f16(g9, g11) - fr26(9, (-4)))), Any[g11])); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    end
    global v52 = [6.74, g10, g10]
    push!(v52, (true ? g10 : max(g10, ((g10 + g11) * (f23((-7), Any["β🐛1ba0y∀1"]) * f23((-5), Any[g9, v42]))))))
    __obs__(v52)
    __obs__(v50)
    __obs__(v42)
    __obs__(v40)
    __obs__(v39)
    __obs__(v28)
    __obs__(g11)
    __obs__(g10)
    __obs__(g9)
end

```

## Original program

```julia
struct S1
    fld2::Float64
    fld3::Float64
    fld4::Bool
end
struct S5
    fld6::Bool
    fld7::Float64
    fld8::Bool
end
g9 = ((-6) + ((((-10) * ((-958) * 444)) % 3) * (0 - ((true && false) ? (-2) : 1))))
g10 = -5.8
const g11 = ((-3) ÷ (-1))
function f12(a13, a14, a15::Float64)
    __obs__(((a13).fld7 / (a13).fld7))
    return min((((-1) - min(6, abs(g11))) - (((1.5 == a15) ? (g11 - (-6)) : (-8)) * g11)), g9)
end
function f16(a17, a18::Int64; kw19 = 5, kw20 = -4)
    __obs__([a18, a18, kw19])
    return f12(S5(false, g10, true), ((-8) - kw20), g10)
end
function f16(a21::S5, a22::Int64)
    nothing
    return (g11 * (a22 - (-7)))
end
function f23(a24, a25)
    nothing
    return -5.32
end
function fr26(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr26(n - 1, acc + abs(g11))
end
v28 = Float64[-0.0 for c27 in 1:3]
__obs__([g11, (-3)])
__obs__(("0a🐛1ββa" != "🐛y∀x0 "))
try; v28[(f16((g9 + g9), ((g11 + g9) - (10 * length(v28)))) * fr26(5, f12(S5((872 != g11), g10, (g10 isa Any)), f12(S5(false, g10, false), (g9 * g9), (g10 + g10)), g10)))] = g10; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
let
    if ("1bα∀yxaa! " != " ")
        v29 = S5((g10 == (min((g10 + 7.61), f23(10, Any[g11, g9, "!1aaββ"])) / -4.1)), g10, true)
        v30 = S5((g9 != (min(f16((-6), (-769), ; kw19 = g11), f12(S5(true, g10, true), 0, g10)) + (g11 + (-7)))), 9.52, ((-9) isa String))
    else
        let l31 = (max((((0 ÷ 1) - g9) - f16(g9, g11)), (-445)) ÷ 3), l32 = " xy🐛1y0"
            v33 = S1(f23(7, Any["", nothing, g11]), f23(((length(l32) * f16(S5(true, 4.26, true), (-8))) * (f16(l31, l31, ; kw19 = 3, kw20 = g9) * (0 - l31))), Any[nothing, l32, v28]), false)
            if ((!(l32 < ((l32 != l32) ? l32 : (false ? "yβαx🐛aβa" : "")))) && ((v33).fld4 ? ((v33).fld4 && (v33).fld4) : ((f16(g9, 714, ; kw20 = (-5)) * ((-6) * (-10))) isa Integer)))
                if true
                    u34 = f16((((false || true) || ((false ? "y🐛" : "1") isa Float64)) ? f12(S5(false, g10, false), g9, (v33).fld2) : (min(g9, abs((-257))) + 2)), g9, ; kw20 = g9)
                end
                __obs__(@isdefined(u34))
                __obs__(try; u34; catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            v35 = v33
        end
        if (!(true ? ((f12(S5(false, g10, true), (-9), g10) * (10 - g11)) === ((false || false) ? (1 ÷ 7) : (-6))) : (((!false) ? (-6) : fr26((-5), 8)) == f12(S5(false, -5.12, true), (g11 ÷ 2), (true ? g10 : -7.86)))))
            u36 = true
        end
        __obs__(@isdefined(u36))
        __obs__(try; u36; catch __e; (:__undef, nameof(typeof(__e))) end)
        try; v28[(g9 * (2 * g9))] = (get(v28, g11, max(f23(g11, Any[g9, true, g10]), 5.99)) / ((((g10 - g10) - (g10 + g10)) * f23((g11 - g9), Any[g11])) - g10)); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        v37 = max((-5), f12(S5(((-2.34 - g10) <= f23(g9, Any[:b])), get(v28, (true ? g11 : g11), g10), ((g10 >= g10) ? ((-10) <= 9) : ("x 🐛yββ∀0" < "β!1aαb0x 0"))), max(length(v28), ((g10 != 1.96) ? (g9 - 1) : f16(g11, g11, ; kw20 = 9))), f23(g11, Any[g11, g9])))
    end
    push!(v28, (f23(g11, Any[v28]) / g10))
    v39 = Float64[2.2250738585072014e-308 for c38 in 1:4 if ("b🐛 βb1α∀" isa String)]
    v40 = (-0.0, g10)
    global g9 = (abs(g9) + fr26(g9, max(((true || true) ? f16(g11, g9, ; kw19 = 0) : min((-7), 9)), f16(S5(false, 7.86, false), max(10, 0)))))
    v42 = Int64[8 for c41 in 1:4]
    global v40 = (g10, -8.41)
    __obs__(f12(S5(true, -4.77, true), (9 % 7), g10))
    try
        global v39 = [g10, 2.81, g10]
        try; v39[g11] = get(v39, g11, (get(v28, fr26((g11 * g11), length(v42)), (f23(4, Any[v40, 460, v42]) - 1.5)) / ((abs(g11) % 7) * g9))); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        v45 = Int64[(f16((g11 * f16(f12(S5(true, g10, true), g11, -2.5), (g11 + g11), ; kw19 = ((-1) % 1))), (fr26((g9 + 816), (g11 - (-894))) - c44)) * (-1)) for c44 in 1:1]
    catch err43
        __obs__((g11, "∀ba0a !αa"))
    end
    push!(v39, ((string(string(:e, " ∀"), :c) != "1") ? get(v39, abs((-9223372036854775808)), 1.59) : f23((g9 - 8), Any[g10])))
    __obs__("111β∀0yby")
    let l46 = g11, l47 = g10
        v48 = S5(("" != "xβ"), NaN, ((((l46 >= g9) && false) ? get(v39, (g11 + l46), (2.64 + 1.5)) : g10) == min(get(v39, (l46 * (-6)), f23(l46, Any[-9.63, v40, g9])), f23((-755), Any[l47]))))
        v49 = (string(((-6) - ((l46 === (-6)) ? ((-501) % (-1)) : l46)), "xα ") isa Int64)
    end
    v50 = v28
    v52 = Float64[8.77 for c51 in 1:2 if ((try f23(f23(((c51 * 5) + 9), Any[nothing]), Any[v50]) catch __e; (:__thrown, nameof(typeof(__e))) end) isa AbstractString)]
    push!(v52, g10)
    fuel53 = 4
    while (f23((2 - f16(g11, g9, ; kw19 = abs(g11))), Any[v28]) <= f23((min(g11, (g11 + g9)) + (f16(10, g9) - g11)), Any[v52, 702])) && (fuel53 > 0)
        global fuel53 -= 1
        ((f16(g9, (length(v28) * g9), ; kw19 = get(v42, g11, (-1))) >= ((("a1byaβ" == (false ? "a🐛" : "y ")) ? (3 - 5) : 4) - fr26((get(v42, 9, 10) * (g11 - g11)), g9)))) && break
        try; v50[(g9 + (false ? (true ? (f16((-10), g9, ; kw20 = g11) * (10 * g11)) : (g11 * g11)) : f12(S5((1.74 < -1.34), (-8.53 / -9.64), (-0.32 <= -4.61)), (f16(S5(true, 7.32, true), g11) % (-1)), ((g10 < g10) ? 1.99 : abs(g10)))))] = (min(f23((max(g11, 12) + f16(g11, g11, ; kw19 = (-2), kw20 = g11)), Any[g11, :c, g10]), f23(((nothing isa Float64) ? length(v42) : get(v42, g11, g9)), Any[v50, v28, g9])) + f23((length(v42) - (f16(g9, g11) - fr26(9, (-4)))), Any[g11])); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    end
    global v52 = [6.74, g10, g10]
    push!(v52, (true ? g10 : max(g10, ((g10 + g11) * (f23((-7), Any["β🐛1ba0y∀1"]) * f23((-5), Any[g9, v42]))))))
    __obs__(v52)
    __obs__(v50)
    __obs__(v42)
    __obs__(v40)
    __obs__(v39)
    __obs__(v28)
    __obs__(g11)
    __obs__(g10)
    __obs__(g9)
end

```
