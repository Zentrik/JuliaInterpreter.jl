# julia_engine_divergence (julia-julia_engine_divergence-5ada7c05)

- seed: `6200909`
- interp mode: `rec`
- julia: `1.12.6`
- divergent observation index: 10
- ref exception: `none`  interp exception: `none`

## Detail

```
obs[10]: ref=(:__thrown, :UndefVarError) interp=(:__thrown, :ArgumentError)
```

## Shrunk program

```julia
struct S1
    fld2::Function
end
mutable struct S3
    @atomic fld4::Symbol
end
g5 = 0
g6 = ((-3) - (false ? g5 : ((abs(g5) * g5) % 2)))
const g7 = :e
function f8(a9 = 0)
    for i10 in 1:5
        v11 = S3(:e)
        ((!(false && (((-3.03 - i10) * -3.25) < ((1.5 + -5.25) + (7.26 + 9.18)))))) && break
        ((string((g5 % 2), g7) != (true ? string((g5 % 7), true, ("0αxα" isa Int64)) : ""))) && break
        __obs__((g5, "∀∀1ya!x"))
    end
    return S3(:d)
end
function f12()
    let l13 = :d
        ((-8.85 > max((((-4.89 / 1.7976931348623157e308) / (g6 * g6)) + 1.0), 2.84))) && return ((g6 == (g5 - (7 + 6))) ? 2.13 : (-7.02 * g5))
        (((7.82 != -5.06) ? ("1β" < "α! xa11") : ("" < "aa🐛a1"))) && return (-1.49 / 4.74)
        v14 = (((((9223372036854775807 ÷ 2) * (0 - (-1))) + g6) < 6) ? (try Base.bitcast(Float64, Base.compilerbarrier(:const, g5)) catch __e; (:__thrown, nameof(typeof(__e))) end) : (try Core.invoke_in_world(Base.compilerbarrier(:const, g7)) catch __e; (:__thrown, nameof(typeof(__e))) end))
        v16 = S1(((p15) -> 3.81))
    end
    v17 = Dict{Int64, Symbol}(g6 => g7, g5 => g7, 2 => g7)
    for i18 in 1:5
        v19 = S3(g7)
        __obs__([g6, g6, 8])
        for i20 in 1:3
            v21 = (g5 - 145)
        end
    end
    return -9.25
end
function f22(a23; kw24 = -2, kw25 = 2)
    __obs__([9, (-10), 9])
    __obs__((g6, a23))
    return ((p26) -> (kw25 = (kw25 + 0); kw25))
end
function f22(a27::Bool)
    nothing
    return ((!(1 < ((g5 + g5) ÷ 7))) ? ((g6 - (g5 - (-6))) * (((-1) - (a27 ? g6 : 7)) % (-3))) : (g5 ÷ 3))
end
function f28(a29, a30, a31)
    v32 = (try Core.modifyglobal!((@__MODULE__), Base.compilerbarrier(:const, :__probe_g_zzz), Base.compilerbarrier(:const, +), Base.compilerbarrier(:const, g6)) catch __e; (:__thrown, nameof(typeof(__e))) end)
    return S1(((p33) -> true))
end
function f34()
    v35 = f28(S3(:c), (true ? (1.5 - (g6 - g6)) : 8.12), (g7, g6, -0.6))
    v36 = (try Core.Intrinsics.neg_int(Base.compilerbarrier(:const, UInt8(0))) catch __e; (:__thrown, nameof(typeof(__e))) end)
    return g7
end
let
    __obs__(("x 🐛α🐛β∀0ay" isa String))
    v38 = Int64[((8 - ((string(2, "xxyy", c37) != string("bb🐛", " 1α!1", "xαbax!β")) ? 6 : g6)) - (5 * g6)) for c37 in 1:4]
    __obs__(f12())
    v39 = f28(f8(max(max(573, (g6 ÷ 1)), ((g6 + (-1)) ÷ (-3)))), f12(), (:a, g5, -4.09))
    __obs__((-3))
    for i40 in 1:1
        v41 = (g7, g5)
        __obs__(v38)
    end
    try; v38[g5] = ((((g5 + (g6 + g6)) - (g6 - g6)) * (g5 - ((-7) + g5))) + g5); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    try; v38[((max(g6, ((true ? g5 : g6) + g6)) + g5) % (-3))] = g5; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    __obs__((-2))
    if false
        u42 = (get(v38, max((("0αx!🐛b α!" < "! 1🐛αβ") ? max(1, g5) : g6), 173), (((false && true) ? 0 : g5) * (get(v38, 1, g5) ÷ 1))) + abs(max(((g6 === (-15)) ? 7 : (9 * (-1))), (g5 + g6))))
    end
    __obs__(@isdefined(u42))
    __obs__(try; u42; catch __e; (:__undef, nameof(typeof(__e))) end)
    push!(v38, abs(g5))
    v43 = (try Core._svec_ref(Base.compilerbarrier(:const, g6), Base.compilerbarrier(:const, v38), Base.compilerbarrier(:const, Int32(7))) catch __e; (:__thrown, nameof(typeof(__e))) end)
    __obs__(v43)
    __obs__(v39)
    __obs__(v38)
    __obs__(g7)
    __obs__(g6)
    __obs__(g5)
end

```

