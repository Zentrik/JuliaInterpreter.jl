# step_only_throw (step-step_only_throw-960a5d39)

- seed: `1785779695200300017`
- walk seed: `5311061205655927257`
- interp mode: `step`
- julia: `1.12.6`
- divergent observation index: 0
- ref exception: `none`  interp exception: `AssertionError`

## Detail

```
stepping threw where plain interpretation completed
AssertionError in step_expr! (interpret.jl:779): AssertionError: is_leaf(frame)

Stacktrace:
  [1] step_expr!(interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, node::Any, istoplevel::Bool)
    @ JuliaInterpreter /home/user/JuliaInterpreter.jl/src/interpret.jl:779
  [2] step_expr!
    @ /home/user/JuliaInterpreter.jl/src/interpret.jl:958 [inlined]
  [3] debug_command(interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, cmd::Symbol, rootistoplevel::Bool; line::Nothing)
    @ JuliaInterpreter /home/user/JuliaInterpreter.jl/src/commands.jl:660
  [4] debug_command
    @ /home/user/JuliaInterpreter.jl/src/commands.jl:639 [inlined]
  [5] walkframe!(rng::Random.Xoshiro, interp::JuliaInterpreter.RecursiveInterpreter, frame::JuliaInterpreter.Frame, maxcmds::Int64, bpd::Main.FuzzJI.BpDriver)
    @ Main.FuzzJI /home/user/JuliaInterpreter.jl/fuzz/src/stepfuzz.jl:300
  [6] step_program(src::String; walkseed::Int64, interp::JuliaInterpreter.RecursiveInterpreter, maxcmds::Int64, usebreakpoints::Bool)
    @ Main.FuzzJI /home/user/JuliaInterpreter.jl/fuzz/src/stepfuzz.jl:354
  [7] step_program
    @ /home/user/JuliaInterpreter.jl/fuzz/src/stepfuzz.jl:331 [inlined]
  [8] step_campaign(; n::Int64, baseseed::Int64, nstmts::Int64, outdir::String, journaldir::String, cfg::Cfg, progress::Int64, maxcmds::Int64, seeddisk::Bool, journalsync::Bool, usebreakpoints::Bool, doshrink::Bool, shrinkruns::Int64, shrinksecs::Float64)
    @ Main.FuzzJI /home/user/JuliaInterpreter.jl/fuzz/src/stepfuzz.jl:515
  [9] top-level scope
    @ /home/user/JuliaInterpreter.jl/fuzz/run.jl:199
 [10] include(mod::Module, _path::String)
    @ Base ./Base.jl:306
 [11] exec_options(opts::Base.JLOptions)
    @ Base ./client.jl:317
 [12] _start()
    @ Base ./client.jl:550
```

## Shrunk program

