# call_only_throw (call-call_only_throw-1dc96bf0)

- seed: `1785779695403700942`
- walk seed: `3082767985190167853`
- interp mode: `call`
- julia: `1.12.6`
- divergent observation index: 0
- ref exception: `none`  interp exception: `MethodError`

## Detail

```
f10/1: interp threw MethodError where the native call completed
MethodError: no method matching push!(::Bool, ::Float64)
The function `push!` exists, but no method is defined for this combination of argument types.

Closest candidates are:
  push!(::Any, ::Any, !Matched::Any)
   @ Base abstractarray.jl:3560
  push!(::Any, ::Any, !Matched::Any, !Matched::Any...)
   @ Base abstractarray.jl:3561
  push!(!Matched::Base.Nowhere, ::Any)
   @ Base array.jl:1862
  ...


Stacktrace:
  [1] macro expansion
    @ ./some.jl:158 [inlined]
  [2] native_call
    @ /home/user/JuliaInterpreter.jl/src/interpret.jl:280 [inlined]
  [3] evaluate_call!(interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, fargs::Vector{Any}, enter_generated::Bool)
    @ JuliaInterpreter /home/user/JuliaInterpreter.jl/src/interpret.jl:451
  [4] evaluate_call!(interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, call_expr::Expr, enter_generated::Bool)
    @ JuliaInterpreter /home/user/JuliaInterpreter.jl/src/interpret.jl:329
  [5] evaluate_call!(interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, call_expr::Expr)
    @ JuliaInterpreter /home/user/JuliaInterpreter.jl/src/interpret.jl:322
  [6] eval_rhs(interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, node::Expr)
    @ JuliaInterpreter /home/user/JuliaInterpreter.jl/src/interpret.jl:631
  [7] step_expr!(interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, node::Any, istoplevel::Bool)
    @ JuliaInterpreter /home/user/JuliaInterpreter.jl/src/interpret.jl:919
  [8] step_expr!(interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, istoplevel::Bool)
    @ JuliaInterpreter /home/user/JuliaInterpreter.jl/src/interpret.jl:987
  [9] finish!
    @ /home/user/JuliaInterpreter.jl/src/commands.jl:14 [inlined]
 [10] debug_command(interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, cmd::Symbol, rootistoplevel::Bool; line::Nothing)
    @ JuliaInterpreter /home/user/JuliaInterpreter.jl/src/commands.jl:753
 [11] debug_command
    @ /home/user/JuliaInterpreter.jl/src/commands.jl:639 [inlined]
 [12] walkframe!(rng::Random.Xoshiro, interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, maxcmds::Int64, bpd::Nothing)
    @ Main.FuzzJI /home/user/JuliaInterpreter.jl/fuzz/src/stepfuzz.jl:300
 [13] walkframe!
    @ /home/user/JuliaInterpreter.
```

## Shrunk program