## Original program

```julia
struct S1
    fld2::Function
end
mutable struct S3
    @atomic fld4::Symbol
end
g5 = 0
g6 = ((-3) - (false ? g5 : ((abs(g5) * g5) % 2)))
const g7 = :e
function f8(a9 = 0)
    for i10 in 1:5
        v11 = S3(:e)
        ((!(false && (((-3.03 - i10) * -3.25) < ((1.5 + -5.25) + (7.26 + 9.18)))))) && break
        ((string((g5 % 2), g7) != (true ? string((g5 % 7), true, ("0αxα" isa Int64)) : ""))) && break
        __obs__((g5, "∀∀1ya!x"))
    end
    return S3(:d)
end
function f12()
    let l13 = :d
        ((-8.85 > max((((-4.89 / 1.7976931348623157e308) / (g6 * g6)) + 1.0), 2.84))) && return ((g6 == (g5 - (7 + 6))) ? 2.13 : (-7.02 * g5))
        (((7.82 != -5.06) ? ("1β" < "α! xa11") : ("" < "aa🐛a1"))) && return (-1.49 / 4.74)
        v14 = (((((9223372036854775807 ÷ 2) * (0 - (-1))) + g6) < 6) ? (try Base.bitcast(Float64, Base.compilerbarrier(:const, g5)) catch __e; (:__thrown, nameof(typeof(__e))) end) : (try Core.invoke_in_world(Base.compilerbarrier(:const, g7)) catch __e; (:__thrown, nameof(typeof(__e))) end))
        v16 = S1(((p15) -> 3.81))
    end
    v17 = Dict{Int64, Symbol}(g6 => g7, g5 => g7, 2 => g7)
    for i18 in 1:5
        v19 = S3(g7)
        __obs__([g6, g6, 8])
        for i20 in 1:3
            v21 = (g5 - 145)
        end
    end
    return -9.25
end
function f22(a23; kw24 = -2, kw25 = 2)
    __obs__([9, (-10), 9])
    __obs__((g6, a23))
    return ((p26) -> (kw25 = (kw25 + 0); kw25))
end
function f22(a27::Bool)
    nothing
    return ((!(1 < ((g5 + g5) ÷ 7))) ? ((g6 - (g5 - (-6))) * (((-1) - (a27 ? g6 : 7)) % (-3))) : (g5 ÷ 3))
end
function f28(a29, a30, a31)
    v32 = (try Core.modifyglobal!((@__MODULE__), Base.compilerbarrier(:const, :__probe_g_zzz), Base.compilerbarrier(:const, +), Base.compilerbarrier(:const, g6)) catch __e; (:__thrown, nameof(typeof(__e))) end)
    return S1(((p33) -> true))
end
function f34()
    v35 = f28(S3(:c), (true ? (1.5 - (g6 - g6)) : 8.12), (g7, g6, -0.6))
    v36 = (try Core.Intrinsics.neg_int(Base.compilerbarrier(:const, UInt8(0))) catch __e; (:__thrown, nameof(typeof(__e))) end)
    return g7
end
let
    __obs__(("x 🐛α🐛β∀0ay" isa String))
    v38 = Int64[((8 - ((string(2, "xxyy", c37) != string("bb🐛", " 1α!1", "xαbax!β")) ? 6 : g6)) - (5 * g6)) for c37 in 1:4]
    __obs__(f12())
    v39 = f28(f8(max(max(573, (g6 ÷ 1)), ((g6 + (-1)) ÷ (-3)))), f12(), (:a, g5, -4.09))
    __obs__((-3))
    for i40 in 1:1
        v41 = (g7, g5)
        __obs__(v38)
    end
    try; v38[g5] = ((((g5 + (g6 + g6)) - (g6 - g6)) * (g5 - ((-7) + g5))) + g5); catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    try; v38[((max(g6, ((true ? g5 : g6) + g6)) + g5) % (-3))] = g5; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    __obs__((-2))
    if false
        u42 = (get(v38, max((("0αx!🐛b α!" < "! 1🐛αβ") ? max(1, g5) : g6), 173), (((false && true) ? 0 : g5) * (get(v38, 1, g5) ÷ 1))) + abs(max(((g6 === (-15)) ? 7 : (9 * (-1))), (g5 + g6))))
    end
    __obs__(@isdefined(u42))
    __obs__(try; u42; catch __e; (:__undef, nameof(typeof(__e))) end)
    push!(v38, abs(g5))
    v43 = (try Core._svec_ref(Base.compilerbarrier(:const, g6), Base.compilerbarrier(:const, v38), Base.compilerbarrier(:const, Int32(7))) catch __e; (:__thrown, nameof(typeof(__e))) end)
    __obs__(v43)
    __obs__(v39)
    __obs__(v38)
    __obs__(g7)
    __obs__(g6)
    __obs__(g5)
end

```
