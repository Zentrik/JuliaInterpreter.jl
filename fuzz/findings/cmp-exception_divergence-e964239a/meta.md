# exception_divergence (cmp-exception_divergence-e964239a)

- seed: `1200050`
- interp mode: `cmp`
- julia: `1.11.9`
- divergent observation index: 0
- ref exception: `ErrorException`  interp exception: `ArgumentError`

## Detail

```
ref threw ErrorException (syntax: `global fuel10`: fuel10 is a local variable in its enclosing scope); interp threw ArgumentError (ArgumentError: lowering returned an error, $(Expr(:error, "`global fuel10`: fuel10 is a local variable in its enclosing scope")))
```

## Shrunk program

```julia
struct S1
    fld2::Int64
end
g3 = (-6)
g4 = 1.74
g5 = :b
function fr6(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr6(n - 1, acc + ((("🐛" != string(n, g3)) ? ((9 - (-10)) + n) : min((n - 9223372036854775807), (acc - n))) - n))
end
function fr6(a7::S1, a8::Int64)
    nothing
    return ((a7).fld2 * (((a8 - g3) - (true ? (-7) : a8)) - (-10)))
end
__obs__(((((-8.46 * g4) / (g4 / g4)) / max(g4, g4)) * (((9.97 - -2.5) - (g4 - 4)) / abs(g4))))
v9 = fr6(S1(g3), fr6((fr6(g3, 3) % 1), fr6(fr6(S1(g3), g3), fr6(9223372036854775806, g3))))
let
    fuel10 = 4
    while true && (fuel10 > 0)
        global fuel10 -= 1
        if false
            v11 = (g4 / (g4 / g3))
            if (fr6(S1((v9 - (-2))), fr6(v9, fr6(S1(g3), (-9)))) != fr6(S1(g3), fr6(S1(v9), (-688))))
                ((!(!((!true) === (true || false))))) && break
            end
        end
        __obs__(true)
        __obs__((string(:c, fr6((true ? 3 : g3), (g3 - (-4)))) isa Int64))
    end
    v12 = (g4, 9.01)
    v12 = v12
    fuel13 = 3
    while (("0b🐛" < string("", g5)) === (!(true && ("β" === "αa")))) && (fuel13 > 0)
        global fuel13 -= 1
        v15 = ((p14) -> (((g4 / (-9)) - g4) / fr6(S1(0), g3)))
        v16 = [v9, g3]
    end
    v17 = ((string(:e, "1yα") < "0y") ? g3 : fr6(S1(v9), v9))
    v18 = 0.78
    __obs__(v18)
    __obs__(v17)
    __obs__(v12)
    __obs__(v9)
    __obs__(g5)
    __obs__(g4)
    __obs__(g3)
end

```

## Original program

```julia
struct S1
    fld2::Int64
end
g3 = (-6)
g4 = 1.74
g5 = :b
function fr6(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr6(n - 1, acc + ((("🐛" != string(n, g3)) ? ((9 - (-10)) + n) : min((n - 9223372036854775807), (acc - n))) - n))
end
function fr6(a7::S1, a8::Int64)
    nothing
    return ((a7).fld2 * (((a8 - g3) - (true ? (-7) : a8)) - (-10)))
end
__obs__(((((-8.46 * g4) / (g4 / g4)) / max(g4, g4)) * (((9.97 - -2.5) - (g4 - 4)) / abs(g4))))
v9 = fr6(S1(g3), fr6((fr6(g3, 3) % 1), fr6(fr6(S1(g3), g3), fr6(9223372036854775806, g3))))
let
    fuel10 = 4
    while true && (fuel10 > 0)
        global fuel10 -= 1
        if false
            v11 = (g4 / (g4 / g3))
            if (fr6(S1((v9 - (-2))), fr6(v9, fr6(S1(g3), (-9)))) != fr6(S1(g3), fr6(S1(v9), (-688))))
                ((!(!((!true) === (true || false))))) && break
            end
        end
        __obs__(true)
        __obs__((string(:c, fr6((true ? 3 : g3), (g3 - (-4)))) isa Int64))
    end
    v12 = (g4, 9.01)
    v12 = v12
    fuel13 = 3
    while (("0b🐛" < string("", g5)) === (!(true && ("β" === "αa")))) && (fuel13 > 0)
        global fuel13 -= 1
        v15 = ((p14) -> (((g4 / (-9)) - g4) / fr6(S1(0), g3)))
        v16 = [v9, g3]
    end
    v17 = ((string(:e, "1yα") < "0y") ? g3 : fr6(S1(v9), v9))
    v18 = 0.78
    __obs__(v18)
    __obs__(v17)
    __obs__(v12)
    __obs__(v9)
    __obs__(g5)
    __obs__(g4)
    __obs__(g3)
end

```
