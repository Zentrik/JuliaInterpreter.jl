# call_value_divergence (call-call_value_divergence-370cc475)

- seed: `1785779695400700433`
- walk seed: `7067809865547766385`
- interp mode: `call`
- julia: `1.12.6`
- divergent observation index: 1
- ref exception: `none`  interp exception: `none`

## Detail

```
f16/1: native=(:__thrown, :UndefVarError) interp=(:__thrown, :ArgumentError)
```

## Shrunk program

```julia
mutable struct S1
    fld2::Function
end
mutable struct S3
    @atomic fld4::Function
    fld5::Int64
end
g6 = :c
global g7::Int64 = 2
sv8 = S1(((p9) -> (max((min((-307), 8) - ((-8) + p9)), (9223372036854775806 * (true ? p9 : 159))) - p9)))
sv10 = S3(((p11) -> ((false ? -2.5 : min((-0.58 / (-1)), (true ? 6.59 : 0.0))) + 5)), g7)
function f12(va13...)
    fuel14 = 3
    while ((((false ? 0.2 : -3.86) + -9.97) <= -2.3) || true) && (fuel14 > 0)
        fuel14 -= 1
        global g7 = (-8)
        v15 = [4.08]
        __obs__(g6)
    end
    ((((sv10).fld5 + abs((true ? g7 : g7))) >= (sv10).fld5)) && return (try (g7 ÷ g7) catch __e; (:__thrown, nameof(typeof(__e))) end)
    return :c
end
function f16(va17...)
    v18 = S1((@atomic (sv10).fld4))
    v20 = Float64[-1.43 for c19 in 1:2 if (!(((g7 + g7) % 3) != ((2 - c19) % 2)))]
    return (try Core._svec_ref(Base.compilerbarrier(:const, g6)) catch __e; (:__thrown, nameof(typeof(__e))) end)
end
let
    if (f12((0.0 / g7)) === :b)
        v21 = [-1.87]
        if ((@atomic (sv10).fld4) isa AbstractString)
            sv10.fld5 = ((((sv10).fld5 isa Number) ? ((false ? g7 : (-4)) - abs(g7)) : ((sv10).fld5 - g7)) - (5 - (-1)))
            global g7 = 6
        else
            push!(v21, -5.78)
            global sv8 = S1(((p22) -> ((g7 <= p22) ? false : (-3.25 <= 4.85))))
        end
        sv8.fld2 = (sv8).fld2
    end
    if true
        fuel23 = 2
        while false && (fuel23 > 0)
            fuel23 -= 1
            v24 = (((string("aa1!1b", "∀bb !!") != "🐛") ? g7 : (sv10).fld5) - ((g7 ÷ 3) * ((0 - g7) + (g7 + (-2)))))
        end
        fuel25 = 2
        while (g7 < g7) && (fuel25 > 0)
            fuel25 -= 1
            __obs__(true)
            __obs__((min(abs(0.27), (-2.5 * (true ? 5.9 : -0.0))) + ((-3.28 + (sv10).fld5) + g7)))
        end
    end
    v26 = Dict{Bool, String}(false => "x! !")
    al27 = sv8
    __obs__((g7, "🐛α! x1"))
    @atomic sv10.fld4 = (sv8).fld2
    __obs__(al27)
    __obs__(v26)
    __obs__(sv10)
    __obs__(sv8)
    __obs__(g7)
    __obs__(g6)
end

```

## Original program

```julia
mutable struct S1
    fld2::Function
end
mutable struct S3
    @atomic fld4::Function
    fld5::Int64
end
g6 = :c
global g7::Int64 = 2
sv8 = S1(((p9) -> (max((min((-307), 8) - ((-8) + p9)), (9223372036854775806 * (true ? p9 : 159))) - p9)))
sv10 = S3(((p11) -> ((false ? -2.5 : min((-0.58 / (-1)), (true ? 6.59 : 0.0))) + 5)), g7)
function f12(va13...)
    fuel14 = 3
    while ((((false ? 0.2 : -3.86) + -9.97) <= -2.3) || true) && (fuel14 > 0)
        fuel14 -= 1
        global g7 = (-8)
        v15 = [4.08]
        __obs__(g6)
    end
    ((((sv10).fld5 + abs((true ? g7 : g7))) >= (sv10).fld5)) && return (try (g7 ÷ g7) catch __e; (:__thrown, nameof(typeof(__e))) end)
    return :c
end
function f16(va17...)
    v18 = S1((@atomic (sv10).fld4))
    v20 = Float64[-1.43 for c19 in 1:2 if (!(((g7 + g7) % 3) != ((2 - c19) % 2)))]
    return (try Core._svec_ref(Base.compilerbarrier(:const, g6)) catch __e; (:__thrown, nameof(typeof(__e))) end)
end
let
    if (f12((0.0 / g7)) === :b)
        v21 = [-1.87]
        if ((@atomic (sv10).fld4) isa AbstractString)
            sv10.fld5 = ((((sv10).fld5 isa Number) ? ((false ? g7 : (-4)) - abs(g7)) : ((sv10).fld5 - g7)) - (5 - (-1)))
            global g7 = 6
        else
            push!(v21, -5.78)
            global sv8 = S1(((p22) -> ((g7 <= p22) ? false : (-3.25 <= 4.85))))
        end
        sv8.fld2 = (sv8).fld2
    end
    if true
        fuel23 = 2
        while false && (fuel23 > 0)
            fuel23 -= 1
            v24 = (((string("aa1!1b", "∀bb !!") != "🐛") ? g7 : (sv10).fld5) - ((g7 ÷ 3) * ((0 - g7) + (g7 + (-2)))))
        end
        fuel25 = 2
        while (g7 < g7) && (fuel25 > 0)
            fuel25 -= 1
            __obs__(true)
            __obs__((min(abs(0.27), (-2.5 * (true ? 5.9 : -0.0))) + ((-3.28 + (sv10).fld5) + g7)))
        end
    end
    v26 = Dict{Bool, String}(false => "x! !")
    al27 = sv8
    __obs__((g7, "🐛α! x1"))
    @atomic sv10.fld4 = (sv8).fld2
    __obs__(al27)
    __obs__(v26)
    __obs__(sv10)
    __obs__(sv8)
    __obs__(g7)
    __obs__(g6)
end

```
