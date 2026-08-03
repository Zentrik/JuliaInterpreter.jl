# call_value_divergence (call-call_value_divergence-6deeb299)

- seed: `1785779695403601143`
- walk seed: `1511666922561067042`
- interp mode: `call`
- julia: `1.12.6`
- divergent observation index: 1
- ref exception: `none`  interp exception: `none`

## Detail

```
f13/0: native=(:__thrown, :ErrorException) interp=(:__thrown, :ConcurrencyViolationError)
```

## Shrunk program

```julia
const __LCG__ = Ref{UInt64}(0x00000000155170f9)
__randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
__randint__() = __randu__() % Int64
__randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
__randbool__() = __randu__() % Bool
__randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
mutable struct S1
    fld2::Symbol
end
sv3 = S1(:c)
function f4(a5, a6::Tuple)
    local t7::Int64 = 6
    return ((((true || false) ? -2.5 : max(-8.65, 1.6)) - __randrange__(1, 8)) != -9.16)
end
function f8(a9::Float64, a10::Symbol, a11 = 0)
    v12 = 3
    return (v12 - v12)
end
function f13(a14 = 0; kw15 = -2)
    fuel16 = 4
    while ((sv3).fld2 === (sv3).fld2) && (fuel16 > 0)
        fuel16 -= 1
        try
            __obs__(((((9.41 - -7.38) * a14) > ((true || true) ? (true ? -8.77 : 4.32) : __randfloat__())) ? a14 : ((__randrange__(1, 2) + (839 + 2)) - f8(3.48, (sv3).fld2, (sv3).fld2))))
        catch err17
            v18 = (sv3).fld2
            v19 = [a14, (-7), a14]
            (((((5.86 * 5.39) - (0.0 * -2.5)) + kw15) != 9.62)) && rethrow()
        end
        for i20 in 1:__randrange__(0, 4)
            if f4((9223372036854775806 - abs(i20)), (-6.34, "x∀yaαa"))
                v23 = ((p21, p22) -> ((f4(a14, (p21, "xa🐛0β∀")) && (a14 != a14)) ? 1.7976931348623157e308 : (p21 - 1.63)))
            else
                ((840 > kw15)) && break
            end
        end
        ((!(((0.1 * -5.82) / (-7.98 * -8.2)) == ((-2.28 + 3) / abs(9.75))))) && break
    end
    local t24::Float64 = 2.57
    return (try Base.atomic_fence(:unordered) catch __e; (:__thrown, nameof(typeof(__e))) end)
end
__obs__(640)
__obs__(:e)
let
    for i25 in 1:__randrange__(0, 4)
        if (f8((2.2250738585072014e-308 - 0), (sv3).fld2, (sv3).fld2) >= i25)
            __obs__((f8(-6.67, (sv3).fld2, (sv3).fld2) * 9))
        end
        for i26 in 1:0
            v27 = Dict{Char, Int64}()
        end
    end
    if (f4(abs((-3)), (-9.45, "")) === (__randbool__() || false))
        v29 = ((p28) -> -0.0)
        try
            v31 = Dict{Bool, String}(true => "αβ1", true => "bα🐛 ∀")
            __obs__(keys(v31))
        catch err30
            v32 = 630
        end
    end
    try
        v34 = [9]
    catch err33
        v35 = f8(-2.59, (sv3).fld2, (sv3).fld2)
    end
    if ((__randbool__() ? __randfloat__() : 1.89) > ((((-4) == 9223372036854775806) ? 4.88 : -2.93) - abs(min(-0.09, 5.47))))
        __obs__((try Core.setglobalonce!((@__MODULE__), Base.compilerbarrier(:const, :__probe_g_zzz), Base.compilerbarrier(:const, (-5))) catch __e; (:__thrown, nameof(typeof(__e))) end))
        __obs__((try f13(6.3) catch __e; (:__thrown, nameof(typeof(__e))) end))
    else
        fuel36 = 2
        while (f8(-6.75, (sv3).fld2, :d) <= ((-8) + 5)) && (fuel36 > 0)
            fuel36 -= 1
            local t37::Int64 = 569
        end
        v38 = ""
    end
    v39 = (5, 3)
    let l40 = (-9), l41 = f4(max(f8((9.65 - 2.72), (sv3).fld2, (sv3).fld2), f8((false ? 9.87 : 1.7976931348623157e308), :c, (sv3).fld2)), (-5.36, "a0!α0"))
        v44 = ((p42, p43) -> (((l41 || l41) ? f8(1.5, :d, :e) : __randint__()) * ((l40 * l40) + l40)))
        local t45::Int64 = f8((__randfloat__() / -2.5), :e, :a)
        __obs__(((__randfloat__() <= ((-6.37 * 1.7976931348623157e308) / (t45 + t45))) ? t45 : (((-9) - (false ? t45 : t45)) + ((t45 ÷ 1) * (l40 * l40)))))
    end
    try
        __obs__((sv3).fld2)
    catch err46
        for i47 in 1:3
            (("xay0" != string(i47, (__randint__() + f8(-0.91, :c, :c))))) && break
        end
    else
        local t48::Float64 = (0.36 + ((-3.29 - -9.18) * (abs(329) * (true ? 9 : 445))))
    end
    v49 = (try trunc(Int8, 300.0) catch __e; (:__thrown, nameof(typeof(__e))) end)
    v50 = Set{Char}(['b', 'α'])
    if (__randint__() === (5 * __randrange__(1, 4)))
        v51 = nothing
        __obs__(((-4.19 >= -6.94) ? ((3.71 - -9.09) + ((6.49 - 1.01) * (true ? -9.12 : 6.1))) : 6.94))
        __obs__(((-0.66 / -3.05) / ((max((-8), (-2)) - length(v50)) + (-7))))
    end
    push!(v50, ' ')
    __obs__(v50)
    __obs__(v49)
    __obs__(v39)
    __obs__(sv3)
end

```

