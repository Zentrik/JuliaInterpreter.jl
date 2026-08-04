# value_divergence (value_divergence-64876489)

- seed: `1785779695100401397`
- interp mode: `rec`
- julia: `1.12.6`
- divergent observation index: 10
- ref exception: `none`  interp exception: `none`

## Detail

```
obs[10]: ref=(:__thrown, :ErrorException) interp=(9, -100)
```

## Shrunk program

```julia
function f1(a2, a3)
    v4 = 663
    fuel5 = 1
    while (true && (((6 != v4) ? string(true, "  1xβx") : string(false, :d)) < "1")) && (fuel5 > 0)
        fuel5 -= 1
        ((a3 < a3)) && break
        v6 = (7.85 >= (1.69 * (-3.97 + 3.23)))
        v7 = (:a, "🐛by", v4)
    end
    return Any[a2, a2, :c]
end
function f8(a9::Bool, a10, a11 = 0)
    __obs__(9223372036854775807)
    v12 = Any["∀y∀", a10]
    return min(a11, (a11 - min((a9 ? a11 : a11), (false ? a11 : a11))))
end
if (" b∀0" == string(((-302) + ((-9) + 1)), string(:e, "ba∀β", false), 411))
    u13 = :c
end
__obs__(@isdefined(u13))
__obs__(try; u13; catch __e; (:__undef, nameof(typeof(__e))) end)
__obs__(" 0")
let
    v14 = (-10)
    v15 = (abs(abs((8.38 - -0.53))) * (((true ? -7.46 : -0.0) + -8.34) / v14))
    let l16 = v14
        local t17::Float64 = ((((true || true) ? v14 : (v14 * (-4))) < (f8(false, :b, l16) % (-1))) ? (((v15 * v15) != (9.18 + 919)) ? v15 : ((v15 + 9.0) + -9.94)) : v15)
    end
    if ((((:a === :d) ? v14 : (v14 * v14)) <= (-8)) ? true : (((v14 isa Int64) ? (-0.91 + v14) : -6.87) <= (2.28 / f8(false, :a, v14))))
        v18 = (v14 * (-9))
        v18 = (v14 - v18)
        v14 = v18
    end
    let l19 = :c, l20 = :e
        __obs__(string((max((true ? (-5) : v14), (false ? v14 : (-798))) < ((-10) ÷ 7)), string(string(string("1yxx", false), l19), (true ? (false ? "bb" : "") : (false ? "1" : "a🐛∀"))), 6))
        if ("ya" == string(l19, ((!true) ? v14 : (-9))))
            u21 = (false ? v14 : v14)
        end
        __obs__(@isdefined(u21))
        __obs__(try; u21; catch __e; (:__undef, nameof(typeof(__e))) end)
    end
    v22 = ((((true ? "∀🐛aαx " : "b") == "y") ? ((true ? -0.21 : -2.0) - v15) : abs(v15)) - (-2.8 + v14))
    __obs__(:d)
    v23 = (9, v14)
    __obs__((try Core.compilerbarrier(Base.compilerbarrier(:const, :b), Base.compilerbarrier(:const, v23)) catch __e; (:__thrown, nameof(typeof(__e))) end))
    v23 = v23
    __obs__("")
    v24 = :d
    v14 = v14
    __obs__(v24)
    __obs__(v23)
    __obs__(v22)
    __obs__(v15)
    __obs__(v14)
end

```

## Original program

```julia
function f1(a2, a3)
    v4 = 663
    fuel5 = 1
    while (true && (((6 != v4) ? string(true, "  1xβx") : string(false, :d)) < "1")) && (fuel5 > 0)
        fuel5 -= 1
        ((a3 < a3)) && break
        v6 = (7.85 >= (1.69 * (-3.97 + 3.23)))
        v7 = (:a, "🐛by", v4)
    end
    return Any[a2, a2, :c]
end
function f8(a9::Bool, a10, a11 = 0)
    __obs__(9223372036854775807)
    v12 = Any["∀y∀", a10]
    return min(a11, (a11 - min((a9 ? a11 : a11), (false ? a11 : a11))))
end
if (" b∀0" == string(((-302) + ((-9) + 1)), string(:e, "ba∀β", false), 411))
    u13 = :c
end
__obs__(@isdefined(u13))
__obs__(try; u13; catch __e; (:__undef, nameof(typeof(__e))) end)
__obs__(" 0")
let
    v14 = (-10)
    v15 = (abs(abs((8.38 - -0.53))) * (((true ? -7.46 : -0.0) + -8.34) / v14))
    let l16 = v14
        local t17::Float64 = ((((true || true) ? v14 : (v14 * (-4))) < (f8(false, :b, l16) % (-1))) ? (((v15 * v15) != (9.18 + 919)) ? v15 : ((v15 + 9.0) + -9.94)) : v15)
    end
    if ((((:a === :d) ? v14 : (v14 * v14)) <= (-8)) ? true : (((v14 isa Int64) ? (-0.91 + v14) : -6.87) <= (2.28 / f8(false, :a, v14))))
        v18 = (v14 * (-9))
        v18 = (v14 - v18)
        v14 = v18
    end
    let l19 = :c, l20 = :e
        __obs__(string((max((true ? (-5) : v14), (false ? v14 : (-798))) < ((-10) ÷ 7)), string(string(string("1yxx", false), l19), (true ? (false ? "bb" : "") : (false ? "1" : "a🐛∀"))), 6))
        if ("ya" == string(l19, ((!true) ? v14 : (-9))))
            u21 = (false ? v14 : v14)
        end
        __obs__(@isdefined(u21))
        __obs__(try; u21; catch __e; (:__undef, nameof(typeof(__e))) end)
    end
    v22 = ((((true ? "∀🐛aαx " : "b") == "y") ? ((true ? -0.21 : -2.0) - v15) : abs(v15)) - (-2.8 + v14))
    __obs__(:d)
    v23 = (9, v14)
    __obs__((try Core.compilerbarrier(Base.compilerbarrier(:const, :b), Base.compilerbarrier(:const, v23)) catch __e; (:__thrown, nameof(typeof(__e))) end))
    v23 = v23
    __obs__("")
    v24 = :d
    v14 = v14
    __obs__(v24)
    __obs__(v23)
    __obs__(v22)
    __obs__(v15)
    __obs__(v14)
end

```
