# value_divergence (value_divergence-142a17f7)

- seed: `1001330`
- interp mode: `rec`
- julia: `1.12.6`
- divergent observation index: 11
- ref exception: `none`  interp exception: `none`

## Detail

```
obs[11]: ref=(:__thrown, :MethodError) interp=(:__thrown, :UndefVarError)
```

## Shrunk program

```julia
g1 = ((("🐛01y" != " 1x") && ((-2) === (-5))) ? 9 : 4)
g2 = -2.49
function fr3(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr3(n - 1, acc + 6)
end
function fr4(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr4(n - 1, acc + (-3))
end
function fr4(a5::Bool, a6::Int64)
    nothing
    return 6
end
function fr7(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr7(n - 1, acc + min(acc, acc))
end
function fr7(a8::String, a9::Int64)
    nothing
    return 6
end
v10 = Set{Bool}([true])
v11 = ((fr4(false, g1) + ((g1 - (-10)) * fr4(g1, g1))) != length(v10))
let
    v12 = fr7(fr7(string((v11 || v11), (v11 ? "ya1" : "x")), fr4((g2 <= g2), ((-2) + (-734)))), length(v10))
    __obs__([16, 6])
    v14 = ((p13) -> -3.25)
    v15 = (!((("b!00ay" === "αaβ") isa Float64) && (fr4(v12, 10) > (v12 - v12))))
    __obs__(v10)
    global g2 = g2
    if (!v11)
        v12 = min(g1, ((-10) + v12))
        if ((!((true ? v15 : v11) || v11)) && v11)
            for i16 in 1:4
                global v11 = v15
            end
        end
        if ("y β∀1∀" === "")
            global g2 = g2
        end
    else
        let l17 = (((("" < "yxα🐛x") ? g2 : -2.92) * g1) - fr7(((g1 + 0) * ((-7) * 162)), (v12 * (v15 ? 2 : (-8))))), l18 = ((-4) - (-1))
            l18 = ((-742) - (-3))
        end
    end
    for i19 in 1:4
        if (false ? (-0.84 < g2) : ("" < " b"))
            u20 = (4.73 != (g2 * ((g2 / g2) / (v15 ? 7.78 : g2))))
        end
        __obs__(@isdefined(u20))
        __obs__(try; u20; catch __e; (:__undef, nameof(typeof(__e))) end)
    end
    __obs__((try Core._call_latest(:b) catch __e; (:__thrown, nameof(typeof(__e))) end))
    push!(v10, ((((g2 - 1) - (g1 * v12)) / 9.75) isa Bool))
    global g1 = fr4(((("β🐛yb0" === " ya0🐛") || (v11 && v11)) ? (!(!v11)) : ((v12 + v12) != length(v10))), g1)
    if (((v11 ? (g2 + g2) : (2.01 + g2)) >= g2) && v15)
        v21 = in(v11, v10)
        v23 = Int64[(9223372036854775806 * (-870)) for c22 in 1:2 if true]
        global g1 = ((((g1 - g1) ÷ (-3)) - (fr7(g1, v12) * (v12 - v12))) ÷ 7)
    end
    __obs__(v15)
    __obs__((try v14(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v12)
    __obs__(v11)
    __obs__(v10)
    __obs__(g2)
    __obs__(g1)
end

```

## Original program

```julia
g1 = ((("🐛01y" != " 1x") && ((-2) === (-5))) ? 9 : 4)
g2 = -2.49
function fr3(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr3(n - 1, acc + 6)
end
function fr4(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr4(n - 1, acc + (-3))
end
function fr4(a5::Bool, a6::Int64)
    nothing
    return 6
end
function fr7(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr7(n - 1, acc + min(acc, acc))
end
function fr7(a8::String, a9::Int64)
    nothing
    return 6
end
v10 = Set{Bool}([true])
v11 = ((fr4(false, g1) + ((g1 - (-10)) * fr4(g1, g1))) != length(v10))
let
    v12 = fr7(fr7(string((v11 || v11), (v11 ? "ya1" : "x")), fr4((g2 <= g2), ((-2) + (-734)))), length(v10))
    __obs__([16, 6])
    v14 = ((p13) -> -3.25)
    v15 = (!((("b!00ay" === "αaβ") isa Float64) && (fr4(v12, 10) > (v12 - v12))))
    __obs__(v10)
    global g2 = g2
    if (!v11)
        v12 = min(g1, ((-10) + v12))
        if ((!((true ? v15 : v11) || v11)) && v11)
            for i16 in 1:4
                global v11 = v15
            end
        end
        if ("y β∀1∀" === "")
            global g2 = g2
        end
    else
        let l17 = (((("" < "yxα🐛x") ? g2 : -2.92) * g1) - fr7(((g1 + 0) * ((-7) * 162)), (v12 * (v15 ? 2 : (-8))))), l18 = ((-4) - (-1))
            l18 = ((-742) - (-3))
        end
    end
    for i19 in 1:4
        if (false ? (-0.84 < g2) : ("" < " b"))
            u20 = (4.73 != (g2 * ((g2 / g2) / (v15 ? 7.78 : g2))))
        end
        __obs__(@isdefined(u20))
        __obs__(try; u20; catch __e; (:__undef, nameof(typeof(__e))) end)
    end
    __obs__((try Core._call_latest(:b) catch __e; (:__thrown, nameof(typeof(__e))) end))
    push!(v10, ((((g2 - 1) - (g1 * v12)) / 9.75) isa Bool))
    global g1 = fr4(((("β🐛yb0" === " ya0🐛") || (v11 && v11)) ? (!(!v11)) : ((v12 + v12) != length(v10))), g1)
    if (((v11 ? (g2 + g2) : (2.01 + g2)) >= g2) && v15)
        v21 = in(v11, v10)
        v23 = Int64[(9223372036854775806 * (-870)) for c22 in 1:2 if true]
        global g1 = ((((g1 - g1) ÷ (-3)) - (fr7(g1, v12) * (v12 - v12))) ÷ 7)
    end
    __obs__(v15)
    __obs__((try v14(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v12)
    __obs__(v11)
    __obs__(v10)
    __obs__(g2)
    __obs__(g1)
end

```