## Original program

```julia
const __LCG__ = Ref{UInt64}(0x00000000155170f9)
__randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
__randint__() = __randu__() % Int64
__randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
__randbool__() = __randu__() % Bool
__randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
mutable struct S1
    fld2::Symbol
end
sv3 = S1(:c)
function f4(a5, a6::Tuple)
    local t7::Int64 = 6
    return ((((true || false) ? -2.5 : max(-8.65, 1.6)) - __randrange__(1, 8)) != -9.16)
end
function f8(a9::Float64, a10::Symbol, a11 = 0)
    v12 = 3
    return (v12 - v12)
end
function f13(a14 = 0; kw15 = -2)
    fuel16 = 4
    while ((sv3).fld2 === (sv3).fld2) && (fuel16 > 0)
        fuel16 -= 1
        try
            __obs__(((((9.41 - -7.38) * a14) > ((true || true) ? (true ? -8.77 : 4.32) : __randfloat__())) ? a14 : ((__randrange__(1, 2) + (839 + 2)) - f8(3.48, (sv3).fld2, (sv3).fld2))))
        catch err17
            v18 = (sv3).fld2
            v19 = [a14, (-7), a14]
            (((((5.86 * 5.39) - (0.0 * -2.5)) + kw15) != 9.62)) && rethrow()
        end
        for i20 in 1:__randrange__(0, 4)
            if f4((9223372036854775806 - abs(i20)), (-6.34, "x∀yaαa"))
                v23 = ((p21, p22) -> ((f4(a14, (p21, "xa🐛0β∀")) && (a14 != a14)) ? 1.7976931348623157e308 : (p21 - 1.63)))
            else
                ((840 > kw15)) && break
            end
        end
        ((!(((0.1 * -5.82) / (-7.98 * -8.2)) == ((-2.28 + 3) / abs(9.75))))) && break
    end
    local t24::Float64 = 2.57
    return (try Base.atomic_fence(:unordered) catch __e; (:__thrown, nameof(typeof(__e))) end)
end
__obs__(640)
__obs__(:e)
let
    for i25 in 1:__randrange__(0, 4)
        if (f8((2.2250738585072014e-308 - 0), (sv3).fld2, (sv3).fld2) >= i25)
            __obs__((f8(-6.67, (sv3).fld2, (sv3).fld2) * 9))
        end
        for i26 in 1:0
            v27 = Dict{Char, Int64}()
        end
    end
    if (f4(abs((-3)), (-9.45, "")) === (__randbool__() || false))
        v29 = ((p28) -> -0.0)
        try
            v31 = Dict{Bool, String}(true => "αβ1", true => "bα🐛 ∀")
            __obs__(keys(v31))
        catch err30
            v32 = 630
        end
    end
    try
        v34 = [9]
    catch err33
        v35 = f8(-2.59, (sv3).fld2, (sv3).fld2)
    end
    if ((__randbool__() ? __randfloat__() : 1.89) > ((((-4) == 9223372036854775806) ? 4.88 : -2.93) - abs(min(-0.09, 5.47))))
        __obs__((try Core.setglobalonce!((@__MODULE__), Base.compilerbarrier(:const, :__probe_g_zzz), Base.compilerbarrier(:const, (-5))) catch __e; (:__thrown, nameof(typeof(__e))) end))
        __obs__((try f13(6.3) catch __e; (:__thrown, nameof(typeof(__e))) end))
    else
        fuel36 = 2
        while (f8(-6.75, (sv3).fld2, :d) <= ((-8) + 5)) && (fuel36 > 0)
            fuel36 -= 1
            local t37::Int64 = 569
        end
        v38 = ""
    end
    v39 = (5, 3)
    let l40 = (-9), l41 = f4(max(f8((9.65 - 2.72), (sv3).fld2, (sv3).fld2), f8((false ? 9.87 : 1.7976931348623157e308), :c, (sv3).fld2)), (-5.36, "a0!α0"))
        v44 = ((p42, p43) -> (((l41 || l41) ? f8(1.5, :d, :e) : __randint__()) * ((l40 * l40) + l40)))
        local t45::Int64 = f8((__randfloat__() / -2.5), :e, :a)
        __obs__(((__randfloat__() <= ((-6.37 * 1.7976931348623157e308) / (t45 + t45))) ? t45 : (((-9) - (false ? t45 : t45)) + ((t45 ÷ 1) * (l40 * l40)))))
    end
    try
        __obs__((sv3).fld2)
    catch err46
        for i47 in 1:3
            (("xay0" != string(i47, (__randint__() + f8(-0.91, :c, :c))))) && break
        end
    else
        local t48::Float64 = (0.36 + ((-3.29 - -9.18) * (abs(329) * (true ? 9 : 445))))
    end
    v49 = (try trunc(Int8, 300.0) catch __e; (:__thrown, nameof(typeof(__e))) end)
    v50 = Set{Char}(['b', 'α'])
    if (__randint__() === (5 * __randrange__(1, 4)))
        v51 = nothing
        __obs__(((-4.19 >= -6.94) ? ((3.71 - -9.09) + ((6.49 - 1.01) * (true ? -9.12 : 6.1))) : 6.94))
        __obs__(((-0.66 / -3.05) / ((max((-8), (-2)) - length(v50)) + (-7))))
    end
    push!(v50, ' ')
    __obs__(v50)
    __obs__(v49)
    __obs__(v39)
    __obs__(sv3)
end

```
