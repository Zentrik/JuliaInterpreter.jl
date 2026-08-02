# exception_divergence (exception_divergence-6ad42783)

- seed: `5300038`
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global v19`: v19 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global v19`: v19 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
const g1 = ((((-553) * (-10)) <= (((-1) - (true ? (-896) : (-5))) + ((-3) % (-1)))) ? abs((((4.35 / (-9)) - (6.94 - 0.0)) * (("🐛α0b∀yββb " == "xβy!ββ∀01y") ? 0 : 303))) : (((5.03 - -0.23) - (min(2.220446049250313e-16, 3.55) + 0.0)) + (9.43 - -1.77)))
g2 = (((8.75 / (g1 / (0 ÷ (-1)))) == 5.68) ? ((-1) - 104) : (9 * (((:d === :c) || (!true)) ? 96 : ((0 + 1) + (-6)))))
function fr3(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr3(n - 1, acc + 6)
end
v4 = :a
v5 = (-5.25, v4)
__obs__((try Int8(300) catch __e; (:__thrown, nameof(typeof(__e))) end))
let
    v6 = ((-310), g2)
    let l7 = ((-2.5 - (1.93 - ((g1 / g2) / (g1 / g2)))) - (g1 - g1)), l8 = (max(abs(((true ? g1 : g1) * abs(g1))), abs(g1)) - -0.66)
        try
            local t10::Int64 = fr3(0, 2)
        catch err9
            try
                if ("!b" != "1!b0!0b1")
                    u12 = -Inf
                end
                __obs__(@isdefined(u12))
                __obs__(try; u12; catch __e; (:__undef, nameof(typeof(__e))) end)
                for li13 in 1:2
                    if li13 == 2
                        __obs__(@isdefined(lx14))
                        __obs__(try; (:__v, lx14); catch __e; (:__undef, nameof(typeof(__e))) end)
                    end
                    lx14 = li13
                end
            catch err11
                __obs__(g1)
                ((!(("yx" != string((false ? "α0yxy!!b∀b" : "1🐛🐛yy1!∀🐛"), (true || true))) ? ("🐛01a" == "βax0 ") : (!(-7.75 <= 0.0))))) && rethrow()
            end
            if (l8 isa AbstractString)
                u15 = (((true ? max(max(l8, -Inf), g1) : min(g1, g1)) <= -5.51) ? g2 : g2)
            end
            __obs__(@isdefined(u15))
            __obs__(try; u15; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        __obs__(-3.7)
        v16 = ((-899), true, (-10))
    end
    global g2 = (-10)
    try
        v18 = v4
    catch err17
        err17 = (((g1 >= g1) ? g2 : abs(g2)) != (-6))
    end
    v19 = ((g2 + g2) ÷ 3)
    local t20::Int64 = ((((g1 * (g1 * 0.0)) + ((false || true) ? (3 ÷ 7) : (-5))) >= abs(g1)) ? fr3(1, (max((-8), v19) * (-532))) : v19)
    __obs__((try Core.tuple(1, 2, 3) catch __e; (:__thrown, nameof(typeof(__e))) end))
    for li21 in 1:3
        if li21 == 3
            __obs__(@isdefined(lx22))
            __obs__(try; (:__v, lx22); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx22 = 2.220446049250313e-16
    end
    v23 = g1
    if ((!((("a" != "1a b") ? (false || false) : (false && false)) || true)) || (false || ((string(v4, v4, "β") == "aa!b🐛α") ? (!(true ? false : false)) : ((false || true) && (g1 >= -4.22)))))
        for li24 in 1:3
            if li24 == 3
                __obs__(@isdefined(lx25))
                __obs__(try; (:__v, lx25); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx25 = ((fr3((-1), t20) * fr3((fr3(t20, v19) % (-1)), fr3(t20, t20))) ÷ 1)
        end
        v26 = (0, 1, g2)
    end
    __obs__((fr3(fr3((fr3(g2, v19) - (0 - g2)), abs(g2)), (g2 + t20)) - max(g2, fr3(v19, fr3((g2 - g2), (v19 % 1))))))
    global v6 = v6
    local t27::Float64 = min((g1 * 3.02), (v23 / (((v23 - g2) + -9.1) / ((false ? v23 : g1) / 9.0))))
    try
        global v19 = fr3(((false ? 7 : ((v19 - 9223372036854775807) - t20)) + (-8)), min((((g2 % 2) + (g2 + g2)) * (0 * (g2 ÷ 1))), (((true ? g2 : v19) * ((-9) * (-10))) - max((7 - t20), fr3((-6), g2)))))
        v29 = (:d, v23)
        __obs__(" !1α αb")
    catch err28
        global v6 = v6
        if ("y∀ yβ" isa Integer)
            if (t20 == (-3))
                u30 = v23
            end
            __obs__(@isdefined(u30))
            __obs__(try; u30; catch __e; (:__undef, nameof(typeof(__e))) end)
            __obs__((try fr3((((min(v19, 4) * v19) < fr3((g2 * v19), ((-4) * g2))) ? "0bα" : string("x1β", v4, ((t20 >= 9) ? string(:a, true, v4) : "β"))), (t20 + min((-8), fr3(g2, v19)))) catch __e; (:__thrown, nameof(typeof(__e))) end))
            for i31 in 1:1
                ((i31 === ((true ? fr3(abs(g2), 3) : (fr3(t20, t20) + g2)) - (fr3((-6), v19) - ((-2) + (t20 % 3)))))) && continue
                v34 = ((p32, p33) -> 3.94)
            end
        end
    finally
        __obs__(fr3((fr3((-871), (-60)) - (8 * (((-8) * 8) ÷ 3))), fr3((true ? fr3(fr3(v19, v19), g2) : 469), fr3(min((-3), (t20 + v19)), (max(t20, t20) + max((-6), v19))))))
    end
    for i35 in 1:3
        global v23 = -1.26
        for i36 in 1:4
            for i37 in 1:1
                __obs__((g2, "y🐛y🐛 xαbβ"))
                v38 = Any[(-10), i36, nothing]
            end
            ((((5 * fr3(t20, fr3(9223372036854775806, v19))) * ((-9) * 2)) === i35)) && continue
        end
        if ((v23 >= max(((t27 * v23) * (2.2250738585072014e-308 * -8.72)), ((false ? t27 : -9.38) + (t27 - -9.84)))) || ("🐛0b🐛bx" == "1!!!"))
            (false) && continue
            if (((7.08 <= ((t27 - v23) + (-1))) === (((false && false) && (true isa Float64)) || ((true ? (-4) : t20) < min(g2, (-1))))) || true)
                u39 = fr3(fr3((-5), t20), (((2.51 - (v23 - (-7))) < abs(v23)) ? ((-2) + (v19 - (i35 - v19))) : (((4 * (-444)) - fr3((-7), (-2))) ÷ 1)))
            end
            __obs__(@isdefined(u39))
            __obs__(try; u39; catch __e; (:__undef, nameof(typeof(__e))) end)
        else
            ((((1 * (min(t20, 8) * ((-1) + v19))) >= (10 - (v19 + fr3(v19, t20)))) || ((fr3((-350), g2) > ((t20 % (-3)) - 9223372036854775806)) && false))) && continue
            v40 = v23
            __obs__([t20, v19, v19])
        end
    end
    global v4 = :c
    v41 = :e
    v44 = ((p42, p43) -> (((false || ((-1) === g2)) || ("🐛 1βb10y00" isa Int64)) ? (("yaα01xα" === string("b🐛xβ", v41)) ? string(t20, "00!b🐛!ya") : "α1∀x") : "b1"))
    __obs__((t20 - fr3(fr3((-3), fr3((false ? g2 : v19), (t20 - 9))), (-6))))
    __obs__(string(:e, string(string(v19, (((-2) isa Any) ? string(true, " a ") : string(10, v4, "!b ∀bαbb1a")), "b🐛∀∀"), "!1aa"), t20))
    try
        try
            global t27 = g1
            v49 = ((p47, p48) -> (true ? 8.71 : (g1 - ((v23 + -8.49) / 5.6))))
            try
                local t51::Float64 = (-6.5 - max(t27, 0.09))
            catch err50
                local t52::Float64 = v23
            else
                __obs__([t20])
            end
        catch err46
            __obs__(string(g2, " xxxβaβ1!", v41))
            __obs__(string(fr3(g2, (("∀yy∀" < "!α∀∀") ? g2 : ((false ? g2 : v19) * fr3(v19, t20)))), string(string("b!αy", (abs(v19) * (-511))), (!(0.0 isa AbstractString)), " 1b1"), ((((6 * g2) >= (true ? g2 : (-2))) && (!(true ? true : false))) ? string(v4, v41, (false ? (t20 - t20) : 9223372036854775806)) : "b!")))
            ((!(g2 === abs(((true || true) ? (v19 - g2) : (g2 % 7)))))) && rethrow()
        end
        try
            global t20 = (fr3((-5), (((245 * g2) >= v19) ? fr3((true ? 3 : v19), ((-49) - t20)) : ((-7) * fr3(g2, t20)))) ÷ 3)
            global v6 = (g2, (-2))
            v54 = nothing
        catch err53
            v56 = Int64[abs(max(g2, min(c55, v19))) for c55 in 1:6]
            __obs__(((-962), "ααβ∀α"))
        end
    catch err45
        if false
            v57 = fr3((t20 * g2), (t20 * (-7)))
            v58 = [v19, g2, (-4)]
            v59 = (try fr3(((((9.86 - g2) <= (3.54 - 8.21)) || (t27 <= v23)) || (!(v41 === v4))), (get(v58, fr3((t20 ÷ 1), v19), (((-7) + v19) * (true ? (-8) : v57))) + 9)) catch __e; (:__thrown, nameof(typeof(__e))) end)
        else
            try
                global g2 = g2
            catch err60
                for li61 in 1:2
                    if li61 == 2
                        __obs__(@isdefined(lx62))
                        __obs__(try; (:__v, lx62); catch __e; (:__undef, nameof(typeof(__e))) end)
                    end
                    lx62 = ((t27 + Inf) / (-8))
                end
                (((g2 ÷ (-1)) == (3 + (fr3((-10), g2) - v19)))) && rethrow()
            finally
                if true
                    __obs__([5])
                end
            end
            for li63 in 1:2
                if li63 == 2
                    __obs__(@isdefined(lx64))
                    __obs__(try; (:__v, lx64); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx64 = g1
            end
            try
                v66 = (min((-1), (fr3(v19, g2) - (-10))) * (g2 + 1))
                __obs__([4, 8])
            catch err65
                global v41 = v4
            end
        end
        local t67::Float64 = -8.4
    finally
        v68 = g2
    end
    for i69 in 1:0
        v70 = ((max(min((g1 / -8.66), v23), min(t27, 0.2)) * ((v19 + g2) + fr3((-10), g2))) + t20)
        __obs__((((-8) * 7) >= ((fr3((i69 - (-7)), (false ? t20 : 1)) + fr3(g2, (true ? v19 : t20))) - (("∀0x∀" != "y1") ? 5 : (true ? i69 : (true ? v19 : g2))))))
    end
    if (((t20 - min(g2, fr3(v19, (-220)))) != t20) && (!true))
        v71 = ("y" isa Float64)
    else
        __obs__(string("🐛", ((!(!(t20 === g2))) || ((("!1bα" < " by!∀aβ 00") ? (v19 * v19) : fr3(8, (-7))) >= 6)), string((true ? string(string(false, "🐛αb∀∀αy  b", t20), "1xβ∀α∀xx1") : "b∀αβ"), ((((-6) === g2) && (g2 isa Float64)) || true))))
        global g2 = (abs(((g2 + (4 * (-8))) - g2)) * (-6))
        let l72 = (((!true) || (t20 <= fr3((false ? t20 : v19), (v19 * (-3))))) ? -7.63 : t27), l73 = t27
            for i74 in 1:5
                try
                    v76 = min(8, t20)
                catch err75
                    __obs__([t20, 6, (-525)])
                finally
                    __obs__((g2, ""))
                end
            end
            global v19 = ((fr3(fr3((v19 + v19), v19), abs((v19 - t20))) + g2) - fr3(((g2 * (t20 - (-6))) - v19), v19))
        end
        v77 = v41
    end
    try
        try
            for li80 in 1:2
                if li80 == 2
                    __obs__(@isdefined(lx81))
                    __obs__(try; (:__v, lx81); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx81 = max(t27, (-6.19 + (((!false) ? (true ? -2.5 : 1.7976931348623157e308) : (t27 - t27)) - t27)))
            end
        catch err79
            v82 = -6.21
            ((!true)) && rethrow()
        end
    catch err78
        v83 = [t20]
        if false
            for i84 in 1:1
                if (((get(v83, t20, 3) % (-1)) * max(min(t20, (true ? 768 : v19)), get(v83, i84, (7 + v19)))) > v19)
                    v85 = (" y1🐛 a∀!1" < "yx a0 ")
                end
                if (((((-5.28 * v19) != abs(t27)) && ((v23 * v19) isa Bool)) === ("β1β0aβ🐛" == "🐛1∀!1y !")) && (true && (((t27 >= g1) ? ("1🐛b!xb🐛1α" < "βb  α🐛") : ("" < "")) ? (false === ("x10αβxa🐛x🐛" isa Bool)) : (true && ("b🐛x!y" isa Number)))))
                    u86 = -1.76
                end
                __obs__(@isdefined(u86))
                __obs__(try; u86; catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            v87 = ("α" == "🐛!ya !")
        else
            __obs__(g1)
            __obs__(((t27 - -4.91) / -4.91))
        end
        (false) && rethrow()
    finally
        v88 = t20
    end
    global v4 = :a
    __obs__((try v44(0, 0.0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v41)
    __obs__(t27)
    __obs__(v23)
    __obs__(t20)
    __obs__(v19)
    __obs__(v6)
    __obs__(v5)
    __obs__(v4)
    __obs__(g2)
    __obs__(g1)
end

```

## Original program

```julia
const g1 = ((((-553) * (-10)) <= (((-1) - (true ? (-896) : (-5))) + ((-3) % (-1)))) ? abs((((4.35 / (-9)) - (6.94 - 0.0)) * (("🐛α0b∀yββb " == "xβy!ββ∀01y") ? 0 : 303))) : (((5.03 - -0.23) - (min(2.220446049250313e-16, 3.55) + 0.0)) + (9.43 - -1.77)))
g2 = (((8.75 / (g1 / (0 ÷ (-1)))) == 5.68) ? ((-1) - 104) : (9 * (((:d === :c) || (!true)) ? 96 : ((0 + 1) + (-6)))))
function fr3(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr3(n - 1, acc + 6)
end
v4 = :a
v5 = (-5.25, v4)
__obs__((try Int8(300) catch __e; (:__thrown, nameof(typeof(__e))) end))
let
    v6 = ((-310), g2)
    let l7 = ((-2.5 - (1.93 - ((g1 / g2) / (g1 / g2)))) - (g1 - g1)), l8 = (max(abs(((true ? g1 : g1) * abs(g1))), abs(g1)) - -0.66)
        try
            local t10::Int64 = fr3(0, 2)
        catch err9
            try
                if ("!b" != "1!b0!0b1")
                    u12 = -Inf
                end
                __obs__(@isdefined(u12))
                __obs__(try; u12; catch __e; (:__undef, nameof(typeof(__e))) end)
                for li13 in 1:2
                    if li13 == 2
                        __obs__(@isdefined(lx14))
                        __obs__(try; (:__v, lx14); catch __e; (:__undef, nameof(typeof(__e))) end)
                    end
                    lx14 = li13
                end
            catch err11
                __obs__(g1)
                ((!(("yx" != string((false ? "α0yxy!!b∀b" : "1🐛🐛yy1!∀🐛"), (true || true))) ? ("🐛01a" == "βax0 ") : (!(-7.75 <= 0.0))))) && rethrow()
            end
            if (l8 isa AbstractString)
                u15 = (((true ? max(max(l8, -Inf), g1) : min(g1, g1)) <= -5.51) ? g2 : g2)
            end
            __obs__(@isdefined(u15))
            __obs__(try; u15; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        __obs__(-3.7)
        v16 = ((-899), true, (-10))
    end
    global g2 = (-10)
    try
        v18 = v4
    catch err17
        err17 = (((g1 >= g1) ? g2 : abs(g2)) != (-6))
    end
    v19 = ((g2 + g2) ÷ 3)
    local t20::Int64 = ((((g1 * (g1 * 0.0)) + ((false || true) ? (3 ÷ 7) : (-5))) >= abs(g1)) ? fr3(1, (max((-8), v19) * (-532))) : v19)
    __obs__((try Core.tuple(1, 2, 3) catch __e; (:__thrown, nameof(typeof(__e))) end))
    for li21 in 1:3
        if li21 == 3
            __obs__(@isdefined(lx22))
            __obs__(try; (:__v, lx22); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx22 = 2.220446049250313e-16
    end
    v23 = g1
    if ((!((("a" != "1a b") ? (false || false) : (false && false)) || true)) || (false || ((string(v4, v4, "β") == "aa!b🐛α") ? (!(true ? false : false)) : ((false || true) && (g1 >= -4.22)))))
        for li24 in 1:3
            if li24 == 3
                __obs__(@isdefined(lx25))
                __obs__(try; (:__v, lx25); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx25 = ((fr3((-1), t20) * fr3((fr3(t20, v19) % (-1)), fr3(t20, t20))) ÷ 1)
        end
        v26 = (0, 1, g2)
    end
    __obs__((fr3(fr3((fr3(g2, v19) - (0 - g2)), abs(g2)), (g2 + t20)) - max(g2, fr3(v19, fr3((g2 - g2), (v19 % 1))))))
    global v6 = v6
    local t27::Float64 = min((g1 * 3.02), (v23 / (((v23 - g2) + -9.1) / ((false ? v23 : g1) / 9.0))))
    try
        global v19 = fr3(((false ? 7 : ((v19 - 9223372036854775807) - t20)) + (-8)), min((((g2 % 2) + (g2 + g2)) * (0 * (g2 ÷ 1))), (((true ? g2 : v19) * ((-9) * (-10))) - max((7 - t20), fr3((-6), g2)))))
        v29 = (:d, v23)
        __obs__(" !1α αb")
    catch err28
        global v6 = v6
        if ("y∀ yβ" isa Integer)
            if (t20 == (-3))
                u30 = v23
            end
            __obs__(@isdefined(u30))
            __obs__(try; u30; catch __e; (:__undef, nameof(typeof(__e))) end)
            __obs__((try fr3((((min(v19, 4) * v19) < fr3((g2 * v19), ((-4) * g2))) ? "0bα" : string("x1β", v4, ((t20 >= 9) ? string(:a, true, v4) : "β"))), (t20 + min((-8), fr3(g2, v19)))) catch __e; (:__thrown, nameof(typeof(__e))) end))
            for i31 in 1:1
                ((i31 === ((true ? fr3(abs(g2), 3) : (fr3(t20, t20) + g2)) - (fr3((-6), v19) - ((-2) + (t20 % 3)))))) && continue
                v34 = ((p32, p33) -> 3.94)
            end
        end
    finally
        __obs__(fr3((fr3((-871), (-60)) - (8 * (((-8) * 8) ÷ 3))), fr3((true ? fr3(fr3(v19, v19), g2) : 469), fr3(min((-3), (t20 + v19)), (max(t20, t20) + max((-6), v19))))))
    end
    for i35 in 1:3
        global v23 = -1.26
        for i36 in 1:4
            for i37 in 1:1
                __obs__((g2, "y🐛y🐛 xαbβ"))
                v38 = Any[(-10), i36, nothing]
            end
            ((((5 * fr3(t20, fr3(9223372036854775806, v19))) * ((-9) * 2)) === i35)) && continue
        end
        if ((v23 >= max(((t27 * v23) * (2.2250738585072014e-308 * -8.72)), ((false ? t27 : -9.38) + (t27 - -9.84)))) || ("🐛0b🐛bx" == "1!!!"))
            (false) && continue
            if (((7.08 <= ((t27 - v23) + (-1))) === (((false && false) && (true isa Float64)) || ((true ? (-4) : t20) < min(g2, (-1))))) || true)
                u39 = fr3(fr3((-5), t20), (((2.51 - (v23 - (-7))) < abs(v23)) ? ((-2) + (v19 - (i35 - v19))) : (((4 * (-444)) - fr3((-7), (-2))) ÷ 1)))
            end
            __obs__(@isdefined(u39))
            __obs__(try; u39; catch __e; (:__undef, nameof(typeof(__e))) end)
        else
            ((((1 * (min(t20, 8) * ((-1) + v19))) >= (10 - (v19 + fr3(v19, t20)))) || ((fr3((-350), g2) > ((t20 % (-3)) - 9223372036854775806)) && false))) && continue
            v40 = v23
            __obs__([t20, v19, v19])
        end
    end
    global v4 = :c
    v41 = :e
    v44 = ((p42, p43) -> (((false || ((-1) === g2)) || ("🐛 1βb10y00" isa Int64)) ? (("yaα01xα" === string("b🐛xβ", v41)) ? string(t20, "00!b🐛!ya") : "α1∀x") : "b1"))
    __obs__((t20 - fr3(fr3((-3), fr3((false ? g2 : v19), (t20 - 9))), (-6))))
    __obs__(string(:e, string(string(v19, (((-2) isa Any) ? string(true, " a ") : string(10, v4, "!b ∀bαbb1a")), "b🐛∀∀"), "!1aa"), t20))
    try
        try
            global t27 = g1
            v49 = ((p47, p48) -> (true ? 8.71 : (g1 - ((v23 + -8.49) / 5.6))))
            try
                local t51::Float64 = (-6.5 - max(t27, 0.09))
            catch err50
                local t52::Float64 = v23
            else
                __obs__([t20])
            end
        catch err46
            __obs__(string(g2, " xxxβaβ1!", v41))
            __obs__(string(fr3(g2, (("∀yy∀" < "!α∀∀") ? g2 : ((false ? g2 : v19) * fr3(v19, t20)))), string(string("b!αy", (abs(v19) * (-511))), (!(0.0 isa AbstractString)), " 1b1"), ((((6 * g2) >= (true ? g2 : (-2))) && (!(true ? true : false))) ? string(v4, v41, (false ? (t20 - t20) : 9223372036854775806)) : "b!")))
            ((!(g2 === abs(((true || true) ? (v19 - g2) : (g2 % 7)))))) && rethrow()
        end
        try
            global t20 = (fr3((-5), (((245 * g2) >= v19) ? fr3((true ? 3 : v19), ((-49) - t20)) : ((-7) * fr3(g2, t20)))) ÷ 3)
            global v6 = (g2, (-2))
            v54 = nothing
        catch err53
            v56 = Int64[abs(max(g2, min(c55, v19))) for c55 in 1:6]
            __obs__(((-962), "ααβ∀α"))
        end
    catch err45
        if false
            v57 = fr3((t20 * g2), (t20 * (-7)))
            v58 = [v19, g2, (-4)]
            v59 = (try fr3(((((9.86 - g2) <= (3.54 - 8.21)) || (t27 <= v23)) || (!(v41 === v4))), (get(v58, fr3((t20 ÷ 1), v19), (((-7) + v19) * (true ? (-8) : v57))) + 9)) catch __e; (:__thrown, nameof(typeof(__e))) end)
        else
            try
                global g2 = g2
            catch err60
                for li61 in 1:2
                    if li61 == 2
                        __obs__(@isdefined(lx62))
                        __obs__(try; (:__v, lx62); catch __e; (:__undef, nameof(typeof(__e))) end)
                    end
                    lx62 = ((t27 + Inf) / (-8))
                end
                (((g2 ÷ (-1)) == (3 + (fr3((-10), g2) - v19)))) && rethrow()
            finally
                if true
                    __obs__([5])
                end
            end
            for li63 in 1:2
                if li63 == 2
                    __obs__(@isdefined(lx64))
                    __obs__(try; (:__v, lx64); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx64 = g1
            end
            try
                v66 = (min((-1), (fr3(v19, g2) - (-10))) * (g2 + 1))
                __obs__([4, 8])
            catch err65
                global v41 = v4
            end
        end
        local t67::Float64 = -8.4
    finally
        v68 = g2
    end
    for i69 in 1:0
        v70 = ((max(min((g1 / -8.66), v23), min(t27, 0.2)) * ((v19 + g2) + fr3((-10), g2))) + t20)
        __obs__((((-8) * 7) >= ((fr3((i69 - (-7)), (false ? t20 : 1)) + fr3(g2, (true ? v19 : t20))) - (("∀0x∀" != "y1") ? 5 : (true ? i69 : (true ? v19 : g2))))))
    end
    if (((t20 - min(g2, fr3(v19, (-220)))) != t20) && (!true))
        v71 = ("y" isa Float64)
    else
        __obs__(string("🐛", ((!(!(t20 === g2))) || ((("!1bα" < " by!∀aβ 00") ? (v19 * v19) : fr3(8, (-7))) >= 6)), string((true ? string(string(false, "🐛αb∀∀αy  b", t20), "1xβ∀α∀xx1") : "b∀αβ"), ((((-6) === g2) && (g2 isa Float64)) || true))))
        global g2 = (abs(((g2 + (4 * (-8))) - g2)) * (-6))
        let l72 = (((!true) || (t20 <= fr3((false ? t20 : v19), (v19 * (-3))))) ? -7.63 : t27), l73 = t27
            for i74 in 1:5
                try
                    v76 = min(8, t20)
                catch err75
                    __obs__([t20, 6, (-525)])
                finally
                    __obs__((g2, ""))
                end
            end
            global v19 = ((fr3(fr3((v19 + v19), v19), abs((v19 - t20))) + g2) - fr3(((g2 * (t20 - (-6))) - v19), v19))
        end
        v77 = v41
    end
    try
        try
            for li80 in 1:2
                if li80 == 2
                    __obs__(@isdefined(lx81))
                    __obs__(try; (:__v, lx81); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx81 = max(t27, (-6.19 + (((!false) ? (true ? -2.5 : 1.7976931348623157e308) : (t27 - t27)) - t27)))
            end
        catch err79
            v82 = -6.21
            ((!true)) && rethrow()
        end
    catch err78
        v83 = [t20]
        if false
            for i84 in 1:1
                if (((get(v83, t20, 3) % (-1)) * max(min(t20, (true ? 768 : v19)), get(v83, i84, (7 + v19)))) > v19)
                    v85 = (" y1🐛 a∀!1" < "yx a0 ")
                end
                if (((((-5.28 * v19) != abs(t27)) && ((v23 * v19) isa Bool)) === ("β1β0aβ🐛" == "🐛1∀!1y !")) && (true && (((t27 >= g1) ? ("1🐛b!xb🐛1α" < "βb  α🐛") : ("" < "")) ? (false === ("x10αβxa🐛x🐛" isa Bool)) : (true && ("b🐛x!y" isa Number)))))
                    u86 = -1.76
                end
                __obs__(@isdefined(u86))
                __obs__(try; u86; catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            v87 = ("α" == "🐛!ya !")
        else
            __obs__(g1)
            __obs__(((t27 - -4.91) / -4.91))
        end
        (false) && rethrow()
    finally
        v88 = t20
    end
    global v4 = :a
    __obs__((try v44(0, 0.0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v41)
    __obs__(t27)
    __obs__(v23)
    __obs__(t20)
    __obs__(v19)
    __obs__(v6)
    __obs__(v5)
    __obs__(v4)
    __obs__(g2)
    __obs__(g1)
end

```
