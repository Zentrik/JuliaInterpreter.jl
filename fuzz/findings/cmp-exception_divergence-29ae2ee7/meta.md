# exception_divergence (cmp-exception_divergence-29ae2ee7)

- seed: `1200048`
- interp mode: `cmp`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel34`: fuel34 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel34`: fuel34 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
function f1()
    v2 = :c
    v3 = 3.83
    return [4, 206]
end
function f4(a5::Tuple, va6...; kw7 = 3)
    for i8 in 1:2
        i8 = kw7
        (((((-7.66 < -3.27) ? (false && true) : (!true)) ? true : ((true || true) && (!false))) || ((try (kw7 % kw7) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Number))) && continue
    end
    try
        for i10 in 1:1
            v12 = Float64[(((("0β🐛" isa Number) ? (-3.19 - kw7) : (4.4 * 3.79)) * 0.2) + 6.79) for c11 in 1:1 if (((6 isa Number) ? "aα 1β" : string("∀!", "1a!1")) == (true ? "!aα" : string(string(:c, i10), :d)))]
            try; v12[(i10 + (min((kw7 - 1), (true ? (-6) : i10)) * ((kw7 % (-1)) - (-1))))] = (-5.56 / (get(v12, max(kw7, 6), abs(1.36)) + ((5 + i10) * kw7))); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        end
        __obs__(f1())
        __obs__(((((6 + (-504)) - (3 ÷ 2)) != ((-3.11 >= -7.12) ? (-6) : (-9))) ? (-5.84 / 6.31) : 1.5))
    catch err9
        v13 = ((9223372036854775807 - (9 + (kw7 - kw7))) - kw7)
        kw7 = (true ? 3 : (true ? ((0 === v13) ? (v13 - 186) : abs(v13)) : (kw7 ÷ (-1))))
    finally
        if (min(-4.71, 3.03) isa Any)
            __obs__("b∀")
        else
            fuel14 = 4
            while (kw7 != (abs((false ? 5 : 0)) * (-7))) && (fuel14 > 0)
                fuel14 -= 1
                ((((true ? kw7 : kw7) == ((-Inf < -9.36) ? 1 : 6)) || (string(:a, "🐛a") == string(:b, "")))) && continue
            end
        end
    end
    fuel15 = 1
    while (!((((-5) + 1) - ((-10) - kw7)) <= kw7)) && (fuel15 > 0)
        fuel15 -= 1
        v16 = :c
        (((-1) < (true ? kw7 : kw7))) && continue
    end
    return 7.3
end
try
    __obs__((0, ""))
    v18 = nothing
catch err17
    __obs__((-4.75 - f4(((-2), :a, :e))))
end
__obs__(:b)
v19 = (try (519 ÷ 7) catch __e; (:__thrown, nameof(typeof(__e))) end)
let
    if (0.71 <= max(((6.87 / 4.65) * (-8.63 + 0.65)), min(0.1, (0.83 / -4.55))))
        let l20 = (f4((2, :e, :b)) / ((-4) ÷ (-3))), l21 = ((((-10) % 7) * (2 % 1)) + 8)
            v22 = (((((-4) * l21) < l21) ? "🐛x " : " 1🐛!") < "! axya")
            __obs__((l21 + l21))
        end
    end
    try
        try
            try
                v26 = (((-8) * (-5)) * ((((-3) - 8) + (-5)) + 626))
            catch err25
                v27 = nothing
            finally
                v28 = (true, :e)
            end
        catch err24
            __obs__(((f4(((-6), :a, :c)) != min((false ? 1.17 : 7.89), (-6.11 + 683))) || true))
            try
                v30 = ((!((-8) === 509)) || (((9.63 <= -1.26) || (true && false)) && ((false || true) ? ("" == "") : (9.89 isa Bool))))
            catch err29
                __obs__(string(" ", (((" 🐛aβy" isa AbstractString) || true) ? (5 === (0 - (-821))) : ((try Core.replacefield!(Ref(1), :x, 1, 9) catch __e; (:__thrown, nameof(typeof(__e))) end) isa String)), "0"))
            end
            (((-981) < 8)) && rethrow()
        end
        if true
            u31 = "αα0β11"
        end
        __obs__(@isdefined(u31))
        __obs__(try; u31; catch __e; (:__undef, nameof(typeof(__e))) end)
        global v19 = -1.81
    catch err23
        err23 = f4((5, :d, :d))
        err23 = :e
    end
    v33 = ((p32) -> "ax0")
    __obs__("bx")
    __obs__((7, "x"))
    fuel34 = 1
    while ("α" != "00") && (fuel34 > 0)
        global fuel34 -= 1
        v33 = ((p35) -> (("x∀" != string("", "")) ? string(:e, string(:a, :b, true)) : string((true || true), (!false))))
        try
            v37 = f1()
            __obs__("α!α!")
        catch err36
            __obs__((0, "!0"))
            for i38 in 1:1
                v39 = 0.0
            end
        end
    end
    try
        v41 = -8.84
        __obs__(((!(:e === :a)) ? (try first(Core.modifyfield!(Ref(2), :x, +, 5)) catch __e; (:__thrown, nameof(typeof(__e))) end) : f1()))
    catch err40
        let l42 = :c
            if (false || (((-8.0 / 4.93) < -9.33) ? ((2 isa Number) && (false && true)) : (8 <= 8)))
                u43 = (-10)
            end
            __obs__(@isdefined(u43))
            __obs__(try; u43; catch __e; (:__undef, nameof(typeof(__e))) end)
            try
                if ((false ? (-2) : (((-5) * 8) - (false ? 5 : 7))) > (4 * (-6)))
                    u45 = 1
                end
                __obs__(@isdefined(u45))
                __obs__(try; u45; catch __e; (:__undef, nameof(typeof(__e))) end)
            catch err44
                v46 = (f4(((-10), l42, :d)) + (((:e === l42) ? 0.0 : 1.46) - (f4(((-9), l42, l42), ; kw7 = (-7)) * 3.22)))
                __obs__((8, ""))
            end
        end
        (((10 ÷ 7) != ((-982) * (-54)))) && rethrow()
    end
    try
        v48 = f4((1, :a, :e))
    catch err47
        v49 = Any[:a]
        for i50 in 1:0
            v51 = 0.1
        end
    else
        __obs__([0])
    end
    global v19 = :e
    fuel52 = 1
    while ((true isa Number) && false) && (fuel52 > 0)
        global fuel52 -= 1
        __obs__(1.5)
        let l53 = "yα1", l54 = :a
            if (l53 < l53)
                v55 = (((8.84 != (3.14 * 1.5)) || ("" === (false ? l53 : ""))) || (!true))
            end
            if (((!(3.23 isa Integer)) ? l53 : ((2 <= 4) ? string(l53, l53, "") : l53)) == string(((false || false) ? "βb" : string(8, l53, l53)), l53, :b))
                u56 = ((max(((-2) * 1), 7) + length(l53)) - (-650))
            end
            __obs__(@isdefined(u56))
            __obs__(try; u56; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
    end
    for i57 in 1:4
        i57 = ((-246) * (-7))
        global v19 = (("1a1α" != string("01!0🐛y", string("y0!bb", "11b1a∀"), "∀🐛01 ")) ? 6.51 : f4((i57, :d, :c), ((:c === :e) ? -1.17 : -7.48), (true ? ("00α00!" == " ") : false)))
    end
    __obs__((try v33(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v19)
end

```

## Original program

```julia
function f1()
    v2 = :c
    v3 = 3.83
    return [4, 206]
end
function f4(a5::Tuple, va6...; kw7 = 3)
    for i8 in 1:2
        i8 = kw7
        (((((-7.66 < -3.27) ? (false && true) : (!true)) ? true : ((true || true) && (!false))) || ((try (kw7 % kw7) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Number))) && continue
    end
    try
        for i10 in 1:1
            v12 = Float64[(((("0β🐛" isa Number) ? (-3.19 - kw7) : (4.4 * 3.79)) * 0.2) + 6.79) for c11 in 1:1 if (((6 isa Number) ? "aα 1β" : string("∀!", "1a!1")) == (true ? "!aα" : string(string(:c, i10), :d)))]
            try; v12[(i10 + (min((kw7 - 1), (true ? (-6) : i10)) * ((kw7 % (-1)) - (-1))))] = (-5.56 / (get(v12, max(kw7, 6), abs(1.36)) + ((5 + i10) * kw7))); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        end
        __obs__(f1())
        __obs__(((((6 + (-504)) - (3 ÷ 2)) != ((-3.11 >= -7.12) ? (-6) : (-9))) ? (-5.84 / 6.31) : 1.5))
    catch err9
        v13 = ((9223372036854775807 - (9 + (kw7 - kw7))) - kw7)
        kw7 = (true ? 3 : (true ? ((0 === v13) ? (v13 - 186) : abs(v13)) : (kw7 ÷ (-1))))
    finally
        if (min(-4.71, 3.03) isa Any)
            __obs__("b∀")
        else
            fuel14 = 4
            while (kw7 != (abs((false ? 5 : 0)) * (-7))) && (fuel14 > 0)
                fuel14 -= 1
                ((((true ? kw7 : kw7) == ((-Inf < -9.36) ? 1 : 6)) || (string(:a, "🐛a") == string(:b, "")))) && continue
            end
        end
    end
    fuel15 = 1
    while (!((((-5) + 1) - ((-10) - kw7)) <= kw7)) && (fuel15 > 0)
        fuel15 -= 1
        v16 = :c
        (((-1) < (true ? kw7 : kw7))) && continue
    end
    return 7.3
end
try
    __obs__((0, ""))
    v18 = nothing
catch err17
    __obs__((-4.75 - f4(((-2), :a, :e))))
end
__obs__(:b)
v19 = (try (519 ÷ 7) catch __e; (:__thrown, nameof(typeof(__e))) end)
let
    if (0.71 <= max(((6.87 / 4.65) * (-8.63 + 0.65)), min(0.1, (0.83 / -4.55))))
        let l20 = (f4((2, :e, :b)) / ((-4) ÷ (-3))), l21 = ((((-10) % 7) * (2 % 1)) + 8)
            v22 = (((((-4) * l21) < l21) ? "🐛x " : " 1🐛!") < "! axya")
            __obs__((l21 + l21))
        end
    end
    try
        try
            try
                v26 = (((-8) * (-5)) * ((((-3) - 8) + (-5)) + 626))
            catch err25
                v27 = nothing
            finally
                v28 = (true, :e)
            end
        catch err24
            __obs__(((f4(((-6), :a, :c)) != min((false ? 1.17 : 7.89), (-6.11 + 683))) || true))
            try
                v30 = ((!((-8) === 509)) || (((9.63 <= -1.26) || (true && false)) && ((false || true) ? ("" == "") : (9.89 isa Bool))))
            catch err29
                __obs__(string(" ", (((" 🐛aβy" isa AbstractString) || true) ? (5 === (0 - (-821))) : ((try Core.replacefield!(Ref(1), :x, 1, 9) catch __e; (:__thrown, nameof(typeof(__e))) end) isa String)), "0"))
            end
            (((-981) < 8)) && rethrow()
        end
        if true
            u31 = "αα0β11"
        end
        __obs__(@isdefined(u31))
        __obs__(try; u31; catch __e; (:__undef, nameof(typeof(__e))) end)
        global v19 = -1.81
    catch err23
        err23 = f4((5, :d, :d))
        err23 = :e
    end
    v33 = ((p32) -> "ax0")
    __obs__("bx")
    __obs__((7, "x"))
    fuel34 = 1
    while ("α" != "00") && (fuel34 > 0)
        global fuel34 -= 1
        v33 = ((p35) -> (("x∀" != string("", "")) ? string(:e, string(:a, :b, true)) : string((true || true), (!false))))
        try
            v37 = f1()
            __obs__("α!α!")
        catch err36
            __obs__((0, "!0"))
            for i38 in 1:1
                v39 = 0.0
            end
        end
    end
    try
        v41 = -8.84
        __obs__(((!(:e === :a)) ? (try first(Core.modifyfield!(Ref(2), :x, +, 5)) catch __e; (:__thrown, nameof(typeof(__e))) end) : f1()))
    catch err40
        let l42 = :c
            if (false || (((-8.0 / 4.93) < -9.33) ? ((2 isa Number) && (false && true)) : (8 <= 8)))
                u43 = (-10)
            end
            __obs__(@isdefined(u43))
            __obs__(try; u43; catch __e; (:__undef, nameof(typeof(__e))) end)
            try
                if ((false ? (-2) : (((-5) * 8) - (false ? 5 : 7))) > (4 * (-6)))
                    u45 = 1
                end
                __obs__(@isdefined(u45))
                __obs__(try; u45; catch __e; (:__undef, nameof(typeof(__e))) end)
            catch err44
                v46 = (f4(((-10), l42, :d)) + (((:e === l42) ? 0.0 : 1.46) - (f4(((-9), l42, l42), ; kw7 = (-7)) * 3.22)))
                __obs__((8, ""))
            end
        end
        (((10 ÷ 7) != ((-982) * (-54)))) && rethrow()
    end
    try
        v48 = f4((1, :a, :e))
    catch err47
        v49 = Any[:a]
        for i50 in 1:0
            v51 = 0.1
        end
    else
        __obs__([0])
    end
    global v19 = :e
    fuel52 = 1
    while ((true isa Number) && false) && (fuel52 > 0)
        global fuel52 -= 1
        __obs__(1.5)
        let l53 = "yα1", l54 = :a
            if (l53 < l53)
                v55 = (((8.84 != (3.14 * 1.5)) || ("" === (false ? l53 : ""))) || (!true))
            end
            if (((!(3.23 isa Integer)) ? l53 : ((2 <= 4) ? string(l53, l53, "") : l53)) == string(((false || false) ? "βb" : string(8, l53, l53)), l53, :b))
                u56 = ((max(((-2) * 1), 7) + length(l53)) - (-650))
            end
            __obs__(@isdefined(u56))
            __obs__(try; u56; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
    end
    for i57 in 1:4
        i57 = ((-246) * (-7))
        global v19 = (("1a1α" != string("01!0🐛y", string("y0!bb", "11b1a∀"), "∀🐛01 ")) ? 6.51 : f4((i57, :d, :c), ((:c === :e) ? -1.17 : -7.48), (true ? ("00α00!" == " ") : false)))
    end
    __obs__((try v33(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v19)
end

```
