# call_value_divergence (call-call_value_divergence-8a9f8dee)

- seed: `1785779695400001373`
- walk seed: `2501281150161429089`
- interp mode: `call`
- julia: `1.12.6`
- divergent observation index: 1
- ref exception: `none`  interp exception: `none`

## Detail

```
f8/1; kw=[:kw10]: native=(:__thrown, :TypeError) interp=(:__thrown, :ErrorException)
```

## Shrunk program

```julia
mutable struct S1
    @atomic fld2::Function
    @atomic fld3::Symbol
    @atomic fld4::Vector
end
global g5::Int64 = ((0 * (-5)) + ((((-3) - (-2)) == ((-1) - 9223372036854775807)) ? (-8) : 10))
sv6 = S1(((p7) -> true), :b, [-6.72, -2.51, 1.32])
function f8(a9; kw10 = -4, kw11 = -3)
    nothing
    return (try Base.checked_udiv_int(Base.compilerbarrier(:const, kw10), Base.compilerbarrier(:const, kw10)) catch __e; (:__thrown, nameof(typeof(__e))) end)
end
function f8(a12::Int64)
    nothing
    return (-8.57 * 9.17)
end
v13 = sv6
let
    v14 = S1((@atomic (v13).fld2), (@atomic (sv6).fld3), (@atomic (v13).fld4))
    let l15 = (max((1.5 - -2.74), 0.99) - 4.37), l16 = (@atomic (v13).fld3)
        let l17 = g5, l18 = ((l15 * (-0.0 - (l15 / 7))) / (true ? ((true ? l15 : l15) * (1.98 + 5.81)) : l15))
            v19 = S1((@atomic (v14).fld2), (@atomic (sv6).fld3), [l18, -4.98])
        end
        v20 = ("αy!b", l15, -1.93)
    end
    if ((true ? (false === ("!y∀b!" < "yy")) : ((9.72 isa Number) isa Integer)) && ((true && (!false)) && false))
        v21 = (false, -0.43)
        v22 = Any[false]
        v23 = (619 * 5)
    else
        if (!((-2.5 / g5) == ((-2.13 + -4.9) + 0.99)))
            u24 = :c
        end
        __obs__(@isdefined(u24))
        __obs__(try; u24; catch __e; (:__undef, nameof(typeof(__e))) end)
        for i25 in 1:1
            let l26 = (1.5 * (3.41 * -6.1)), l27 = :a
                (((((-0.83 * l26) * (2 % 7)) <= ((l26 - -3.69) * l26)) || (((!true) ? l26 : (0.1 / 8)) != l26))) && break
            end
            v29 = Float64[(-4.05 - c28) for c28 in 1:4]
        end
    end
    let l30 = (:d === (@atomic (v14).fld3)), l31 = false
        __obs__([g5])
        v34 = ((p32, p33) -> l30)
        __obs__(string((@atomic (v14).fld3), (@atomic (sv6).fld3)))
    end
    if ("βx" != "ayyx🐛")
        v35 = Dict{Char, String}('🐛' => "🐛0bx!", '∀' => "y1!🐛", ' ' => " β")
        v37 = S1(((p36) -> 8), (@atomic (v13).fld3), (@atomic (v14).fld4))
    else
        for li38 in 1:2
            if li38 == 2
                __obs__(@isdefined(lx39))
                __obs__(try; (:__v, lx39); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx39 = li38
        end
        if ((((0.1 != -0.0) || (false && false)) ? g5 : ((4 % (-3)) - g5)) === g5)
            if ((try setfieldonce!(Base.compilerbarrier(:const, Ref(1)), Base.compilerbarrier(:const, :x), Base.compilerbarrier(:const, 2), :not_atomic, :not_atomic) catch __e; (:__thrown, nameof(typeof(__e))) end) isa String)
                u40 = (-1)
            end
            __obs__(@isdefined(u40))
            __obs__(try; u40; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
    end
    __obs__(9.59)
    for i41 in 1:2
        v43 = Float64[8.76 for c42 in 1:1 if (c42 === 0)]
    end
    __obs__(((((false && true) || (false ? false : false)) ? g5 : ((v14 isa Integer) ? g5 : (g5 * 8))) - g5))
    __obs__(v14)
    __obs__(v13)
    __obs__(sv6)
    __obs__(g5)
end

```

