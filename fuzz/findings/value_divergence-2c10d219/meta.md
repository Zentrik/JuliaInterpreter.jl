# value_divergence (value_divergence-2c10d219)

- seed: `100102954`
- interp mode: `rec`
- julia: `1.12.6`
- divergent observation index: 4
- ref exception: `none`  interp exception: `none`

## Detail

```
obs[4]: ref=(:__thrown, :TypeError) interp=(:__thrown, :ErrorException)
```

## Shrunk program

```julia
const __LCG__ = Ref{UInt64}(0x0000000037737832)
__randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
__randint__() = __randu__() % Int64
__randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
__randbool__() = __randu__() % Bool
__randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
mutable struct S1
    @atomic fld2::Int64
    @atomic fld3::Int64
end
global g4::Int64 = 8
g5 = "xy "
const g6 = (5 * __randint__())
sv7 = S1((-1), g4)
function fr8(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr8(n - 1, acc + (-531))
end
function f9(a10, a11, va12...; kw13 = 2, kw14 = -3)
    nothing
    return __randfloat__()
end
v15 = [8.31, -6.48]
let
    v16 = f9(S1((-9), (-927)), "!!xbx0", ; kw13 = min(length(v15), g6))
    @atomic sv7.fld3 = (@atomic (sv7).fld2)
    v18 = ((p17) -> (v16 = (v16 * v16); v16))
    try
        try
            __obs__((698 < fr8((@atomic (sv7).fld2), ((true ? g6 : g4) + ((-4) + (-2))))))
            try; v15[min((@atomic (sv7).fld2), g6)] = v16; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        catch err20
            v21 = " αβ1"
        end
    catch err19
        try
            v23 = (((@atomic (sv7).fld2) isa Bool) ? (!(__randint__() >= (true ? g4 : g6))) : (((g4 >= g4) ? "" : string(:b, g4, g5)) === g5))
            for i24 in 1:2
                ((!((true ? false : (v23 ? v23 : true)) && v23))) && continue
            end
        catch err22
            v25 = (v16, 0.0, g6)
            try
                v27 = (!("!aby" == (__randbool__() ? string(g5, (-9), "") : g5)))
            catch err26
                __obs__(((-5), "abyα!a"))
                @atomic sv7.fld2 -= g6
            end
            (false) && rethrow()
        finally
            if (!(9223372036854775806 < length(g5)))
                u28 = :c
            end
            __obs__(@isdefined(u28))
            __obs__(try; u28; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        (true) && rethrow()
    end
    v29 = __randbool__()
    try
        __obs__(g4)
        __obs__((v29 ? (try invoke(Base.compilerbarrier(:const, Int), Base.compilerbarrier(:const, Char), Base.compilerbarrier(:const, (g4, "!β∀1")), Base.compilerbarrier(:const, DataType), Base.compilerbarrier(:const, sv7)) catch __e; (:__thrown, nameof(typeof(__e))) end) : g5))
        try
            __obs__(4)
            v32 = S1(g6, (-8))
        catch err31
            if ((((v29 ? 5 : 9) ÷ (-1)) ÷ (-1)) <= min((-1), ((g4 + (-9223372036854775808)) + g6)))
                u33 = ((g5 != "") ? ((string(g5, g5) == g5) ? (-9) : (-5)) : (-931))
            end
            __obs__(@isdefined(u33))
            __obs__(try; u33; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
    catch err30
        for li34 in 1:3
            if li34 == 2
                __obs__(@isdefined(lx35))
                __obs__(try; (:__v, lx35); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx35 = v16
        end
    else
        v36 = Any[g5]
    finally
        for i37 in 1:3
            v38 = S1((((5.62 <= 0.01) ? fr8(g4, g4) : g4) + fr8(g4, ((-7) * g4))), (@atomic (sv7).fld3))
            ((__randbool__() === __randbool__())) && continue
        end
    end
    try
        try
            __obs__((__randbool__() ? "xαβ " : string(g4, (v29 ? (3 - g4) : g4), string(g5, :e))))
        catch err40
            @atomic sv7.fld2 += (364 + ((fr8((-10), 2) ÷ (-1)) - (@atomic (sv7).fld3)))
            for i41 in 1:0
                @atomic sv7.fld3 = (fr8((g6 % 1), (-5)) - (g6 * fr8(fr8(501, (-164)), g6)))
            end
            ((-8.32 != (f9(S1(g6, g4), "!🐛0xβx") - max(6.33, v16)))) && rethrow()
        end
        try
            v43 = fr8(((-9) + (@atomic (sv7).fld3)), (((false ? (-9223372036854775808) : g6) * fr8((-5), g6)) * ((v29 ? g6 : (-4)) % 3)))
        catch err42
            local t44::Int64 = (-508)
            v45 = S1(t44, (length(g5) + (@atomic (sv7).fld2)))
        finally
            for li46 in 1:3
                if li46 == 2
                    __obs__(@isdefined(lx47))
                    __obs__(try; (:__v, lx47); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx47 = f9(S1((__randbool__() ? (v29 ? g4 : g6) : li46), length(g5)), string((li46 isa Float64), g5, length(v15)), ([g6, li46])...)
            end
        end
    catch err39
        __obs__(:a)
    finally
        v49 = ((p48) -> (v16 = (v16 * (((v29 || false) ? f9(sv7, g5) : v16) - p48)); v16))
    end
    v50 = fr8(__randint__(), fr8((@atomic (sv7).fld3), (@atomic (sv7).fld3)))
    for i51 in 1:__randrange__(0, 4)
        ((fr8((-2), abs(g6)) > v50)) && continue
    end
    v53 = ((p52) -> fr8((v50 ÷ 2), length(g5)))
    v54 = [g6]
    try; v54[get(v54, v50, (((@atomic (sv7).fld3) * (v50 * v50)) ÷ 1))] = get(v54, (false ? fr8((g6 * (-400)), max(g4, v50)) : (-7)), (@atomic (sv7).fld2)); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    v55 = :b
    __obs__(v55)
    __obs__(v54)
    __obs__((try v53(0.0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v50)
    __obs__(v29)
    __obs__((try v18(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v16)
    __obs__(v15)
    __obs__(sv7)
    __obs__(g6)
    __obs__(g5)
    __obs__(g4)
end

```

