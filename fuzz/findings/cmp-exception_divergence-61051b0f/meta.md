# exception_divergence (cmp-exception_divergence-61051b0f)

- seed: `747`
- interp mode: `cmp`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `MethodError`  interp exception: `ErrorException`

## Detail

```
ref threw MethodError (MethodError: no method matching -(::Tuple{Symbol, Symbol}, ::Float64)
The function `-` exists, but no method is defined for this combination of argument types.

Closest candidates are:
  -(!Matched::BigFloat, ::Union{Float16, Float32, Float64})
   @ Base mpfr.jl:565
  -(!Matched::Complex{Bool}, ::Real)
   @ Base complex.jl:329
  -(!Matched::Missing, ::Number)
   @ Base missing.jl:123
  ...
); interp threw ErrorException (rethrow() not allowed outside a catch block)
```

## Shrunk program

```julia
function f5(a6, a7)
    try
        try
            ((((2 + 1) ÷ 1) != (((true && true) ? a6 : ((-12) ÷ (-3))) * a6))) && return (try (max(0, (a6 - (a6 % (-1)))) % a6) catch __e; (:__thrown, nameof(typeof(__e))) end)
        catch err10
            nothing
        end
    catch err8
        nothing
    finally
        nothing
    end
    return a7
end
let
    try
        __obs__((f5(0, f5(0, 0.0)) - 0.0))
    catch err18
        if (:b === :b)
            u20 = (0 - 0)
        end
        __obs__(@isdefined(u20))
        __obs__(try; u20; catch __e; (:__undef, nameof(typeof(__e))) end)
        (((((!true) ? (-8) : (0 % 3)) < 0) ? (0 == 1) : (!("yb🐛ab" < string((-10), ""))))) && rethrow()
    else
        nothing
    end
end

```

## Original program

```julia
g1 = ((((true ? -4.13 : -2.21) + min(1.5, -6.6)) > (-2.12 / (true ? 9.23 : -1.61))) ? max((5.29 * (-6.09 * -0.25)), (-7.33 - -6.28)) : (4.66 - 6.64))
function f2(a3::Symbol, a4::Symbol)
    nothing
    return (((-275) * (min((-6), 10) % 1)) % 2)
end
function f5(a6, a7)
    try
        v9 = (((max(a7, -8.39) <= g1) isa Int64) ? string(a6, max((a6 + 6), (true ? a6 : a6))) : "")
        try
            ((((2 + 1) ÷ 1) != (((true && true) ? a6 : ((-12) ÷ (-3))) * a6))) && return (try (max(f2(:b, :a), (a6 - (a6 % (-1)))) % a6) catch __e; (:__thrown, nameof(typeof(__e))) end)
        catch err10
            a6 = 7
        end
    catch err8
        __obs__([a6, a6, (-6)])
        err8 = :c
    finally
        v11 = ""
    end
    return a7
end
function fr12(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr12(n - 1, acc + (0 + acc))
end
function fr12(a13::Float64, a14::Int64)
    nothing
    return (f2(:c, :c) - f2(:b, :b))
end
v15 = 10
v16 = Any[nothing]
push!(v16, v15)
let
    __obs__((g1 < 1.5))
    local t17::Int64 = ((f2(:a, :d) - f2(:d, :c)) * 7)
    try
        __obs__((f5(f2(:b, :d), f5(t17, g1)) - g1))
        __obs__(f5(((v15 % 3) - (9 + fr12(-7.18, v15))), (("!βy" == "0 1y ") ? (g1 * (-1)) : g1)))
    catch err18
        v19 = [g1, 2.2250738585072014e-308, -7.06]
        if (:b === :b)
            u20 = (fr12(g1, (true ? t17 : ((-10) - t17))) - t17)
        end
        __obs__(@isdefined(u20))
        __obs__(try; u20; catch __e; (:__undef, nameof(typeof(__e))) end)
        (((((!true) ? (-8) : (v15 % 3)) < fr12(-6.39, (-7))) ? (v15 == 1) : (!("yb🐛ab" < string((-10), ""))))) && rethrow()
    else
        v21 = ("∀", "xβxα")
    end
    try
        v24 = ((p23) -> ((true ? "0β0🐛β1" : "βaa🐛 ") === "b0🐛🐛β"))
        __obs__(v15)
        for li25 in 1:2
            if li25 == 2
                __obs__(@isdefined(lx26))
                __obs__(try; (:__v, lx26); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx26 = ((((false ? 7.31 : -7.8) * 7) + ((v15 >= li25) ? li25 : li25)) / (f5(t17, (true ? g1 : g1)) * ((li25 * (-10)) + (false ? t17 : 10))))
        end
    catch err22
        v27 = fr12(((max(t17, (-214)) ÷ 3) + ((true || true) ? 10 : fr12(g1, t17))), ((-4) + ((v15 - (-130)) - abs((-9)))))
        try
            err22 = -4.45
        catch err28
            err22 = (true isa Float64)
            try
                __obs__(((string(true, ("y∀β" == "a!🐛")) == "y") ? t17 : ((t17 + 0) - ((false || false) ? t17 : (t17 + v15)))))
            catch err29
                __obs__([(-5), 10])
                v30 = (try (v16)[(((true ? v27 : t17) * v27) + (9223372036854775806 + fr12((-4), v27)))] catch __e; (:__thrown, nameof(typeof(__e))) end)
            else
                v31 = [g1, 8.97, g1]
            end
        else
            for li32 in 1:2
                if li32 == 2
                    __obs__(@isdefined(lx33))
                    __obs__(try; (:__v, lx33); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx33 = f5(li32, 5.38)
            end
        finally
            if ("b0aββα" == string((!(true && false)), string(false, (:c === :b), :a), ((false ? true : false) && (g1 > 1.68))))
                u34 = fr12(f5((v27 + (v27 % (-3))), (g1 - f5(9, g1))), (4 * v27))
            end
            __obs__(@isdefined(u34))
            __obs__(try; u34; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
    end
    __obs__(((-854), "∀x!"))
    push!(v16, abs(g1))
    __obs__(t17)
    __obs__(v16)
    __obs__(v15)
    __obs__(g1)
end

```
