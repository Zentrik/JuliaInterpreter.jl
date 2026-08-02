# exception_divergence (exception_divergence-d6369a0b)

- seed: `1200005`
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel9`: fuel9 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel9`: fuel9 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
g1 = :d
function f2(a3, va4...)
    if (2.45 <= 2.220446049250313e-16)
        u5 = (min(-9.81, 0.83) / 2.220446049250313e-16)
    end
    __obs__(@isdefined(u5))
    __obs__(try; u5; catch __e; (:__undef, nameof(typeof(__e))) end)
    for i6 in 1:1
        v7 = Any[i6, va4]
        (("1α1αβ🐛" < string(:d, string(g1, :c), i6))) && continue
    end
    return (-4.2, g1)
end
function fr8(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr8(n - 1, acc + n)
end
let
    fuel9 = 2
    while true && (fuel9 > 0)
        global fuel9 -= 1
        global g1 = g1
        global g1 = :d
        ((false && ((g1 === g1) && (string(g1, "y∀β") < "a0∀🐛a1")))) && continue
    end
    __obs__(:e)
    v11 = Float64[9.14 for c10 in 1:4 if (fr8((max((-3), c10) + min(1, c10)), fr8((-5), (c10 * (-6)))) > (((c10 ÷ (-3)) + (-5)) * ((false ? c10 : c10) + (-4))))]
    v12 = Any[v11, g1]
    __obs__(max((max(min(-4.99, 3.44), (4.64 - -2.5)) * get(v11, (-1), -5.13)), get(v11, max(length(v12), ((-313) ÷ 2)), max((7.27 + -0.82), 2.31))))
    try; v11[(5 + (fr8(fr8((-5), (-47)), fr8((-5), (-9))) * (fr8((-6), (-7)) * (-9))))] = 6.17; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    for li13 in 1:2
        if li13 == 2
            __obs__(@isdefined(lx14))
            __obs__(try; (:__v, lx14); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx14 = length(v11)
    end
    v17 = ((p15, p16) -> "y 11!1")
    push!(v12, ((abs((-2)) + ((false ? 8 : 5) + fr8((-4), 6))) - 2))
    v18 = Any[v11]
    v19 = (true, 689)
    fuel20 = 2
    while (NaN <= ((!true) ? (get(v11, (-5), -1.17) / 0.0) : get(v11, (0 + (-4)), get(v11, (-8), -0.67)))) && (fuel20 > 0)
        global fuel20 -= 1
        v18 = Any[v19]
    end
    __obs__(v19)
    __obs__(v18)
    __obs__((try v17(0, 0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v12)
    __obs__(v11)
    __obs__(g1)
end

```

## Original program

```julia
g1 = :d
function f2(a3, va4...)
    if (2.45 <= 2.220446049250313e-16)
        u5 = (min(-9.81, 0.83) / 2.220446049250313e-16)
    end
    __obs__(@isdefined(u5))
    __obs__(try; u5; catch __e; (:__undef, nameof(typeof(__e))) end)
    for i6 in 1:1
        v7 = Any[i6, va4]
        (("1α1αβ🐛" < string(:d, string(g1, :c), i6))) && continue
    end
    return (-4.2, g1)
end
function fr8(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr8(n - 1, acc + n)
end
let
    fuel9 = 2
    while true && (fuel9 > 0)
        global fuel9 -= 1
        global g1 = g1
        global g1 = :d
        ((false && ((g1 === g1) && (string(g1, "y∀β") < "a0∀🐛a1")))) && continue
    end
    __obs__(:e)
    v11 = Float64[9.14 for c10 in 1:4 if (fr8((max((-3), c10) + min(1, c10)), fr8((-5), (c10 * (-6)))) > (((c10 ÷ (-3)) + (-5)) * ((false ? c10 : c10) + (-4))))]
    v12 = Any[v11, g1]
    __obs__(max((max(min(-4.99, 3.44), (4.64 - -2.5)) * get(v11, (-1), -5.13)), get(v11, max(length(v12), ((-313) ÷ 2)), max((7.27 + -0.82), 2.31))))
    try; v11[(5 + (fr8(fr8((-5), (-47)), fr8((-5), (-9))) * (fr8((-6), (-7)) * (-9))))] = 6.17; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    for li13 in 1:2
        if li13 == 2
            __obs__(@isdefined(lx14))
            __obs__(try; (:__v, lx14); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx14 = length(v11)
    end
    v17 = ((p15, p16) -> "y 11!1")
    push!(v12, ((abs((-2)) + ((false ? 8 : 5) + fr8((-4), 6))) - 2))
    v18 = Any[v11]
    v19 = (true, 689)
    fuel20 = 2
    while (NaN <= ((!true) ? (get(v11, (-5), -1.17) / 0.0) : get(v11, (0 + (-4)), get(v11, (-8), -0.67)))) && (fuel20 > 0)
        global fuel20 -= 1
        v18 = Any[v19]
    end
    __obs__(v19)
    __obs__(v18)
    __obs__((try v17(0, 0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v12)
    __obs__(v11)
    __obs__(g1)
end

```