## Original program

```julia
mutable struct S1
    @atomic fld2::Function
    @atomic fld3::Symbol
    @atomic fld4::Vector
end
global g5::Int64 = ((0 * (-5)) + ((((-3) - (-2)) == ((-1) - 9223372036854775807)) ? (-8) : 10))
sv6 = S1(((p7) -> true), :b, [-6.72, -2.51, 1.32])
function f8(a9; kw10 = -4, kw11 = -3)
    nothing
    return (try Base.checked_udiv_int(Base.compilerbarrier(:const, kw10), Base.compilerbarrier(:const, kw10)) catch __e; (:__thrown, nameof(typeof(__e))) end)
end
function f8(a12::Int64)
    nothing
    return (-8.57 * 9.17)
end
v13 = sv6
let
    v14 = S1((@atomic (v13).fld2), (@atomic (sv6).fld3), (@atomic (v13).fld4))
    let l15 = (max((1.5 - -2.74), 0.99) - 4.37), l16 = (@atomic (v13).fld3)
        let l17 = g5, l18 = ((l15 * (-0.0 - (l15 / 7))) / (true ? ((true ? l15 : l15) * (1.98 + 5.81)) : l15))
            v19 = S1((@atomic (v14).fld2), (@atomic (sv6).fld3), [l18, -4.98])
        end
        v20 = ("αy!b", l15, -1.93)
    end
    if ((true ? (false === ("!y∀b!" < "yy")) : ((9.72 isa Number) isa Integer)) && ((true && (!false)) && false))
        v21 = (false, -0.43)
        v22 = Any[false]
        v23 = (619 * 5)
    else
        if (!((-2.5 / g5) == ((-2.13 + -4.9) + 0.99)))
            u24 = :c
        end
        __obs__(@isdefined(u24))
        __obs__(try; u24; catch __e; (:__undef, nameof(typeof(__e))) end)
        for i25 in 1:1
            let l26 = (1.5 * (3.41 * -6.1)), l27 = :a
                (((((-0.83 * l26) * (2 % 7)) <= ((l26 - -3.69) * l26)) || (((!true) ? l26 : (0.1 / 8)) != l26))) && break
            end
            v29 = Float64[(-4.05 - c28) for c28 in 1:4]
        end
    end
    let l30 = (:d === (@atomic (v14).fld3)), l31 = false
        __obs__([g5])
        v34 = ((p32, p33) -> l30)
        __obs__(string((@atomic (v14).fld3), (@atomic (sv6).fld3)))
    end
    if ("βx" != "ayyx🐛")
        v35 = Dict{Char, String}('🐛' => "🐛0bx!", '∀' => "y1!🐛", ' ' => " β")
        v37 = S1(((p36) -> 8), (@atomic (v13).fld3), (@atomic (v14).fld4))
    else
        for li38 in 1:2
            if li38 == 2
                __obs__(@isdefined(lx39))
                __obs__(try; (:__v, lx39); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx39 = li38
        end
        if ((((0.1 != -0.0) || (false && false)) ? g5 : ((4 % (-3)) - g5)) === g5)
            if ((try setfieldonce!(Base.compilerbarrier(:const, Ref(1)), Base.compilerbarrier(:const, :x), Base.compilerbarrier(:const, 2), :not_atomic, :not_atomic) catch __e; (:__thrown, nameof(typeof(__e))) end) isa String)
                u40 = (-1)
            end
            __obs__(@isdefined(u40))
            __obs__(try; u40; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
    end
    __obs__(9.59)
    for i41 in 1:2
        v43 = Float64[8.76 for c42 in 1:1 if (c42 === 0)]
    end
    __obs__(((((false && true) || (false ? false : false)) ? g5 : ((v14 isa Integer) ? g5 : (g5 * 8))) - g5))
    __obs__(v14)
    __obs__(v13)
    __obs__(sv6)
    __obs__(g5)
end

```
