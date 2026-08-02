# exception_divergence (exception_divergence-afd6a7fa)

- seed: `1200007`
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel17`: fuel17 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel17`: fuel17 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
struct S1
    fld2::Vector
end
g3 = max(573, (0 - ((10 - (-9)) * 6)))
g4 = 9223372036854775806
function f5(a6, a7, va8...; kw9 = -4, kw10 = 2)
    v11 = (((-7) * kw10) != 0)
    ((!(((2 * g4) * (10 * 2)) === kw10))) && return 8
    return g4
end
function f5(a12::Float64, a13::S1)
    nothing
    return a12
end
function f14(va15...; kw16 = 4)
    nothing
    return f5(((-9), (-7), :d), S1([g4]), ; kw9 = kw16)
end
__obs__((min(3.86, ((true ? -0.0 : -9.72) - 2.22)) < (((8 <= 1) || (false === false)) ? (5.0 - (false ? 3.97 : -2.5)) : 9.64)))
let
    fuel17 = 2
    while (true || (:b === :d)) && (fuel17 > 0)
        global fuel17 -= 1
        v18 = "1yaα1!"
        for li19 in 1:3
            if li19 == 2
                __obs__(@isdefined(lx20))
                __obs__(try; (:__v, lx20); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx20 = ((((true ? -5.83 : Inf) * (-9)) - -3.88) / (-1.83 * -9.69))
        end
        v21 = length(v18)
    end
    if (!(((true && true) && (6.62 > 1.76)) || ((true isa Bool) && (true && false))))
        v22 = string(:e, " ")
        __obs__(:a)
    end
    for li23 in 1:2
        if li23 == 2
            __obs__(@isdefined(lx24))
            __obs__(try; (:__v, lx24); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx24 = 2
    end
    v27 = ((p25, p26) -> (true && ((-3) != (false ? (-4) : (-452)))))
    __obs__(((-3.79 < (9.85 + g3)) || (true || false)))
    if (g3 < g4)
        u28 = (g3 - 9223372036854775806)
    end
    __obs__(@isdefined(u28))
    __obs__(try; u28; catch __e; (:__undef, nameof(typeof(__e))) end)
    v29 = 8.55
    for li30 in 1:2
        if li30 == 2
            __obs__(@isdefined(lx31))
            __obs__(try; (:__v, lx31); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx31 = 8
    end
    if ("b∀x!α" isa Integer)
        u32 = min(((-7) * (g3 % 2)), g4)
    end
    __obs__(@isdefined(u32))
    __obs__(try; u32; catch __e; (:__undef, nameof(typeof(__e))) end)
    v33 = ((((g4 === 2) && (g3 isa Any)) ? (-9) : (-39)) - (((g4 % 3) * (true ? 2 : g3)) - max((-4), g3)))
    for li34 in 1:2
        if li34 == 2
            __obs__(@isdefined(lx35))
            __obs__(try; (:__v, lx35); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx35 = (-1)
    end
    __obs__(v33)
    __obs__(v29)
    __obs__((try v27(0, 0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(g4)
    __obs__(g3)
end

```

## Original program

```julia
struct S1
    fld2::Vector
end
g3 = max(573, (0 - ((10 - (-9)) * 6)))
g4 = 9223372036854775806
function f5(a6, a7, va8...; kw9 = -4, kw10 = 2)
    v11 = (((-7) * kw10) != 0)
    ((!(((2 * g4) * (10 * 2)) === kw10))) && return 8
    return g4
end
function f5(a12::Float64, a13::S1)
    nothing
    return a12
end
function f14(va15...; kw16 = 4)
    nothing
    return f5(((-9), (-7), :d), S1([g4]), ; kw9 = kw16)
end
__obs__((min(3.86, ((true ? -0.0 : -9.72) - 2.22)) < (((8 <= 1) || (false === false)) ? (5.0 - (false ? 3.97 : -2.5)) : 9.64)))
let
    fuel17 = 2
    while (true || (:b === :d)) && (fuel17 > 0)
        global fuel17 -= 1
        v18 = "1yaα1!"
        for li19 in 1:3
            if li19 == 2
                __obs__(@isdefined(lx20))
                __obs__(try; (:__v, lx20); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx20 = ((((true ? -5.83 : Inf) * (-9)) - -3.88) / (-1.83 * -9.69))
        end
        v21 = length(v18)
    end
    if (!(((true && true) && (6.62 > 1.76)) || ((true isa Bool) && (true && false))))
        v22 = string(:e, " ")
        __obs__(:a)
    end
    for li23 in 1:2
        if li23 == 2
            __obs__(@isdefined(lx24))
            __obs__(try; (:__v, lx24); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx24 = 2
    end
    v27 = ((p25, p26) -> (true && ((-3) != (false ? (-4) : (-452)))))
    __obs__(((-3.79 < (9.85 + g3)) || (true || false)))
    if (g3 < g4)
        u28 = (g3 - 9223372036854775806)
    end
    __obs__(@isdefined(u28))
    __obs__(try; u28; catch __e; (:__undef, nameof(typeof(__e))) end)
    v29 = 8.55
    for li30 in 1:2
        if li30 == 2
            __obs__(@isdefined(lx31))
            __obs__(try; (:__v, lx31); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx31 = 8
    end
    if ("b∀x!α" isa Integer)
        u32 = min(((-7) * (g3 % 2)), g4)
    end
    __obs__(@isdefined(u32))
    __obs__(try; u32; catch __e; (:__undef, nameof(typeof(__e))) end)
    v33 = ((((g4 === 2) && (g3 isa Any)) ? (-9) : (-39)) - (((g4 % 3) * (true ? 2 : g3)) - max((-4), g3)))
    for li34 in 1:2
        if li34 == 2
            __obs__(@isdefined(lx35))
            __obs__(try; (:__v, lx35); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx35 = (-1)
    end
    __obs__(v33)
    __obs__(v29)
    __obs__((try v27(0, 0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(g4)
    __obs__(g3)
end

```
