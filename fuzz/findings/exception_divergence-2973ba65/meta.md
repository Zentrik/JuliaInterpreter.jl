# exception_divergence (exception_divergence-2973ba65)

- seed: `5300243`
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel36`: fuel36 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel36`: fuel36 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
g1 = 0.0
g2 = g1
g3 = 7
g4 = ((((("β!bβ1" < "") && true) && (!("αx∀xxβx0β" == "bαba"))) && false) ? g3 : (-10))
g5 = g1
function fr6(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr6(n - 1, acc + n)
end
function f7(a8; kw9 = -1)
    v10 = (try invoke(abs, Tuple{Float64}, -3) catch __e; (:__thrown, nameof(typeof(__e))) end)
    global g3 = kw9
    __obs__((!((!((true || false) ? true : ("ax" isa Float64))) && (!((g1 - 3.69) <= (true ? g2 : -6.6))))))
    return ((p11) -> "🐛x∀1α!1! b")
end
function f7(a12::String)
    nothing
    return :c
end
function f13(a14, a15; kw16 = 1, kw17 = 1)
    (((try Core.Intrinsics.abs_float(-0.0) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Float64)) && return ((false === (((9.6 * g5) / (g5 / g2)) == g2)) ? kw17 : kw17)
    push!(a14, (((fr6((g4 + g3), 2) * ((-3) * (a15 + kw17))) * fr6((fr6((-10), kw16) - (a15 * kw17)), abs((g4 ÷ 3)))) + fr6((a15 * fr6((true ? g3 : kw16), (false ? 0 : 9))), (8 * fr6((-8), (a15 * g4))))))
    return g4
end
function f18()
    global g1 = g2
    return g3
end
function f19(va20...)
    nothing
    return abs(((((1.72 isa AbstractString) ? g4 : g3) * (f13(Any[g3, g2], g3, ; kw16 = g3, kw17 = (-5)) ÷ 3)) + ((!(false ? true : true)) ? abs((-1)) : ((true ? 3 : g4) ÷ 7))))
end
let l21 = 0
    v22 = (l21 - max(f18(), ((l21 * 2) ÷ 7)))
    __obs__((try ((-1) ÷ ((((false ? false : false) ? (false ? l21 : g3) : 0) + f13(Any["α1α x0", 2.24, g1], (-1))) - f13(Any[g2, g4, v22], g3, ; kw16 = 203))) catch __e; (:__thrown, nameof(typeof(__e))) end))
end
let
    v24 = ((p23) -> (!(((g2 isa AbstractString) && (true ? false : true)) || false)))
    __obs__(g3)
    __obs__([4])
    global g4 = ((false ? (((8 * 9223372036854775806) * (g3 + g3)) - 6) : g4) * g3)
    v25 = string("bxybxb0a∀y", :e, ((true && (((-7) <= g4) isa Bool)) ? "baαbax🐛β" : "🐛yαy1x1"))
    v27 = Float64[1.5 for c26 in 1:5 if (string((("∀" == v25) ? 9 : length(v25)), false, v25) < string(((:b === :a) ? v25 : v25), 8))]
    v29 = Float64[g2 for c28 in 1:2]
    v30 = (length(v25) != (((g5 >= min(g5, 3.23)) ? f18() : f13(Any[g1, "∀y!", -1.36], (-3), ; kw16 = max(g4, g3), kw17 = g3)) * (((g4 % (-3)) + fr6(g4, g3)) * f13(Any[true, g2], length(v29), ; kw16 = length(v25), kw17 = (g3 - g3)))))
    al31 = v27
    __obs__(((-3), v25))
    v32 = "0"
    v33 = f19((((g1 >= g5) && true) && (max(8, g4) != (-8))), f18())
    v34 = (g2 > get(al31, length(v27), ((max(g1, g5) - (true ? 0.0 : 5.66)) + ((v30 && true) ? -2.5 : g1))))
    global g5 = g1
    v35 = (0.1, true)
    fuel36 = 4
    while (v32 == (v34 ? string(:a, (v25 != v25)) : (((!true) && (true === v30)) ? string(:e, ("βyβ🐛y!!" != v25), :d) : string(((-107) - 9), v25)))) && (fuel36 > 0)
        global fuel36 -= 1
        __obs__(:a)
    end
    __obs__(v35)
    __obs__(v34)
    __obs__(v33)
    __obs__(v32)
    __obs__(al31)
    __obs__(v30)
    __obs__(v29)
    __obs__(v27)
    __obs__(v25)
    __obs__((try v24(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(g5)
    __obs__(g4)
    __obs__(g3)
    __obs__(g2)
    __obs__(g1)
end

```

## Original program

```julia
g1 = 0.0
g2 = g1
g3 = 7
g4 = ((((("β!bβ1" < "") && true) && (!("αx∀xxβx0β" == "bαba"))) && false) ? g3 : (-10))
g5 = g1
function fr6(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr6(n - 1, acc + n)
end
function f7(a8; kw9 = -1)
    v10 = (try invoke(abs, Tuple{Float64}, -3) catch __e; (:__thrown, nameof(typeof(__e))) end)
    global g3 = kw9
    __obs__((!((!((true || false) ? true : ("ax" isa Float64))) && (!((g1 - 3.69) <= (true ? g2 : -6.6))))))
    return ((p11) -> "🐛x∀1α!1! b")
end
function f7(a12::String)
    nothing
    return :c
end
function f13(a14, a15; kw16 = 1, kw17 = 1)
    (((try Core.Intrinsics.abs_float(-0.0) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Float64)) && return ((false === (((9.6 * g5) / (g5 / g2)) == g2)) ? kw17 : kw17)
    push!(a14, (((fr6((g4 + g3), 2) * ((-3) * (a15 + kw17))) * fr6((fr6((-10), kw16) - (a15 * kw17)), abs((g4 ÷ 3)))) + fr6((a15 * fr6((true ? g3 : kw16), (false ? 0 : 9))), (8 * fr6((-8), (a15 * g4))))))
    return g4
end
function f18()
    global g1 = g2
    return g3
end
function f19(va20...)
    nothing
    return abs(((((1.72 isa AbstractString) ? g4 : g3) * (f13(Any[g3, g2], g3, ; kw16 = g3, kw17 = (-5)) ÷ 3)) + ((!(false ? true : true)) ? abs((-1)) : ((true ? 3 : g4) ÷ 7))))
end
let l21 = 0
    v22 = (l21 - max(f18(), ((l21 * 2) ÷ 7)))
    __obs__((try ((-1) ÷ ((((false ? false : false) ? (false ? l21 : g3) : 0) + f13(Any["α1α x0", 2.24, g1], (-1))) - f13(Any[g2, g4, v22], g3, ; kw16 = 203))) catch __e; (:__thrown, nameof(typeof(__e))) end))
end
let
    v24 = ((p23) -> (!(((g2 isa AbstractString) && (true ? false : true)) || false)))
    __obs__(g3)
    __obs__([4])
    global g4 = ((false ? (((8 * 9223372036854775806) * (g3 + g3)) - 6) : g4) * g3)
    v25 = string("bxybxb0a∀y", :e, ((true && (((-7) <= g4) isa Bool)) ? "baαbax🐛β" : "🐛yαy1x1"))
    v27 = Float64[1.5 for c26 in 1:5 if (string((("∀" == v25) ? 9 : length(v25)), false, v25) < string(((:b === :a) ? v25 : v25), 8))]
    v29 = Float64[g2 for c28 in 1:2]
    v30 = (length(v25) != (((g5 >= min(g5, 3.23)) ? f18() : f13(Any[g1, "∀y!", -1.36], (-3), ; kw16 = max(g4, g3), kw17 = g3)) * (((g4 % (-3)) + fr6(g4, g3)) * f13(Any[true, g2], length(v29), ; kw16 = length(v25), kw17 = (g3 - g3)))))
    al31 = v27
    __obs__(((-3), v25))
    v32 = "0"
    v33 = f19((((g1 >= g5) && true) && (max(8, g4) != (-8))), f18())
    v34 = (g2 > get(al31, length(v27), ((max(g1, g5) - (true ? 0.0 : 5.66)) + ((v30 && true) ? -2.5 : g1))))
    global g5 = g1
    v35 = (0.1, true)
    fuel36 = 4
    while (v32 == (v34 ? string(:a, (v25 != v25)) : (((!true) && (true === v30)) ? string(:e, ("βyβ🐛y!!" != v25), :d) : string(((-107) - 9), v25)))) && (fuel36 > 0)
        global fuel36 -= 1
        __obs__(:a)
    end
    __obs__(v35)
    __obs__(v34)
    __obs__(v33)
    __obs__(v32)
    __obs__(al31)
    __obs__(v30)
    __obs__(v29)
    __obs__(v27)
    __obs__(v25)
    __obs__((try v24(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(g5)
    __obs__(g4)
    __obs__(g3)
    __obs__(g2)
    __obs__(g1)
end

```
