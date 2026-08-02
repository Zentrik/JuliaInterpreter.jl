# exception_divergence (exception_divergence-3c42f60a)

- seed: `1200040`
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel32`: fuel32 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel32`: fuel32 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
g1 = ""
g2 = ((((false ? -8.56 : -9.67) / (3 - 3)) / -3.43) - abs((-0.0 * (-8))))
g3 = ((!((g1 < "x!βb0") && (true && false))) ? (g2 / (-10)) : 4.47)
function f4(a5::Float64, a6, a7::Int64 = 0)
    if (g2 <= a6)
        u8 = ((a7 < ((5 * a7) * a7)) ? ((("α!yβy" < g1) isa Integer) ? g1 : string(false, g1, string(:a, g1, :b))) : "∀00∀")
    end
    __obs__(@isdefined(u8))
    __obs__(try; u8; catch __e; (:__undef, nameof(typeof(__e))) end)
    try
        __obs__([9])
        fuel10 = 2
        while (:e === :d) && (fuel10 > 0)
            fuel10 -= 1
            v11 = ((length(g1) > 6) && (-7.17 > (-7.43 * a6)))
            v13 = Float64[-0.0 for c12 in 1:1 if (("" isa Number) && (string(v11, string(c12, g1, c12), g1) < g1))]
        end
        try
            __obs__((a7, g1))
        catch err14
            ((a7 === (((a5 < 2.2250738585072014e-308) === (!true)) ? (a7 * (5 * a7)) : 5))) && return (g3 / (((a7 isa Bool) || (g2 >= 0.0)) ? (abs(a5) - (g3 * -1.69)) : (7.33 / g3)))
            ((:c === :d)) && rethrow()
        finally
            global g3 = a5
        end
    catch err9
        a6 = 6.78
        v15 = "y0🐛"
    else
        v17 = Float64[a5 for c16 in 1:2]
    end
    return ((((true ? -2.5 : a6) * (g2 * 1.5)) + a6) + -3.76)
end
if (((7 - ((-5) * (-6))) + 10) == (((4 * 8) isa Bool) ? length(g1) : 10))
    local t18::Int64 = (((!(!false)) ? (-9) : 3) - (-9))
    t18 = ((!true) ? length(g1) : t18)
end
__obs__([(-5), (-7)])
let
    v19 = (((-1) < (((-8) ÷ (-3)) + (-397))) ? (try f4(g1, f4(max(g2, g2), f4(g3, g3, (-10)), ((-480) + (-1))), 9) catch __e; (:__thrown, nameof(typeof(__e))) end) : "1 🐛🐛β")
    for i20 in 1:2
        (true) && break
    end
    v21 = 9.05
    if (!((7 === abs(926)) && (string(g1, 0) isa String)))
        for i22 in 1:2
            __obs__(g1)
        end
        v23 = (g2 / min(((true isa AbstractString) ? (g2 + 4.42) : (g3 + 0.1)), v21))
        try
            v19 = ("" isa Bool)
        catch err24
            v25 = ((-9), v21, g1)
        end
    else
        v19 = :d
        v26 = f4(f4(g2, f4((true ? g3 : 2.16), f4(v21, 8.55, 0), abs((-3))), 5), 1.92, (2 % 1))
        local t27::Float64 = max(max(min(g3, (-1.4 / -4.85)), abs((v21 * -2.47))), -7.89)
    end
    for i28 in 1:3
        for i29 in 1:1
            v31 = Float64[g3 for c30 in 1:0 if true]
        end
        __obs__((try (g1)[i28] catch __e; (:__thrown, nameof(typeof(__e))) end))
        __obs__(v21)
    end
    fuel32 = 2
    while (8 >= (-3)) && (fuel32 > 0)
        global fuel32 -= 1
        v34 = Float64[(7.76 * max(f4(-2.5, (v21 - v21), (false ? (-9) : c33)), g3)) for c33 in 1:3 if (!(:a === :e))]
        global g3 = g3
        ((((false ? 3 : 10) === ((-8) + (-10))) || (((true ? g2 : g3) - 3) < g3))) && break
    end
    v19 = (true || (((" α∀" != "α!") || ("α∀" < "y1x")) && false))
    for i35 in 1:0
        for i36 in 1:3
            v37 = length(g1)
            v38 = (((((-311) * v37) % (-3)) - (v37 * 5)) + 10)
        end
        if ((((!false) ? (!false) : false) ? (i35 * (false ? 2 : i35)) : 0) <= (i35 + ((false ? i35 : i35) - 7)))
            u39 = :e
        end
        __obs__(@isdefined(u39))
        __obs__(try; u39; catch __e; (:__undef, nameof(typeof(__e))) end)
    end
    if (7 == 1)
        u40 = (5 >= (-8))
    end
    __obs__(@isdefined(u40))
    __obs__(try; u40; catch __e; (:__undef, nameof(typeof(__e))) end)
    global g2 = NaN
    __obs__(v21)
    __obs__(v19)
    __obs__(g3)
    __obs__(g2)
    __obs__(g1)
