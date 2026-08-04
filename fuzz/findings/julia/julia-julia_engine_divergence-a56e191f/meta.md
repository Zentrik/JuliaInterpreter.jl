# julia_engine_divergence (julia-julia_engine_divergence-a56e191f)

- seed: `1400128`
- interp mode: `rec`
- julia: `1.12.6`
- divergent observation index: 2
- ref exception: `none`  interp exception: `none`

## Detail

```
obs[2]: ref=(:__thrown, :ErrorException) interp=(:__thrown, :ConcurrencyViolationError)
```

## Shrunk program

```julia
const __RNG__ = Xoshiro(53178887)
function f1()
    if false
        v2 = ((6.15 - ((-8) * min((-2), (-6)))) * min((rand(__RNG__, Bool) ? (2.71 - -1.11) : (-6.7 + 3.89)), 4.72))
        ((!((try (0 % max((-9), 795)) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Any))) && return "!bx"
    else
        v3 = (!(rand(__RNG__, 1:5) < (-7)))
        try
            local t5::Int64 = (((rand(__RNG__, Bool) ? (2.2250738585072014e-308 + -Inf) : (3.71 / -0.0)) isa Float64) ? (-8) : (((7 - (-2)) + 1) + rand(__RNG__, Int)))
        catch err4
            err4 = abs(3.2)
            __obs__(((((5 - (-8)) * (v3 ? (-10) : 7)) != ((!true) ? (-82) : 10)) ? abs(rand(__RNG__)) : -4.88))
        end
        v8 = ((p6, p7) -> "αxα🐛")
    end
    __obs__([(-5), 5])
    try
        v11 = ((p10) -> string("🐛1∀ 1 ", "!! y"))
        v11 = ((p12) -> "!1 11")
    catch err9
        v13 = :d
        (((true ? ((false ? 6.36 : Inf) != 9.47) : ((true || true) || (false || false))) || rand(__RNG__, Bool))) && return ((3 > ((-2) % 7)) ? "  x1" : (false ? "" : string(:d, string(2, false))))
    else
        v14 = 5.54
    end
    return ((((10 < 9) || false) || ((2.2250738585072014e-308 + 8.53) == 9.31)) ? (true ? "  x" : ((!true) ? string(:d, (-1)) : string((-4), true))) : string(6, :b, (((-1) - (-9)) + 2)))
end
function f15(a16, a17::Bool, a18::Int64)
    ((a18 <= a18)) && return ((p19) -> (a16 <= (a16 / (a16 * 1.7976931348623157e308))))
    return ((p20) -> string(f1(), p20, (a18 + (a18 - (-10)))))
end
let
    v21 = -0.57
    v22 = f1()
    local t23::Float64 = (rand(__RNG__) + abs(randn(__RNG__)))
    try
        v25 = (((try (v22)[(-2)] catch __e; (:__thrown, nameof(typeof(__e))) end) isa Bool) || ((v21 <= (t23 + 1.5)) || ((2 isa Any) === (!true))))
        __obs__((try Base.atomic_fence(:unordered) catch __e; (:__thrown, nameof(typeof(__e))) end))
    catch err24
        v22 = string("y", f1(), :c)
        (((((1 + (-5)) != (-6)) ? t23 : abs((v21 / (-10)))) < max(((true && true) ? t23 : 6.39), ((t23 + 4.77) * (t23 + -4.96))))) && rethrow()
    end
    try
        __obs__(((-6), v22))
        fuel27 = 1
        while true && (fuel27 > 0)
            fuel27 -= 1
            (((abs((true ? 10 : 5)) % (-1)) == 2)) && break
        end
    catch err26
        v28 = (2 * (min(((-727) - (-2)), (6 + (-7))) * (__vtime__() - rand(__RNG__, 1:4))))
        v29 = Any[nothing, true, :e]
    end
    __obs__(f1())
    v22 = f1()
    v30 = Any[true, 3]
    try
        try
            try
                v21 = 0.7
            catch err33
                err33 = :b
            end
            __obs__((try f15((v22 < v22), (((true ? t23 : -2.5) - (8 - 0)) isa Number), (-508)) catch __e; (:__thrown, nameof(typeof(__e))) end))
        catch err32
            for li34 in 1:3
                if li34 == 3
                    __obs__(@isdefined(lx35))
                    __obs__(try; (:__v, lx35); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx35 = (((!(true && false)) && false) ? (((v21 / v21) + -2.5) - li34) : ((:c === :b) ? randn(__RNG__) : ((true || true) ? 7.07 : max(t23, t23))))
            end
            v36 = (-8)
        else
            t23 = (rand(__RNG__) + min(((true ? false : false) ? t23 : 6.28), (randn(__RNG__) + (3 ÷ 7))))
        finally
            local t37::Int64 = ((!true) ? (-121) : 0)
        end
        try
            fuel39 = 3
            while (rand(__RNG__, Bool) ? (((false ? 0 : (-8)) < (true ? 4 : 1)) || ((false isa String) && true)) : ((((-984) * (-10)) - 9223372036854775807) isa Float64)) && (fuel39 > 0)
                fuel39 -= 1
                try; v30[abs(((v21 >= (v21 * 8.49)) ? length(v30) : 9))] = -7.67; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
            end
            if true
                u40 = rand(__RNG__, Int)
            end
            __obs__(@isdefined(u40))
            __obs__(try; u40; catch __e; (:__undef, nameof(typeof(__e))) end)
        catch err38
            v41 = v21
        else
            local t42::Int64 = (-485)
        end
        fuel43 = 2
        while (string(9223372036854775807, (-10), v22) != f1()) && (fuel43 > 0)
            fuel43 -= 1
            v21 = v21
        end
    catch err31
        if ((string((true ? v22 : v22), (!true), (2.89 != v21)) != string(string(v22, "x", true), true)) === rand(__RNG__, Bool))
            u44 = 8
        end
        __obs__(@isdefined(u44))
        __obs__(try; u44; catch __e; (:__undef, nameof(typeof(__e))) end)
        v45 = ("0ba∀α ", -0.0)
        (false) && rethrow()
    end
    try; v30[1] = 357; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    fuel46 = 2
    while ((t23 != -4.01) === (((true || false) ? false : (v22 < "βb0αy")) && (!true))) && (fuel46 > 0)
        fuel46 -= 1
        (((rand(__RNG__, Bool) || (v22 === (true ? v22 : v22))) ? (!true) : (!(("" == "ayybb1") ? (true === false) : (true isa Number))))) && continue
        fuel47 = 3
        while (false || ((v21 + (1.7976931348623157e308 - 2.0)) != 0.0)) && (fuel47 > 0)
            fuel47 -= 1
            if (9 < (length(v30) ÷ 2))
                u48 = (5 % 3)
            end
            __obs__(@isdefined(u48))
            __obs__(try; u48; catch __e; (:__undef, nameof(typeof(__e))) end)
            try
                __obs__(:b)
            catch err49
                try; v30[(__vtime__() * rand(__RNG__, 1:2))] = v22; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
                v50 = f15(v21, (((true ? false : true) && (false && true)) || ((247 < 2) && (" b" == "🐛"))), length(v22))
            else
                t23 = -0.0
            end
        end
    end
    try
        v52 = (-808)
        v53 = v52
    catch err51
        try; v30[(-8)] = (((try (10 ÷ 2) catch __e; (:__thrown, nameof(typeof(__e))) end) isa String) ? ((v21 - 6) == ((t23 + t23) + -4.67)) : ((-10) isa Integer)); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        al54 = v30
    else
        if ("yy∀" isa Int64)
            u55 = (((8.91 >= (3.13 * 4.2)) ? rand(__RNG__, 1:8) : ((true ? (-4) : 6) - rand(__RNG__, 1:3))) < (((497 * 9223372036854775806) - 8) + (-4)))
        end
        __obs__(@isdefined(u55))
        __obs__(try; u55; catch __e; (:__undef, nameof(typeof(__e))) end)
    end
    if ((abs(-Inf) / ((true ? 2.9 : -3.99) * randn(__RNG__))) < (false ? ((-2.14 + t23) / t23) : -4.5))
        __obs__(((((2 + (-2)) > (false ? 401 : 2)) || ("!b!β" != v22)) ? 1 : (2 * (-7))))
    else
        __obs__((false && true))
        try
            if ((!true) && (!(f1() isa Any)))
                u57 = f1()
            end
            __obs__(@isdefined(u57))
            __obs__(try; u57; catch __e; (:__undef, nameof(typeof(__e))) end)
            __obs__(:d)
        catch err56
            __obs__((4, v22))
        end
    end
    __obs__(v30)
    __obs__(t23)
    __obs__(v22)
    __obs__(v21)
end

```

