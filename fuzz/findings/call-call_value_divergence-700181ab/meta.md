# call_value_divergence (call-call_value_divergence-700181ab)

- seed: `1785779695400500959`
- walk seed: `515116876229545754`
- interp mode: `call`
- julia: `1.12.6`
- divergent observation index: 1
- ref exception: `none`  interp exception: `none`

## Detail

```
f10/1: native=-6 interp=8528227659402739553
```

## Shrunk program

```julia
const __LCG__ = Ref{UInt64}(0x000000002a00b911)
__randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
__randint__() = __randu__() % Int64
__randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
__randbool__() = __randu__() % Bool
__randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
mutable struct S1
    fld2::Float64
    @atomic fld3::Symbol
end
struct S4
    fld5::Bool
    fld6::Float64
end
g7 = true
g8 = ((-303) * __randrange__(1, 2))
sv9 = S1(-8.78, :c)
function f10(a11)
    v12 = (:d, g7, -6.06)
    global g8 = (((((-9) - (-121)) * __randrange__(1, 5)) * (g7 ? (g7 ? g8 : 5) : (true ? g8 : (-2)))) + 459)
    try
        sv9.fld2 = __randfloat__()
        v14 = [g8, 5]
        v14 = [g8, 4]
    catch err13
        __obs__((@atomic (sv9).fld3))
    end
    return ((-10) + max(max((9 * (-6)), __randrange__(1, 4)), g8))
end
function f15()
    nothing
    return (:e, "β")
end
fuel16 = 4
while (string(string(:d, g8, (@atomic (sv9).fld3)), string(string("", g7, "baa0🐛∀"), (false ? (-9223372036854775808) : (-7)), "β")) isa Any) && (fuel16 > 0)
    global fuel16 -= 1
    try
        global g8 = g8
    catch err17
        v19 = ((p18) -> ("!yx1β" isa Bool))
        __obs__("")
    end
end
let
    global g7 = false
    try
        v21 = (g7 ? f10(((Inf * Inf) / (sv9).fld2)) : f10((("b1αy0a" < "β1") ? 7.65 : 2.54)))
        __obs__(g8)
        v22 = -0.0
    catch err20
        sv9.fld2 = (((__randfloat__() * 0.0) <= abs((sv9).fld2)) ? (__randfloat__() * (7.34 / max(4.27, 1.91))) : 0.73)
        global sv9 = S1(abs(0.0), :a)
    end
    global sv9 = S1((false ? 8.22 : (g7 ? (sv9).fld2 : __randfloat__())), (@atomic (sv9).fld3))
    global sv9 = sv9
    v23 = 2.19
    global g8 = __randint__()
    for i24 in 1:2
        v25 = Any[2, g8]
        v26 = sv9
    end
    try
        v28 = ("!y", v23, :c)
        global g7 = (g7 && ("" isa Any))
        for i29 in 1:2
            v30 = [v23, v23, v23]
            v31 = abs((sv9).fld2)
        end
    catch err27
        v32 = S4(("" < "α"), (true ? v23 : v23))
        __obs__((try ((f10((sv9).fld2) + ((g8 * 3) + (-6))) % ((string(:a, true, "abx!") != "0α1∀") ? ((g7 ? g8 : g8) - g8) : ((g8 * g8) - ((-3) * g8)))) catch __e; (:__thrown, nameof(typeof(__e))) end))
    end
    sv9.fld2 = (sv9).fld2
    try
        try
            sv9.fld2 = __randfloat__()
        catch err34
            __obs__(g7)
        end
        @atomic sv9.fld3 = :d
    catch err33
        for li35 in 1:3
            if li35 == 3
                __obs__(@isdefined(lx36))
                __obs__(try; (:__v, lx36); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx36 = g8
        end
    end
    __obs__(-Inf)
    __obs__(v23)
    __obs__(sv9)
    __obs__(g8)
    __obs__(g7)
end

```

## Original program

```julia
const __LCG__ = Ref{UInt64}(0x000000002a00b911)
__randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
__randint__() = __randu__() % Int64
__randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
__randbool__() = __randu__() % Bool
__randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
mutable struct S1
    fld2::Float64
    @atomic fld3::Symbol
end
struct S4
    fld5::Bool
    fld6::Float64
end
g7 = true
g8 = ((-303) * __randrange__(1, 2))
sv9 = S1(-8.78, :c)
function f10(a11)
    v12 = (:d, g7, -6.06)
    global g8 = (((((-9) - (-121)) * __randrange__(1, 5)) * (g7 ? (g7 ? g8 : 5) : (true ? g8 : (-2)))) + 459)
    try
        sv9.fld2 = __randfloat__()
        v14 = [g8, 5]
        v14 = [g8, 4]
    catch err13
        __obs__((@atomic (sv9).fld3))
    end
    return ((-10) + max(max((9 * (-6)), __randrange__(1, 4)), g8))
end
function f15()
    nothing
    return (:e, "β")
end
fuel16 = 4
while (string(string(:d, g8, (@atomic (sv9).fld3)), string(string("", g7, "baa0🐛∀"), (false ? (-9223372036854775808) : (-7)), "β")) isa Any) && (fuel16 > 0)
    global fuel16 -= 1
    try
        global g8 = g8
    catch err17
        v19 = ((p18) -> ("!yx1β" isa Bool))
        __obs__("")
    end
end
let
    global g7 = false
    try
        v21 = (g7 ? f10(((Inf * Inf) / (sv9).fld2)) : f10((("b1αy0a" < "β1") ? 7.65 : 2.54)))
        __obs__(g8)
        v22 = -0.0
    catch err20
        sv9.fld2 = (((__randfloat__() * 0.0) <= abs((sv9).fld2)) ? (__randfloat__() * (7.34 / max(4.27, 1.91))) : 0.73)
        global sv9 = S1(abs(0.0), :a)
    end
    global sv9 = S1((false ? 8.22 : (g7 ? (sv9).fld2 : __randfloat__())), (@atomic (sv9).fld3))
    global sv9 = sv9
    v23 = 2.19
    global g8 = __randint__()
    for i24 in 1:2
        v25 = Any[2, g8]
        v26 = sv9
    end
    try
        v28 = ("!y", v23, :c)
        global g7 = (g7 && ("" isa Any))
        for i29 in 1:2
            v30 = [v23, v23, v23]
            v31 = abs((sv9).fld2)
        end
    catch err27
        v32 = S4(("" < "α"), (true ? v23 : v23))
        __obs__((try ((f10((sv9).fld2) + ((g8 * 3) + (-6))) % ((string(:a, true, "abx!") != "0α1∀") ? ((g7 ? g8 : g8) - g8) : ((g8 * g8) - ((-3) * g8)))) catch __e; (:__thrown, nameof(typeof(__e))) end))
    end
    sv9.fld2 = (sv9).fld2
    try
        try
            sv9.fld2 = __randfloat__()
        catch err34
            __obs__(g7)
        end
        @atomic sv9.fld3 = :d
    catch err33
        for li35 in 1:3
            if li35 == 3
                __obs__(@isdefined(lx36))
                __obs__(try; (:__v, lx36); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx36 = g8
        end
    end
    __obs__(-Inf)
    __obs__(v23)
    __obs__(sv9)
    __obs__(g8)
    __obs__(g7)
end

```
