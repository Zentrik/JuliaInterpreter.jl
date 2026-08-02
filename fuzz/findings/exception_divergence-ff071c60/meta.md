# exception_divergence (exception_divergence-ff071c60)

- seed: `5300145`
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel44`: fuel44 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel44`: fuel44 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
g1 = (-7.92 / (((((-1) < 5) ? 0.1 : -0.0) + ((0.1 / 3) / (-1.35 + 9.01))) / 8))
global g2::Int64 = (-524)
global g3::Int64 = (-614)
g4 = :c
g5 = g1
function fr6(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr6(n - 1, acc + ((3 * (-630)) + g2))
end
function fr7(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr7(n - 1, acc + g3)
end
function fr7(a8::String, a9::Int64)
    nothing
    return false
end
function f10(a11::Int64)
    fuel12 = 4
    while (("" isa Integer) || (!(((g3 isa String) ? (10 * (-2)) : g3) < a11))) && (fuel12 > 0)
        fuel12 -= 1
        v14 = Float64[((-9.06 + ((-7) - (-5))) / (((-9.44 * (4.82 / g5)) == (g5 / g1)) ? (-9) : g3)) for c13 in 1:2]
        push!(v14, 7.61)
        push!(v14, g1)
        fuel15 = 2
        while ((get(v14, g3, abs((g5 + g2))) / (-1)) == (get(v14, (965 * fr6((-3), g3)), ((false ? g5 : g1) - g2)) - (get(v14, min(g3, g2), 9.02) * -6.49))) && (fuel15 > 0)
            fuel15 -= 1
            v16 = g4
            __obs__(a11)
            __obs__([g2])
        end
    end
    __obs__(((fr6(((!true) ? (false ? g2 : a11) : g3), 7) + (fr6(min(g3, 9), max(g2, (-10))) % 1)) % (-3)))
    for i17 in 1:5
        v18 = (g2 isa Number)
        __obs__((-3.35 * 7.22))
    end
    return string((((("0xαbb∀b0∀x" == "α🐛α") && ("aα" == "αaααβaβyα")) === ((g2 ÷ 7) > (true ? g3 : 10))) ? "ay ∀🐛xx!!y" : "!α🐛0x0β"), (true === (((3.54 + g1) + (g3 - g3)) >= ((!false) ? (true ? g1 : g5) : max(g5, g1)))))
end
function f19(a20, a21::Function, a22::Function; kw23 = -5, kw24 = -2)
    __obs__((!(!true)))
    __obs__(g4)
    for i25 in 1:2
        for i26 in 1:1
            v27 = (g4 === :c)
            v29 = ((p28) -> (((fr6(8, 6) != (true ? g2 : kw23)) ? (f10(6) == (v27 ? "b!αy" : "α yaa")) : (f10(kw23) isa AbstractString)) || ((!("αx∀y" < "α0ααx🐛")) ? (string("!yy 🐛1b", "") == f10((-4))) : ((!true) === v27))))
            __obs__((g5 + (max(g1, (-9.75 - (g1 + a20))) - (((v27 ? v27 : false) ? true : (kw24 != (-9))) ? (v27 ? 0.1 : (g1 - -0.0)) : g5))))
        end
        __obs__(g4)
    end
    return (" ∀!∀yxx11β", "0yaβx∀!!b")
end
function f30(a31::Float64 = 0)
    v32 = (g4, g3, g2)
    v33 = Any[g5, "1🐛 a"]
    return ((((true ? g1 : (-8.57 + (-1))) isa Bool) === false) || (a31 == -3.3))
end
__obs__((((max((5.88 - g3), (g5 + g1)) == g1) && true) || ((((-1) - g3) + fr6(fr6((-10), g2), (-7))) <= (((g2 + g2) - g2) * g2))))
v34 = Any[g3]
v36 = Int64[(g3 % (-3)) for c35 in 1:4]
__obs__((try getfield(1, :x) catch __e; (:__thrown, nameof(typeof(__e))) end))
v38 = Int64[(min((-6), fr6(fr6((g2 * 2), get(v36, g3, c37)), (fr6(g2, c37) - g3))) + 3) for c37 in 1:6 if ((get(v36, g3, max(((-4) + g3), get(v36, g3, g3))) - c37) < fr6(3, fr6((-4), g2)))]
let
    v39 = g4
    v40 = f10((fr6(g2, max(g3, fr6(g2, 1))) + g3))
    v41 = g2
    __obs__([v41])
    push!(v34, :a)
    v43 = Int64[fr6(get(v38, ((false ? (3 % (-3)) : max(g3, g2)) ÷ 2), fr6(c42, ((7 + c42) * fr6(6, g3)))), 2) for c42 in 1:1]
    fuel44 = 6
    while f30(-8.56) && (fuel44 > 0)
        global fuel44 -= 1
        for i45 in 1:0
            try; v43[(fr6(((fr6(40, v41) + fr6(i45, (-9))) * (length(v38) * fr6((-1), 1))), max(v41, (abs(g3) * length(v34)))) % 2)] = abs(4); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
            v46 = min(g1, g5)
            v47 = (((!((i45 + 207) != get(v36, i45, (-9223372036854775808)))) ? (((true && false) || true) ? g5 : g1) : (((false ? 2.3 : v46) + g2) * 1.5)) / ((min((false ? -6.6 : 9.72), 0.0) - 9.13) * max(g5, (g5 + max(g1, g5)))))
        end
        push!(v36, 194)
        al48 = v34
        v49 = (v40, g5)
    end
    __obs__((f10(((length(v36) % 1) + fr6((false ? 482 : g3), max((-2), v41)))) isa Number))
    __obs__(get(v43, length(v40), g3))
    fuel50 = 1
    while (((f30((false ? 6.14 : g5)) ? g5 : (g1 / (-7.8 / v41))) - (((v40 == v40) ? (4.9 * g1) : (g5 - g1)) * fr6((v41 * g2), get(v38, g2, 6)))) >= g5) && (fuel50 > 0)
        global fuel50 -= 1
        v51 = f10(((f10(g2) isa String) ? (max(10, (false ? 0 : v41)) * g3) : max(g3, ((false ? 101 : g2) - g3))))
        v52 = (g5 - ((-7.37 + ((NaN * g1) - get(v36, g3, g2))) / g1))
        v53 = v34
    end
    v55 = Float64[(g5 * 0.1) for c54 in 1:6]
    al56 = v36
    push!(v36, fr6(g2, (length(v34) ÷ 1)))
    try; v34[length(v40)] = max((max(((!false) ? abs(g5) : (false ? -3.49 : g1)), g1) - max(g5, g5)), g5); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    __obs__(al56)
    __obs__(v55)
    __obs__(v43)
    __obs__(v41)
    __obs__(v40)
    __obs__(v39)
    __obs__(v38)
    __obs__(v36)
    __obs__(v34)
    __obs__(g5)
    __obs__(g4)
    __obs__(g3)
    __obs__(g2)
    __obs__(g1)
end

```

## Original program

```julia
g1 = (-7.92 / (((((-1) < 5) ? 0.1 : -0.0) + ((0.1 / 3) / (-1.35 + 9.01))) / 8))
global g2::Int64 = (-524)
global g3::Int64 = (-614)
g4 = :c
g5 = g1
function fr6(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr6(n - 1, acc + ((3 * (-630)) + g2))
end
function fr7(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr7(n - 1, acc + g3)
end
function fr7(a8::String, a9::Int64)
    nothing
    return false
end
function f10(a11::Int64)
    fuel12 = 4
    while (("" isa Integer) || (!(((g3 isa String) ? (10 * (-2)) : g3) < a11))) && (fuel12 > 0)
        fuel12 -= 1
        v14 = Float64[((-9.06 + ((-7) - (-5))) / (((-9.44 * (4.82 / g5)) == (g5 / g1)) ? (-9) : g3)) for c13 in 1:2]
        push!(v14, 7.61)
        push!(v14, g1)
        fuel15 = 2
        while ((get(v14, g3, abs((g5 + g2))) / (-1)) == (get(v14, (965 * fr6((-3), g3)), ((false ? g5 : g1) - g2)) - (get(v14, min(g3, g2), 9.02) * -6.49))) && (fuel15 > 0)
            fuel15 -= 1
            v16 = g4
            __obs__(a11)
            __obs__([g2])
        end
    end
    __obs__(((fr6(((!true) ? (false ? g2 : a11) : g3), 7) + (fr6(min(g3, 9), max(g2, (-10))) % 1)) % (-3)))
    for i17 in 1:5
        v18 = (g2 isa Number)
        __obs__((-3.35 * 7.22))
    end
    return string((((("0xαbb∀b0∀x" == "α🐛α") && ("aα" == "αaααβaβyα")) === ((g2 ÷ 7) > (true ? g3 : 10))) ? "ay ∀🐛xx!!y" : "!α🐛0x0β"), (true === (((3.54 + g1) + (g3 - g3)) >= ((!false) ? (true ? g1 : g5) : max(g5, g1)))))
end
function f19(a20, a21::Function, a22::Function; kw23 = -5, kw24 = -2)
    __obs__((!(!true)))
    __obs__(g4)
    for i25 in 1:2
        for i26 in 1:1
            v27 = (g4 === :c)
            v29 = ((p28) -> (((fr6(8, 6) != (true ? g2 : kw23)) ? (f10(6) == (v27 ? "b!αy" : "α yaa")) : (f10(kw23) isa AbstractString)) || ((!("αx∀y" < "α0ααx🐛")) ? (string("!yy 🐛1b", "") == f10((-4))) : ((!true) === v27))))
            __obs__((g5 + (max(g1, (-9.75 - (g1 + a20))) - (((v27 ? v27 : false) ? true : (kw24 != (-9))) ? (v27 ? 0.1 : (g1 - -0.0)) : g5))))
        end
        __obs__(g4)
    end
    return (" ∀!∀yxx11β", "0yaβx∀!!b")
end
function f30(a31::Float64 = 0)
    v32 = (g4, g3, g2)
    v33 = Any[g5, "1🐛 a"]
    return ((((true ? g1 : (-8.57 + (-1))) isa Bool) === false) || (a31 == -3.3))
end
__obs__((((max((5.88 - g3), (g5 + g1)) == g1) && true) || ((((-1) - g3) + fr6(fr6((-10), g2), (-7))) <= (((g2 + g2) - g2) * g2))))
v34 = Any[g3]
v36 = Int64[(g3 % (-3)) for c35 in 1:4]
__obs__((try getfield(1, :x) catch __e; (:__thrown, nameof(typeof(__e))) end))
v38 = Int64[(min((-6), fr6(fr6((g2 * 2), get(v36, g3, c37)), (fr6(g2, c37) - g3))) + 3) for c37 in 1:6 if ((get(v36, g3, max(((-4) + g3), get(v36, g3, g3))) - c37) < fr6(3, fr6((-4), g2)))]
let
    v39 = g4
    v40 = f10((fr6(g2, max(g3, fr6(g2, 1))) + g3))
    v41 = g2
    __obs__([v41])
    push!(v34, :a)
    v43 = Int64[fr6(get(v38, ((false ? (3 % (-3)) : max(g3, g2)) ÷ 2), fr6(c42, ((7 + c42) * fr6(6, g3)))), 2) for c42 in 1:1]
    fuel44 = 6
    while f30(-8.56) && (fuel44 > 0)
        global fuel44 -= 1
        for i45 in 1:0
            try; v43[(fr6(((fr6(40, v41) + fr6(i45, (-9))) * (length(v38) * fr6((-1), 1))), max(v41, (abs(g3) * length(v34)))) % 2)] = abs(4); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
            v46 = min(g1, g5)
            v47 = (((!((i45 + 207) != get(v36, i45, (-9223372036854775808)))) ? (((true && false) || true) ? g5 : g1) : (((false ? 2.3 : v46) + g2) * 1.5)) / ((min((false ? -6.6 : 9.72), 0.0) - 9.13) * max(g5, (g5 + max(g1, g5)))))
        end
        push!(v36, 194)
        al48 = v34
        v49 = (v40, g5)
    end
    __obs__((f10(((length(v36) % 1) + fr6((false ? 482 : g3), max((-2), v41)))) isa Number))
    __obs__(get(v43, length(v40), g3))
    fuel50 = 1
    while (((f30((false ? 6.14 : g5)) ? g5 : (g1 / (-7.8 / v41))) - (((v40 == v40) ? (4.9 * g1) : (g5 - g1)) * fr6((v41 * g2), get(v38, g2, 6)))) >= g5) && (fuel50 > 0)
        global fuel50 -= 1
        v51 = f10(((f10(g2) isa String) ? (max(10, (false ? 0 : v41)) * g3) : max(g3, ((false ? 101 : g2) - g3))))
        v52 = (g5 - ((-7.37 + ((NaN * g1) - get(v36, g3, g2))) / g1))
        v53 = v34
    end
    v55 = Float64[(g5 * 0.1) for c54 in 1:6]
    al56 = v36
    push!(v36, fr6(g2, (length(v34) ÷ 1)))
    try; v34[length(v40)] = max((max(((!false) ? abs(g5) : (false ? -3.49 : g1)), g1) - max(g5, g5)), g5); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    __obs__(al56)
    __obs__(v55)
    __obs__(v43)
    __obs__(v41)
    __obs__(v40)
    __obs__(v39)
    __obs__(v38)
    __obs__(v36)
    __obs__(v34)
    __obs__(g5)
    __obs__(g4)
    __obs__(g3)
    __obs__(g2)
    __obs__(g1)
end

```