```julia
struct S1
    fld2::Vector
    fld3::Symbol
end
global g4::Int64 = (-7)
g5 = g4
g6 = ((((-0.0 - -7.51) * -2.18) / 6.04) - (-Inf / ((" a0yα" isa String) ? (true ? -5.34 : 0.0) : (1.68 - 2.2250738585072014e-308))))
function f7(; kw8 = 5, kw9 = 1)
    __obs__(0.02)
    return S1([g6], :a)
end
function f10(a11)
    try; a11[(3 * ((-9) * g4))] = 1.5; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    if ("11" < (false ? "🐛∀b∀a" : string((6 - g4), :d, :b)))
        global g4 = (g4 - (-1))
        v12 = f7(; kw8 = g5, kw9 = max(g5, ((true && true) ? (g5 - g5) : length(a11))))
    else
        local t13::Float64 = g6
        push!(a11, 8.03)
        __obs__(:c)
    end
    if (g6 != g6)
        global g5 = (-8)
        __obs__((g5, "0α1"))
    else
        ((("🐛1!y" == "0!ax") ? ((abs(g4) * g4) isa String) : (g5 isa String))) && return g6
    end
    return (g6 - g6)
end
function fr14(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr14(n - 1, acc + abs((-3)))
end
function fr14(a15::S1, a16::Int64)
    nothing
    return g6
end
let
    v17 = f7(; kw8 = (("🐛b 🐛β!" == "") ? g4 : ((g4 ÷ 2) + (true ? g4 : g5))), kw9 = (-1))
    v19 = ((p18) -> "ax∀0αy")
    let l20 = (true === ("yb01🐛b" != "yyxbb0")), l21 = (v17).fld3
        try
            __obs__((v17).fld3)
            __obs__(f10((v17).fld2))
        catch err22
            if ("β!β0🐛β" < string(((!false) && (5 != g4)), ""))
                __obs__((max(0.03, f10([g6, 4.21])) - (g4 * ((5 - g4) * g5))))
            end
            for li23 in 1:2
                if li23 == 2
                    __obs__(@isdefined(lx24))
                    __obs__(try; (:__v, lx24); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx24 = 10
            end
        else
            for li25 in 1:3
                if li25 == 2
                    __obs__(@isdefined(lx26))
                    __obs__(try; (:__v, lx26); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx26 = 448
            end
        end
        global g5 = (-1)
    end
    __obs__(g4)
    __obs__(((-6) + (g4 + 6)))
    __obs__(min(g4, g4))
    __obs__((try v19(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v17)
    __obs__(g6)
    __obs__(g5)
    __obs__(g4)
end

```

## Original program

```julia
struct S1
    fld2::Vector
    fld3::Symbol
end
global g4::Int64 = (-7)
g5 = g4
g6 = ((((-0.0 - -7.51) * -2.18) / 6.04) - (-Inf / ((" a0yα" isa String) ? (true ? -5.34 : 0.0) : (1.68 - 2.2250738585072014e-308))))
function f7(; kw8 = 5, kw9 = 1)
    __obs__(0.02)
    return S1([g6], :a)
end
function f10(a11)
    try; a11[(3 * ((-9) * g4))] = 1.5; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end
    if ("11" < (false ? "🐛∀b∀a" : string((6 - g4), :d, :b)))
        global g4 = (g4 - (-1))
        v12 = f7(; kw8 = g5, kw9 = max(g5, ((true && true) ? (g5 - g5) : length(a11))))
    else
        local t13::Float64 = g6
        push!(a11, 8.03)
        __obs__(:c)
    end
    if (g6 != g6)
        global g5 = (-8)
        __obs__((g5, "0α1"))
    else
        ((("🐛1!y" == "0!ax") ? ((abs(g4) * g4) isa String) : (g5 isa String))) && return g6
    end
    return (g6 - g6)
end
function fr14(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr14(n - 1, acc + abs((-3)))
end
function fr14(a15::S1, a16::Int64)
    nothing
    return g6
end
let
    v17 = f7(; kw8 = (("🐛b 🐛β!" == "") ? g4 : ((g4 ÷ 2) + (true ? g4 : g5))), kw9 = (-1))
    v19 = ((p18) -> "ax∀0αy")
    let l20 = (true === ("yb01🐛b" != "yyxbb0")), l21 = (v17).fld3
        try
            __obs__((v17).fld3)
            __obs__(f10((v17).fld2))
        catch err22
            if ("β!β0🐛β" < string(((!false) && (5 != g4)), ""))
                __obs__((max(0.03, f10([g6, 4.21])) - (g4 * ((5 - g4) * g5))))
            end
            for li23 in 1:2
                if li23 == 2
                    __obs__(@isdefined(lx24))
                    __obs__(try; (:__v, lx24); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx24 = 10
            end
        else
            for li25 in 1:3
                if li25 == 2
                    __obs__(@isdefined(lx26))
                    __obs__(try; (:__v, lx26); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx26 = 448
            end
        end
        global g5 = (-1)
    end
    __obs__(g4)
    __obs__(((-6) + (g4 + 6)))
    __obs__(min(g4, g4))
    __obs__((try v19(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v17)
    __obs__(g6)
    __obs__(g5)
    __obs__(g4)
end

```