## Original program

```julia
const __RNG__ = Xoshiro(53178887)
function f1()
    if false
        v2 = ((6.15 - ((-8) * min((-2), (-6)))) * min((rand(__RNG__, Bool) ? (2.71 - -1.11) : (-6.7 + 3.89)), 4.72))
        ((!((try (0 % max((-9), 795)) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Any))) && return "!bx"
    else
        v3 = (!(rand(__RNG__, 1:5) < (-7)))
        try
            local t5::Int64 = (((rand(__RNG__, Bool) ? (2.2250738585072014e-308 + -Inf) : (3.71 / -0.0)) isa Float64) ? (-8) : (((7 - (-2)) + 1) + rand(__RNG__, Int)))
        catch err4
            err4 = abs(3.2)
            __obs__(((((5 - (-8)) * (v3 ? (-10) : 7)) != ((!true) ? (-82) : 10)) ? abs(rand(__RNG__)) : -4.88))
        end
        v8 = ((p6, p7) -> "αxα🐛")
    end
    __obs__([(-5), 5])
    try
        v11 = ((p10) -> string("🐛1∀ 1 ", "!! y"))
        v11 = ((p12) -> "!1 11")
    catch err9
        v13 = :d
        (((true ? ((false ? 6.36 : Inf) != 9.47) : ((true || true) || (false || false))) || rand(__RNG__, Bool))) && return ((3 > ((-2) % 7)) ? "  x1" : (false ? "" : string(:d, string(2, false))))
    else
        v14 = 5.54
    end
    return ((((10 < 9) || false) || ((2.2250738585072014e-308 + 8.53) == 9.31)) ? (true ? "  x" : ((!true) ? string(:d, (-1)) : string((-4), true))) : string(6, :b, (((-1) - (-9)) + 2)))
end
function f15(a16, a17::Bool, a18::Int64)
    ((a18 <= a18)) && return ((p19) -> (a16 <= (a16 / (a16 * 1.7976931348623157e308))))
    return ((p20) -> string(f1(), p20, (a18 + (a18 - (-10)))))
end
let
    v21 = -0.57
    v22 = f1()
    local t23::Float64 = (rand(__RNG__) + abs(randn(__RNG__)))
    try
        v25 = (((try (v22)[(-2)] catch __e; (:__thrown, nameof(typeof(__e))) end) isa Bool) || ((v21 <= (t23 + 1.5)) || ((2 isa Any) === (!true))))
        __obs__((try Base.atomic_fence(:unordered) catch __e; (:__thrown, nameof(typeof(__e))) end))
    catch err24
        v22 = string("y", f1(), :c)
        (((((1 + (-5)) != (-6)) ? t23 : abs((v21 / (-10)))) < max(((true && true) ? t23 : 6.39), ((t23 + 4.77) * (t23 + -4.96))))) && rethrow()
    end
    try
        __obs__(((-6), v22))
        fuel27 = 1
        while true && (fuel27 > 0)
            fuel27 -= 1
            (((abs((true ? 10 : 5)) % (-1)) == 2)) && break
        end
    catch err26
        v28 = (2 * (min(((-727) - (-2)), (6 + (-7))) * (__vtime__() - rand(__RNG__, 1:4))))
        v29 = Any[nothing, true, :e]
    end
    __obs__(f1())
    v22 = f1()
    v30 = Any[true, 3]
    try
        try
            try
                v21 = 0.7
            catch err33
                err33 = :b
            end
            __obs__((try f15((v22 < v22), (((true ? t23 : -2.5) - (8 - 0)) isa Number), (-508)) catch __e; (:__thrown, nameof(typeof(__e))) end))
        catch err32
            for li34 in 1:3
                if li34 == 3
                    __obs__(@isdefined(lx35))
                    __obs__(try; (:__v, lx35); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx35 = (((!(true && false)) && false) ? (((v21 / v21) + -2.5) - li34) : ((:c === :b) ? randn(__RNG__) : ((true || true) ? 7.07 : max(t23, t23))))
            end
            v36 = (-8)
        else
            t23 = (rand(__RNG__) + min(((true ? false : false) ? t23 : 6.28), (randn(__RNG__) + (3 ÷ 7))))
        finally
            local t37::Int64 = ((!true) ? (-121) : 0)
        end
        try
            fuel39 = 3
            while (rand(__RNG__, Bool) ? (((false ? 0 : (-8)) < (true ? 4 : 1)) || ((false isa String) && true)) : ((((-984) * (-10)) - 9223372036854775807) isa Float64)) && (fuel39 > 0)
                fuel39 -= 1
                try; v30[abs(((v21 >= (v21 * 8.49)) ? length(v30) : 9))] = -7.67; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
            end
            if true
                u40 = rand(__RNG__, Int)
            end
            __obs__(@isdefined(u40))
            __obs__(try; u40; catch __e; (:__undef, nameof(typeof(__e))) end)
        catch err38
            v41 = v21
        else
            local t42::Int64 = (-485)
        end
        fuel43 = 2
        while (string(9223372036854775807, (-10), v22) != f1()) && (fuel43 > 0)
            fuel43 -= 1
            v21 = v21
        end
    catch err31
        if ((string((true ? v22 : v22), (!true), (2.89 != v21)) != string(string(v22, "x", true), true)) === rand(__RNG__, Bool))
            u44 = 8
        end
        __obs__(@isdefined(u44))
        __obs__(try; u44; catch __e; (:__undef, nameof(typeof(__e))) end)
        v45 = ("0ba∀α ", -0.0)
        (false) && rethrow()
    end
    try; v30[1] = 357; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    fuel46 = 2
    while ((t23 != -4.01) === (((true || false) ? false : (v22 < "βb0αy")) && (!true))) && (fuel46 > 0)
        fuel46 -= 1
        (((rand(__RNG__, Bool) || (v22 === (true ? v22 : v22))) ? (!true) : (!(("" == "ayybb1") ? (true === false) : (true isa Number))))) && continue
        fuel47 = 3
        while (false || ((v21 + (1.7976931348623157e308 - 2.0)) != 0.0)) && (fuel47 > 0)
            fuel47 -= 1
            if (9 < (length(v30) ÷ 2))
                u48 = (5 % 3)
            end
            __obs__(@isdefined(u48))
            __obs__(try; u48; catch __e; (:__undef, nameof(typeof(__e))) end)
            try
                __obs__(:b)
            catch err49
                try; v30[(__vtime__() * rand(__RNG__, 1:2))] = v22; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
                v50 = f15(v21, (((true ? false : true) && (false && true)) || ((247 < 2) && (" b" == "🐛"))), length(v22))
            else
                t23 = -0.0
            end
        end
    end
    try
        v52 = (-808)
        v53 = v52
    catch err51
        try; v30[(-8)] = (((try (10 ÷ 2) catch __e; (:__thrown, nameof(typeof(__e))) end) isa String) ? ((v21 - 6) == ((t23 + t23) + -4.67)) : ((-10) isa Integer)); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        al54 = v30
    else
        if ("yy∀" isa Int64)
            u55 = (((8.91 >= (3.13 * 4.2)) ? rand(__RNG__, 1:8) : ((true ? (-4) : 6) - rand(__RNG__, 1:3))) < (((497 * 9223372036854775806) - 8) + (-4)))
        end
        __obs__(@isdefined(u55))
        __obs__(try; u55; catch __e; (:__undef, nameof(typeof(__e))) end)
    end
    if ((abs(-Inf) / ((true ? 2.9 : -3.99) * randn(__RNG__))) < (false ? ((-2.14 + t23) / t23) : -4.5))
        __obs__(((((2 + (-2)) > (false ? 401 : 2)) || ("!b!β" != v22)) ? 1 : (2 * (-7))))
    else
        __obs__((false && true))
        try
            if ((!true) && (!(f1() isa Any)))
                u57 = f1()
            end
            __obs__(@isdefined(u57))
            __obs__(try; u57; catch __e; (:__undef, nameof(typeof(__e))) end)
            __obs__(:d)
        catch err56
            __obs__((4, v22))
        end
    end
    __obs__(v30)
    __obs__(t23)
    __obs__(v22)
    __obs__(v21)
end

```