```julia
const __LCG__ = Ref{UInt64}(0x000000002876fa98)
__randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
__randint__() = __randu__() % Int64
__randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
__randbool__() = __randu__() % Bool
__randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
g1 = (-7.43 - __randint__())
g2 = "xaa"
function f3(a4::Float64, a5; kw6 = 4, kw7 = 2)
    nothing
    return kw6
end
function f8(a9)
    __obs__(false)
    ((((f3(g1, g2) ÷ 7) + (f3(g1, g1, ; kw6 = (-9223372036854775808), kw7 = a9) * (false ? a9 : a9))) != f3(min(max(-2.5, -1.9), __randfloat__()), (!(a9 isa Any))))) && return ((false || (!(a9 != 10))) || (!(!(false ? false : true))))
    fuel10 = 4
    while ((!(("" != g2) && (g1 >= g1))) ? (string("🐛b∀∀🐛∀", :b) isa Bool) : __randbool__()) && (fuel10 > 0)
        fuel10 -= 1
        fuel11 = 2
        while (-7.72 isa AbstractString) && (fuel11 > 0)
            fuel11 -= 1
            local t12::Float64 = g1
            v14 = ((p13) -> "x🐛y∀βa")
        end
        a9 = 736
    end
    return (f3(((5.41 + g1) * (false ? 463 : a9)), (:e, :a)) === __randrange__(1, 7))
end
function f8(a15::Bool)
    nothing
    return 6
end
function f16(a17::Vector)
    v19 = Int64[f3(g1, ((!(g2 != "")) ? true : (f3(g1, false) === (true ? (-1) : c18)))) for c18 in 1:3]
    v21 = Float64[((((c20 == (-7)) ? (1.7976931348623157e308 * 9.43) : 0.93) / __vtime__()) * (f3((-6.53 / g1), (-7)) + f3((g1 * 2), string(g2, true), ; kw7 = f3(-3.06, nothing)))) for c20 in 1:3]
    return f3(get(v21, ((:b === :c) ? f3(g1, g1) : __randint__()), get(v21, f3(g1, [398, (-10)]), abs(-9.36))), v19, ; kw6 = (-3), kw7 = 1)
end
v24 = ((p22, p23) -> max(((!false) ? 2 : f3(p23, g2)), (f3(-0.0, [g1]) + 4)))
try
    local t26::Float64 = (("!0∀0b " != string(g2, (10 - (-408)))) ? (abs((-9.19 * g1)) - (f3(g1, 4, ; kw7 = 1) + f16(Any[:c, false, g1]))) : (((g1 - g1) * 6.7) * (-7)))
catch err25
    v27 = ((-8), -8.77)
finally
    v28 = Dict{String, Symbol}()
end
v30 = Int64[f3(((!true) ? g1 : ((3.76 * -5.76) - (g1 + -2.5))), f3(-7.15, 8.43), ; kw6 = __randint__(), kw7 = __randrange__(1, 6)) for c29 in 1:2 if true]
let
    __obs__(:d)
    if ((try f16(Any[v24]) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Integer)
        al31 = v30
        v33 = Int64[f3((g1 + g1), "αy!") for c32 in 1:0]
        v34 = :c
    else
        fuel35 = 3
        while false && (fuel35 > 0)
            fuel35 -= 1
            push!(v30, f3((((g1 + (-5)) - (g1 / g1)) / g1), [0.0, -2.13, g1]))
        end
        v36 = Set{String}([g2])
    end
    let l37 = g2, l38 = (g1 * (((-4.69 + (-3)) * 0.0) + __randfloat__()))
        v39 = (:c, l37, (-6))
    end
    let l40 = string(__vtime__(), string(g2, (false && (2 == (-6))), g2), :b)
        v41 = -1.04
        __obs__("0a∀")
        v42 = (8, g1, v41)
    end
    if (!((g1 < g1) && (228 == 6)))
        u43 = :e
    end
    __obs__(@isdefined(u43))
    __obs__(try; u43; catch __e; (:__undef, nameof(typeof(__e))) end)
    v44 = Dict{Bool, Symbol}(true => :c, false => :d)
    global g1 = (((:a === get!(v44, true, :a)) ? g1 : ((" ∀" < "∀") ? (1.5 + g1) : (-0.85 + g1))) - 3.78)
    v46 = ((p45) -> g1)
    delete!(v44, (("🐛αaαα" == g2) && true))
    v49 = ((p47, p48) -> g2)
    if haskey(v44, (5 != f16(Any[v24])))
        u50 = g1
    end
    __obs__(@isdefined(u50))
    __obs__(try; u50; catch __e; (:__undef, nameof(typeof(__e))) end)
    __obs__((try v49(0.0, 0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__((try v46(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v44)
    __obs__(v30)
    __obs__((try v24(0, 0.0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(g2)
    __obs__(g1)
end

```

## Original program