end

```

## Original program

```julia
g1 = ""
g2 = ((((false ? -8.56 : -9.67) / (3 - 3)) / -3.43) - abs((-0.0 * (-8))))
g3 = ((!((g1 < "x!βb0") && (true && false))) ? (g2 / (-10)) : 4.47)
function f4(a5::Float64, a6, a7::Int64 = 0)
    if (g2 <= a6)
        u8 = ((a7 < ((5 * a7) * a7)) ? ((("α!yβy" < g1) isa Integer) ? g1 : string(false, g1, string(:a, g1, :b))) : "∀00∀")
    end
    __obs__(@isdefined(u8))
    __obs__(try; u8; catch __e; (:__undef, nameof(typeof(__e))) end)
    try
        __obs__([9])
        fuel10 = 2
        while (:e === :d) && (fuel10 > 0)
            fuel10 -= 1
            v11 = ((length(g1) > 6) && (-7.17 > (-7.43 * a6)))
            v13 = Float64[-0.0 for c12 in 1:1 if (("" isa Number) && (string(v11, string(c12, g1, c12), g1) < g1))]
        end
        try
            __obs__((a7, g1))
        catch err14
            ((a7 === (((a5 < 2.2250738585072014e-308) === (!true)) ? (a7 * (5 * a7)) : 5))) && return (g3 / (((a7 isa Bool) || (g2 >= 0.0)) ? (abs(a5) - (g3 * -1.69)) : (7.33 / g3)))
            ((:c === :d)) && rethrow()
        finally
            global g3 = a5
        end
    catch err9
        a6 = 6.78
        v15 = "y0🐛"
    else
        v17 = Float64[a5 for c16 in 1:2]
    end
    return ((((true ? -2.5 : a6) * (g2 * 1.5)) + a6) + -3.76)
end
if (((7 - ((-5) * (-6))) + 10) == (((4 * 8) isa Bool) ? length(g1) : 10))
    local t18::Int64 = (((!(!false)) ? (-9) : 3) - (-9))
    t18 = ((!true) ? length(g1) : t18)
end
__obs__([(-5), (-7)])
let
    v19 = (((-1) < (((-8) ÷ (-3)) + (-397))) ? (try f4(g1, f4(max(g2, g2), f4(g3, g3, (-10)), ((-480) + (-1))), 9) catch __e; (:__thrown, nameof(typeof(__e))) end) : "1 🐛🐛β")
    for i20 in 1:2
        (true) && break
    end
    v21 = 9.05
    if (!((7 === abs(926)) && (string(g1, 0) isa String)))
        for i22 in 1:2
            __obs__(g1)
        end
        v23 = (g2 / min(((true isa AbstractString) ? (g2 + 4.42) : (g3 + 0.1)), v21))
        try
            v19 = ("" isa Bool)
        catch err24
            v25 = ((-9), v21, g1)
        end
    else
        v19 = :d
        v26 = f4(f4(g2, f4((true ? g3 : 2.16), f4(v21, 8.55, 0), abs((-3))), 5), 1.92, (2 % 1))
        local t27::Float64 = max(max(min(g3, (-1.4 / -4.85)), abs((v21 * -2.47))), -7.89)
    end
    for i28 in 1:3
        for i29 in 1:1
            v31 = Float64[g3 for c30 in 1:0 if true]
        end
        __obs__((try (g1)[i28] catch __e; (:__thrown, nameof(typeof(__e))) end))
        __obs__(v21)
    end
    fuel32 = 2
    while (8 >= (-3)) && (fuel32 > 0)
        global fuel32 -= 1
        v34 = Float64[(7.76 * max(f4(-2.5, (v21 - v21), (false ? (-9) : c33)), g3)) for c33 in 1:3 if (!(:a === :e))]
        global g3 = g3
        ((((false ? 3 : 10) === ((-8) + (-10))) || (((true ? g2 : g3) - 3) < g3))) && break
    end
    v19 = (true || (((" α∀" != "α!") || ("α∀" < "y1x")) && false))
    for i35 in 1:0
        for i36 in 1:3
            v37 = length(g1)
            v38 = (((((-311) * v37) % (-3)) - (v37 * 5)) + 10)
        end
        if ((((!false) ? (!false) : false) ? (i35 * (false ? 2 : i35)) : 0) <= (i35 + ((false ? i35 : i35) - 7)))
            u39 = :e
        end
        __obs__(@isdefined(u39))
        __obs__(try; u39; catch __e; (:__undef, nameof(typeof(__e))) end)
    end
    if (7 == 1)
        u40 = (5 >= (-8))
    end
    __obs__(@isdefined(u40))
    __obs__(try; u40; catch __e; (:__undef, nameof(typeof(__e))) end)
    global g2 = NaN
    __obs__(v21)
    __obs__(v19)
    __obs__(g3)
    __obs__(g2)
    __obs__(g1)
end

```
