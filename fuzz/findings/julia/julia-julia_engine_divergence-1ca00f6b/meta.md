# julia_engine_divergence (julia-julia_engine_divergence-1ca00f6b)

- seed: `1201712`
- interp mode: `rec`
- julia: `1.12.6`
- divergent observation index: 1
- ref exception: `none`  interp exception: `none`

## Detail

```
obs[1]: ref=(:__thrown, :BoundsError) interp=(:__thrown, :ArgumentError)
```

## Shrunk program

```julia
const g1 = ((-4) * 2)
global g2::Int64 = g1
v3 = [g2]
let
    v4 = ((g2 ÷ (-3)) * get(v3, g2, abs((5 * g1))))
    local t5::Int64 = (((g2 + (v4 % 1)) % (-1)) * (-4))
    v6 = (0, "1🐛β", "0ba")
    v7 = g2
    v8 = -5.73
    __obs__((try Core._svec_ref() catch __e; (:__thrown, nameof(typeof(__e))) end))
    let l9 = (min(v8, v8) * (v8 + max(g1, v4))), l10 = (-2)
        try; v3[get(v3, (((false isa Any) ? min(t5, (-2)) : ((-4) + g1)) - (1 ÷ (-1))), (-8))] = 9; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    end
    __obs__((((!true) ? ((-0.33 + v8) != v8) : (false ? (4.16 < 1.14) : (true && false))) ? 2.89 : v8))
    fuel11 = 2
    while (((!(!false)) ? v8 : abs((v8 / 9223372036854775807))) isa AbstractString) && (fuel11 > 0)
        fuel11 -= 1
        v12 = (try Base.rint_llvm(Base.compilerbarrier(:const, 4.07)) catch __e; (:__thrown, nameof(typeof(__e))) end)
    end
    let l13 = (string(9223372036854775807, :b) == "!")
        v14 = (v7, (-10), v8)
    end
    __obs__(v8)
    __obs__(v7)
    __obs__(v6)
    __obs__(t5)
    __obs__(v4)
    __obs__(v3)
    __obs__(g2)
    __obs__(g1)
end

```

## Original program

```julia
const g1 = ((-4) * 2)
global g2::Int64 = g1
v3 = [g2]
let
    v4 = ((g2 ÷ (-3)) * get(v3, g2, abs((5 * g1))))
    local t5::Int64 = (((g2 + (v4 % 1)) % (-1)) * (-4))
    v6 = (0, "1🐛β", "0ba")
    v7 = g2
    v8 = -5.73
    __obs__((try Core._svec_ref() catch __e; (:__thrown, nameof(typeof(__e))) end))
    let l9 = (min(v8, v8) * (v8 + max(g1, v4))), l10 = (-2)
        try; v3[get(v3, (((false isa Any) ? min(t5, (-2)) : ((-4) + g1)) - (1 ÷ (-1))), (-8))] = 9; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    end
    __obs__((((!true) ? ((-0.33 + v8) != v8) : (false ? (4.16 < 1.14) : (true && false))) ? 2.89 : v8))
    fuel11 = 2
    while (((!(!false)) ? v8 : abs((v8 / 9223372036854775807))) isa AbstractString) && (fuel11 > 0)
        fuel11 -= 1
        v12 = (try Base.rint_llvm(Base.compilerbarrier(:const, 4.07)) catch __e; (:__thrown, nameof(typeof(__e))) end)
    end
    let l13 = (string(9223372036854775807, :b) == "!")
        v14 = (v7, (-10), v8)
    end
    __obs__(v8)
    __obs__(v7)
    __obs__(v6)
    __obs__(t5)
    __obs__(v4)
    __obs__(v3)
    __obs__(g2)
    __obs__(g1)
end

```