```julia
const __LCG__ = Ref{UInt64}(0x000000002876fa98)
__randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
__randint__() = __randu__() % Int64
__randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
__randbool__() = __randu__() % Bool
__randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
g1 = (-7.43 - __randint__())
g2 = "xaa"
function f3(a4::Float64, a5; kw6 = 4, kw7 = 2)
    nothing
    return kw6
end
function f8(a9)
    __obs__(false)
    ((((f3(g1, g2) ÷ 7) + (f3(g1, g1, ; kw6 = (-9223372036854775808), kw7 = a9) * (false ? a9 : a9))) != f3(min(max(-2.5, -1.9), __randfloat__()), (!(a9 isa Any))))) && return ((false || (!(a9 != 10))) || (!(!(false ? false : true))))
    fuel10 = 4
    while ((!(("" != g2) && (g1 >= g1))) ? (string("🐛b∀∀🐛∀", :b) isa Bool) : __randbool__()) && (fuel10 > 0)
        fuel10 -= 1
        fuel11 = 2
        while (-7.72 isa AbstractString) && (fuel11 > 0)
            fuel11 -= 1
            local t12::Float64 = g1
            v14 = ((p13) -> "x🐛y∀βa")
        end
        a9 = 736
    end
    return (f3(((5.41 + g1) * (false ? 463 : a9)), (:e, :a)) === __randrange__(1, 7))
end
function f8(a15::Bool)
    nothing
    return 6
end
function f16(a17::Vector)
    v19 = Int64[f3(g1, ((!(g2 != "")) ? true : (f3(g1, false) === (true ? (-1) : c18)))) for c18 in 1:3]
    v21 = Float64[((((c20 == (-7)) ? (1.7976931348623157e308 * 9.43) : 0.93) / __vtime__()) * (f3((-6.53 / g1), (-7)) + f3((g1 * 2), string(g2, true), ; kw7 = f3(-3.06, nothing)))) for c20 in 1:3]
    return f3(get(v21, ((:b === :c) ? f3(g1, g1) : __randint__()), get(v21, f3(g1, [398, (-10)]), abs(-9.36))), v19, ; kw6 = (-3), kw7 = 1)
end
v24 = ((p22, p23) -> max(((!false) ? 2 : f3(p23, g2)), (f3(-0.0, [g1]) + 4)))
try
    local t26::Float64 = (("!0∀0b " != string(g2, (10 - (-408)))) ? (abs((-9.19 * g1)) - (f3(g1, 4, ; kw7 = 1) + f16(Any[:c, false, g1]))) : (((g1 - g1) * 6.7) * (-7)))
catch err25
    v27 = ((-8), -8.77)
finally
    v28 = Dict{String, Symbol}()
end
v30 = Int64[f3(((!true) ? g1 : ((3.76 * -5.76) - (g1 + -2.5))), f3(-7.15, 8.43), ; kw6 = __randint__(), kw7 = __randrange__(1, 6)) for c29 in 1:2 if true]
let
    __obs__(:d)
    if ((try f16(Any[v24]) catch __e; (:__thrown, nameof(typeof(__e))) end) isa Integer)
        al31 = v30
        v33 = Int64[f3((g1 + g1), "αy!") for c32 in 1:0]
        v34 = :c
    else
        fuel35 = 3
        while false && (fuel35 > 0)
            fuel35 -= 1
            push!(v30, f3((((g1 + (-5)) - (g1 / g1)) / g1), [0.0, -2.13, g1]))
        end
        v36 = Set{String}([g2])
    end
    let l37 = g2, l38 = (g1 * (((-4.69 + (-3)) * 0.0) + __randfloat__()))
        v39 = (:c, l37, (-6))
    end
    let l40 = string(__vtime__(), string(g2, (false && (2 == (-6))), g2), :b)
        v41 = -1.04
        __obs__("0a∀")
        v42 = (8, g1, v41)
    end
    if (!((g1 < g1) && (228 == 6)))
        u43 = :e
    end
    __obs__(@isdefined(u43))
    __obs__(try; u43; catch __e; (:__undef, nameof(typeof(__e))) end)
    v44 = Dict{Bool, Symbol}(true => :c, false => :d)
    global g1 = (((:a === get!(v44, true, :a)) ? g1 : ((" ∀" < "∀") ? (1.5 + g1) : (-0.85 + g1))) - 3.78)
    v46 = ((p45) -> g1)
    delete!(v44, (("🐛αaαα" == g2) && true))
    v49 = ((p47, p48) -> g2)
    if haskey(v44, (5 != f16(Any[v24])))
        u50 = g1
    end
    __obs__(@isdefined(u50))
    __obs__(try; u50; catch __e; (:__undef, nameof(typeof(__e))) end)
    __obs__((try v49(0.0, 0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__((try v46(0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(v44)
    __obs__(v30)
    __obs__((try v24(0, 0.0) catch __e; (:__thrown, nameof(typeof(__e))) end))
    __obs__(g2)
    __obs__(g1)
end

```