## Original program

```julia
const __LCG__ = Ref{UInt64}(0x0000000037737832)
__randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
__randint__() = __randu__() % Int64
__randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
__randbool__() = __randu__() % Bool
__randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
mutable struct S1
    @atomic fld2::Int64
    @atomic fld3::Int64
end
global g4::Int64 = 8
g5 = "xy "
const g6 = (5 * __randint__())
sv7 = S1((-1), g4)
function fr8(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr8(n - 1, acc + (-531))
end
function f9(a10, a11, va12...; kw13 = 2, kw14 = -3)
    nothing
    return __randfloat__()
end
v15 = [8.31, -6.48]
let
    v16 = f9(S1((-9), (-927)), "!!xbx0", ; kw13 = min(length(v15), g6))
    @atomic sv7.fld3 = (@atomic (sv7).fld2)
    v18 = ((p17) -> (v16 = (v16 * v16); v16))
    try
        try
            __obs__((698 < fr8((@atomic (sv7).fld2), ((true ? g6 : g4) + ((-4) + (-2))))))
            try; v15[min((@atomic (sv7).fld2), g6)] = v16; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
        catch err20
            v21 = " αβ1"
        end
    catch err19
        try
            v23 = (((@atomic (sv7).fld2) isa Bool) ? (!(__randint__() >= (true ? g4 : g6))) : (((g4 >= g4) ? "" : string(:b, g4, g5)) === g5))
            for i24 in 1:2
                ((!((true ? false : (v23 ? v23 : true)) && v23))) && continue
            end
        catch err22
            v25 = (v16, 0.0, g6)
            try
                v27 = (!("!aby" == (__randbool__() ? string(g5, (-9), "") : g5)))
            catch err26
                __obs__(((-5), "abyα!a"))
                @atomic sv7.fld2 -= g6
            end
            (false) && rethrow()
        finally
            if (!(9223372036854775806 < length(g5)))
                u28 = :c
            end
            __obs__(@isdefined(u28))
            __obs__(try; u28; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        (true) && rethrow()
    end
    v29 = __randbool__()
    try
        __obs__(g4)
        __obs__((v29 ? (try invoke(Base.compilerbarrier(:const, Int), Base.compilerbarrier(:const, Char), Base.compilerbarrier(:const, (g4, "!β∀1")), Base.compilerbarrier(:const, DataType), Base.compilerbarrier(:const, sv7)) catch __e; (:__thrown, nameof(typeof(__e))) end) : g5))
        try
            __obs__(4)
            v32 = S1(g6, (-8))
        catch err31
            if ((((v29 ? 5 : 9) ÷ (-1)) ÷ (-1)) <= min((-1), ((g4 + (-9223372036854775808)) + g6)))
                u33 = ((g5 != "") ? ((string(g5, g5) == g5) ? (-9) : (-5)) : (-931))
            end
            __obs__(@isdefined(u33))
            __obs__(try; u33; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
    catch err30
        for li34 in 1:3
            if li34 == 2
                __obs__(@isdefined(lx35))
                __obs__(try; (:__v, lx35); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx35 = v16
        end
    else
        v36 = Any[g5]
    finally
        for i37 in 1:3
            v38 = S1((((5.62 <= 0.01) ? fr8(g4, g4) : g4) + fr8(g4, ((-7) * g4))), (@atomic (sv7).fld3))
            ((__randbool__() === __randbool__())) && continue
        end
    end
    try
        try
            __obs__((__randbool__() ? "xαβ " : string(g4, (v29 ? (3 - g4) : g4), string(g5, :e))))
        catch err40
            @atomic sv7.fld2 += (364 + ((fr8((-10), 2) ÷ (-1)) - (@atomic (sv7).fld3)))
            for i41 in 1:0
                @atomic sv7.fld3 = (fr8((g6 % 1), (-5)) - (g6 * fr8(fr8(501, (-164)), g6)))
            end
            ((-8.32 != (f9(S1(g6, g4), "!🐛0xβx") - max(6.33, v16)))) && rethrow()
        end
        try
            v43 = fr8(((-9) + (@atomic (sv7).fld3)), (((false ? (-9223372036854775808) : g6) * fr8((-5), g6)) * ((v29 ? g6 : (-4)) % 3)))
        catch err42
            local t44::Int64 = (-508)
            v45 = S1(t44, (length(g5) + (@atomic (sv7).fld2)))
        finally
            for li46 in 1:3
                if li46 == 2
                    __obs__(@isdefined(lx47))
                    __obs__(try; (:__v, lx47); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx47 = f9(S1((__randbool__() ? (v29 ? g4 : g6) : li46), length(g5)), string((li46 isa Float64), g5, length(v15)), ([g6, li46])...)
            end
        end
    catch err39
        __obs__(:a)
    finally
        v49 = ((p48) -> (v16 = (v16 * (((v29 || false) ? f9(sv7, g5) : v16) - p48)); v16))
    end
    v50 = fr8(__randint__(), fr8((@atomic (sv7).fld3), (@atomic (sv7).fld3)))
    for i51 in 1:__randrange__(0, 4)
        ((fr8((-2), abs(g6)) > v50)) && continue
    end
    v53 = ((p52) -> fr8((v50 ÷ 2), length(g5)))
    v54 = [g6]
    try; v54[get(v54, v50, (((@atomic (sv7).fld3) * (v50 * v50)) ÷ 1))] = get(v54, (false ? fr8((g6 * (-400)), max(g4, v50)) : (-7)), (@atomic (sv7).fld2)); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    v55 = :b
    __obs__(v55)
    __obs__(v54)
    __obs__((try v53(0.0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v50)
    __obs__(v29)
    __obs__((try v18(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v16)
    __obs__(v15)
    __obs__(sv7)
    __obs__(g6)
    __obs__(g5)
    __obs__(g4)
end

```
