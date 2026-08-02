# exception_divergence (cmp-exception_divergence-ef6b0e8d)

- seed: `1200003`
- interp mode: `cmp`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel33`: fuel33 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel33`: fuel33 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
mutable struct S1
    fld2::Float64
    @atomic fld3::Float64
    fld4::Int64
end
g5 = :b
g6 = ((abs(5) * 9) - (min(8, (-9)) + min(abs((-1)), 9)))
sv7 = S1(0.41, -6.39, g6)
function f8(a9, a10::Float64, a11)
    nothing
    return (a11 < (a11 / ((a10 + 4.28) / g6)))
end
function f12(a13::Bool, a14::String; kw15 = 2, kw16 = 1)
    nothing
    return "x∀01"
end
try
    try
        v19 = sv7
    catch err18
        v20 = 8.86
    else
        __obs__(string((6 + ((true ? g6 : g6) - 663)), (!(:e === g5)), f12((true || (false ? false : true)), "0bα!α")))
    end
    __obs__(g5)
catch err17
    for li21 in 1:3
        if li21 == 2
            __obs__(@isdefined(lx22))
            __obs__(try; (:__v, lx22); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx22 = (sv7).fld4
    end
    v23 = g5
    ((f12((("🐛a0β0" isa String) || ("" < "🐛α x")), "1a!0β") != string(false, string(f8([g6, g6], -5.33, -3.71), g5)))) && rethrow()
else
    let l24 = 0.0, l25 = g6
        al26 = sv7
    end
end
for i27 in 1:1
    for i28 in 1:0
        (f8((!(true ? (-9.41 < -4.01) : ("α🐛 🐛x" < "aα"))), abs(-5.75), 4.94)) && break
    end
end
try
    __obs__((try (abs(g6) ÷ g6) catch __e; (:__thrown, nameof(typeof(__e))) end))
catch err29
    v30 = sv7
    v31 = S1(0.1, ((@atomic (sv7).fld3) + (v30).fld2), (-3))
finally
    v32 = f8(((!f8("bxβ", -1.01, -8.4)) ? ((g6 - g6) * g6) : (sv7).fld4), -6.44, (false ? ((1.29 / -9.14) * (g6 - g6)) : (sv7).fld2))
end
let
    fuel33 = 2
    while ((false && ((false && false) || (" b∀β" != "🐛α b"))) && (!true)) && (fuel33 > 0)
        global fuel33 -= 1
        v36 = ((p34, p35) -> p35)
        try
            try
                v39 = (!(f8((g6 >= g6), -0.0, (Inf * 7.67)) && (!(true && false))))
            catch err38
                local t40::Float64 = 9.88
                (((f12(f8((10, g6), t40, 0.0), string("1🐛y0α🐛", (-3), true)) < f12((false || true), "αα", ; kw15 = g6, kw16 = g6)) || (t40 != ((t40 * -8.12) / (@atomic (sv7).fld3))))) && break
            end
            @atomic sv7.fld3 *= -7.56
        catch err37
            __obs__(f12((((sv7).fld4 - (sv7).fld4) != (sv7).fld4), f12((f12(false, "a!") != "y"), "αy🐛β ", ; kw16 = ((false || false) ? (g6 * 4) : g6)), ; kw15 = g6, kw16 = (-6)))
            __obs__(string(g5, g5, string(g5, (true || (true ? true : true)), g5)))
        end
    end
    __obs__((sv7).fld4)
    @atomic sv7.fld3 += -4.36
    local t41::Float64 = (((("" != "y∀βα1β") || (-3.29 < 5.13)) ? ((false ? 4.73 : -1.05) + abs(1.21)) : (sv7).fld2) - (g6 - (sv7).fld4))
    local t42::Int64 = g6
    v45 = ((p43, p44) -> f12((g5 === g5), "a"))
    __obs__("")
    let l46 = g5
        v47 = (-7)
    end
    __obs__([g6])
    __obs__([g6, g6, g6])
    v48 = [t42, 5, (-6)]
    __obs__(v48)
    __obs__((try v45(0, 0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(t42)
    __obs__(t41)
    __obs__(sv7)
    __obs__(g6)
    __obs__(g5)
end

```

## Original program

```julia
mutable struct S1
    fld2::Float64
    @atomic fld3::Float64
    fld4::Int64
end
g5 = :b
g6 = ((abs(5) * 9) - (min(8, (-9)) + min(abs((-1)), 9)))
sv7 = S1(0.41, -6.39, g6)
function f8(a9, a10::Float64, a11)
    nothing
    return (a11 < (a11 / ((a10 + 4.28) / g6)))
end
function f12(a13::Bool, a14::String; kw15 = 2, kw16 = 1)
    nothing
    return "x∀01"
end
try
    try
        v19 = sv7
    catch err18
        v20 = 8.86
    else
        __obs__(string((6 + ((true ? g6 : g6) - 663)), (!(:e === g5)), f12((true || (false ? false : true)), "0bα!α")))
    end
    __obs__(g5)
catch err17
    for li21 in 1:3
        if li21 == 2
            __obs__(@isdefined(lx22))
            __obs__(try; (:__v, lx22); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx22 = (sv7).fld4
    end
    v23 = g5
    ((f12((("🐛a0β0" isa String) || ("" < "🐛α x")), "1a!0β") != string(false, string(f8([g6, g6], -5.33, -3.71), g5)))) && rethrow()
else
    let l24 = 0.0, l25 = g6
        al26 = sv7
    end
end
for i27 in 1:1
    for i28 in 1:0
        (f8((!(true ? (-9.41 < -4.01) : ("α🐛 🐛x" < "aα"))), abs(-5.75), 4.94)) && break
    end
end
try
    __obs__((try (abs(g6) ÷ g6) catch __e; (:__thrown, nameof(typeof(__e))) end))
catch err29
    v30 = sv7
    v31 = S1(0.1, ((@atomic (sv7).fld3) + (v30).fld2), (-3))
finally
    v32 = f8(((!f8("bxβ", -1.01, -8.4)) ? ((g6 - g6) * g6) : (sv7).fld4), -6.44, (false ? ((1.29 / -9.14) * (g6 - g6)) : (sv7).fld2))
end
let
    fuel33 = 2
    while ((false && ((false && false) || (" b∀β" != "🐛α b"))) && (!true)) && (fuel33 > 0)
        global fuel33 -= 1
        v36 = ((p34, p35) -> p35)
        try
            try
                v39 = (!(f8((g6 >= g6), -0.0, (Inf * 7.67)) && (!(true && false))))
            catch err38
                local t40::Float64 = 9.88
                (((f12(f8((10, g6), t40, 0.0), string("1🐛y0α🐛", (-3), true)) < f12((false || true), "αα", ; kw15 = g6, kw16 = g6)) || (t40 != ((t40 * -8.12) / (@atomic (sv7).fld3))))) && break
            end
            @atomic sv7.fld3 *= -7.56
        catch err37
            __obs__(f12((((sv7).fld4 - (sv7).fld4) != (sv7).fld4), f12((f12(false, "a!") != "y"), "αy🐛β ", ; kw16 = ((false || false) ? (g6 * 4) : g6)), ; kw15 = g6, kw16 = (-6)))
            __obs__(string(g5, g5, string(g5, (true || (true ? true : true)), g5)))
        end
    end
    __obs__((sv7).fld4)
    @atomic sv7.fld3 += -4.36
    local t41::Float64 = (((("" != "y∀βα1β") || (-3.29 < 5.13)) ? ((false ? 4.73 : -1.05) + abs(1.21)) : (sv7).fld2) - (g6 - (sv7).fld4))
    local t42::Int64 = g6
    v45 = ((p43, p44) -> f12((g5 === g5), "a"))
    __obs__("")
    let l46 = g5
        v47 = (-7)
    end
    __obs__([g6])
    __obs__([g6, g6, g6])
    v48 = [t42, 5, (-6)]
    __obs__(v48)
    __obs__((try v45(0, 0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(t42)
    __obs__(t41)
    __obs__(sv7)
    __obs__(g6)
    __obs__(g5)
end

```
