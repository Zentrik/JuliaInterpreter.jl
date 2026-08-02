# exception_divergence (cmp-exception_divergence-4a0f73f2)

- seed: `5300023`
- interp mode: `cmp`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global v15`: v15 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global v15`: v15 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
g1 = ((992 ÷ 7) + (true ? (3 * 897) : abs((-6))))
function f2()
    nothing
    return (try ((g1 + 7) % 1) catch __e; (:__thrown, nameof(typeof(__e))) end)
end
v3 = "xyα∀🐛a1ax"
v4 = ((f2() isa Number) ? "α" : string(((0.1 <= -5.32) ? g1 : (("1ay🐛🐛0α" == v3) ? (g1 ÷ 7) : 437)), v3))
try
    __obs__((g1, v4))
catch err5
    v6 = (g1, 0.13)
end
v8 = ((p7) -> (p7 - (true ? p7 : ((nothing isa Integer) ? p7 : (p7 / -9.75)))))
g1 = 5
let
    for li9 in 1:2
        if li9 == 2
            __obs__(@isdefined(lx10))
            __obs__(try; (:__v, lx10); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx10 = (g1 * (((false || (v3 != v3)) ? (true ? min(g1, li9) : (false ? li9 : (-6))) : (li9 + (li9 * (-6)))) * (("αx" isa AbstractString) ? min(3, (false ? (-1) : g1)) : (-6))))
    end
    v11 = v8(9.34)
    __obs__((((((false || true) ? (0 < g1) : ("x🐛0β βα🐛" == "")) && ((-8) == g1)) && (((7 + g1) + (true ? g1 : g1)) <= (-6))) ? string(v3, string((g1 isa String), length(v4), "ayβ0b ")) : v4))
    v12 = :b
    local t13::Int64 = 2
    v14 = (v4 < string(false, v4, t13))
    v15 = Any[v4, v12, false]
    try
        fuel17 = 3
        while v14 && (fuel17 > 0)
            fuel17 -= 1
            __obs__([(-10)])
            global v15 = Any["∀ xy🐛∀βββx", nothing, g1]
        end
        let l18 = ((-4) * (-5)), l19 = :e
            __obs__(v11)
        end
    catch err16
        v20 = v15
    end
    let l21 = (min(((!(v14 || v14)) ? (g1 % (-3)) : ((-8) + g1)), g1) * t13), l22 = v3
        v23 = [9.77]
        __obs__(abs(get(v23, 8, (((-9.61 - 7.77) + 544) + v11))))
        __obs__([g1, 3])
    end
    global v4 = string("b", ((((t13 - 2) == t13) ? (g1 + (v14 ? g1 : 0)) : g1) <= (((t13 ÷ 1) + (t13 - 9223372036854775807)) % (-1))), ((g1 != (8 * (t13 * 10))) ? (!(((-3) >= t13) ? (v14 || true) : (7.94 isa Int64))) : (!((-3) == (t13 + g1)))))
    local t24::Int64 = t13
    for i25 in 1:0
        __obs__(v11)
        v26 = v3
        v27 = ((((-1) * (i25 + (g1 + g1))) + (t24 % 2)) > (((!(8.82 >= v11)) || (v14 && (v11 > v11))) ? (((v14 ? true : false) && (v14 ? v14 : v14)) ? ((t13 + g1) % (-3)) : (-5)) : (8 * (t24 + (true ? (-1) : (-8))))))
    end
    v28 = (((v14 ? t13 : t24) < g1) ? ((min((true ? t13 : g1), (v14 ? (-7) : t24)) - (t24 % 2)) - (-10)) : (t24 * min(t13, t13)))
    try
        v31 = Int64[t13 for c30 in 1:4 if (string(length(v3), v4) === (((-288) == 8) ? "αβy" : v4))]
    catch err29
        try; v15[min((g1 - t13), (v28 + (length(v4) - ((v28 * t24) + (v14 ? 10 : v28)))))] = ((length(v3) + g1) * g1); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        __obs__((g1, v3))
    finally
        let l32 = 1, l33 = -7.84
            v34 = v14
        end
    end
    __obs__(v28)
    __obs__(t24)
    __obs__(v15)
    __obs__(v14)
    __obs__(t13)
    __obs__(v12)
    __obs__(v11)
    __obs__((try v8(0.0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v4)
    __obs__(v3)
    __obs__(g1)
end

```

## Original program

```julia
g1 = ((992 ÷ 7) + (true ? (3 * 897) : abs((-6))))
function f2()
    nothing
    return (try ((g1 + 7) % 1) catch __e; (:__thrown, nameof(typeof(__e))) end)
end
v3 = "xyα∀🐛a1ax"
v4 = ((f2() isa Number) ? "α" : string(((0.1 <= -5.32) ? g1 : (("1ay🐛🐛0α" == v3) ? (g1 ÷ 7) : 437)), v3))
try
    __obs__((g1, v4))
catch err5
    v6 = (g1, 0.13)
end
v8 = ((p7) -> (p7 - (true ? p7 : ((nothing isa Integer) ? p7 : (p7 / -9.75)))))
g1 = 5
let
    for li9 in 1:2
        if li9 == 2
            __obs__(@isdefined(lx10))
            __obs__(try; (:__v, lx10); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx10 = (g1 * (((false || (v3 != v3)) ? (true ? min(g1, li9) : (false ? li9 : (-6))) : (li9 + (li9 * (-6)))) * (("αx" isa AbstractString) ? min(3, (false ? (-1) : g1)) : (-6))))
    end
    v11 = v8(9.34)
    __obs__((((((false || true) ? (0 < g1) : ("x🐛0β βα🐛" == "")) && ((-8) == g1)) && (((7 + g1) + (true ? g1 : g1)) <= (-6))) ? string(v3, string((g1 isa String), length(v4), "ayβ0b ")) : v4))
    v12 = :b
    local t13::Int64 = 2
    v14 = (v4 < string(false, v4, t13))
    v15 = Any[v4, v12, false]
    try
        fuel17 = 3
        while v14 && (fuel17 > 0)
            fuel17 -= 1
            __obs__([(-10)])
            global v15 = Any["∀ xy🐛∀βββx", nothing, g1]
        end
        let l18 = ((-4) * (-5)), l19 = :e
            __obs__(v11)
        end
    catch err16
        v20 = v15
    end
    let l21 = (min(((!(v14 || v14)) ? (g1 % (-3)) : ((-8) + g1)), g1) * t13), l22 = v3
        v23 = [9.77]
        __obs__(abs(get(v23, 8, (((-9.61 - 7.77) + 544) + v11))))
        __obs__([g1, 3])
    end
    global v4 = string("b", ((((t13 - 2) == t13) ? (g1 + (v14 ? g1 : 0)) : g1) <= (((t13 ÷ 1) + (t13 - 9223372036854775807)) % (-1))), ((g1 != (8 * (t13 * 10))) ? (!(((-3) >= t13) ? (v14 || true) : (7.94 isa Int64))) : (!((-3) == (t13 + g1)))))
    local t24::Int64 = t13
    for i25 in 1:0
        __obs__(v11)
        v26 = v3
        v27 = ((((-1) * (i25 + (g1 + g1))) + (t24 % 2)) > (((!(8.82 >= v11)) || (v14 && (v11 > v11))) ? (((v14 ? true : false) && (v14 ? v14 : v14)) ? ((t13 + g1) % (-3)) : (-5)) : (8 * (t24 + (true ? (-1) : (-8))))))
    end
    v28 = (((v14 ? t13 : t24) < g1) ? ((min((true ? t13 : g1), (v14 ? (-7) : t24)) - (t24 % 2)) - (-10)) : (t24 * min(t13, t13)))
    try
        v31 = Int64[t13 for c30 in 1:4 if (string(length(v3), v4) === (((-288) == 8) ? "αβy" : v4))]
    catch err29
        try; v15[min((g1 - t13), (v28 + (length(v4) - ((v28 * t24) + (v14 ? 10 : v28)))))] = ((length(v3) + g1) * g1); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        __obs__((g1, v3))
    finally
        let l32 = 1, l33 = -7.84
            v34 = v14
        end
    end
    __obs__(v28)
    __obs__(t24)
    __obs__(v15)
    __obs__(v14)
    __obs__(t13)
    __obs__(v12)
    __obs__(v11)
    __obs__((try v8(0.0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v4)
    __obs__(v3)
    __obs__(g1)
end

```
