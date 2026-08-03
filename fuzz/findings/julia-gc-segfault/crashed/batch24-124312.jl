# FuzzJI candidate — seed 602300291
const __LCG__ = Ref{UInt64}(0x000000000295de02)
__randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
__randint__() = __randu__() % Int64
__randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
__randbool__() = __randu__() % Bool
__randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
g1 = (((-0.08 >= -9.93) ? __randint__() : ((false ? (-1) : 5) ÷ (-1))) != 4)
function f2(a3 = 0, va4...)
    for li5 in 1:2
        if li5 == 2
            __obs__(@isdefined(lx6))
            __obs__(try; (:__v, lx6); catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        lx6 = li5
    end
    return ((p7) -> "byx")
end
function f8(a9::Int64)
    v10 = f2((a9, a9))
    local t11::Float64 = (-6.52 + 10)
    local t12::Float64 = t11
    return ((p13, p14) -> (((p14 - 5) % (-1)) * (-288)))
end
function f8(a15::Float64)
    nothing
    return (-5)
end
let
    v16 = Dict{Symbol, Float64}()
    __obs__([(-2)])
    delete!(v16, :b)
    v16 = v16
    fuel17 = 1
    while __randbool__() && (fuel17 > 0)
        fuel17 -= 1
        for li18 in 1:3
            if li18 == 2
                __obs__(@isdefined(lx19))
                __obs__(try; (:__v, lx19); catch __e; (:__undef, nameof(typeof(__e))) end)
            end
            lx19 = ((1.04 / __randrange__(1, 4)) / (((-9.89 - -0.4) - (g1 ? -1.92 : 2.220446049250313e-16)) - (((-10) - 10) - 0)))
        end
        local t20::Int64 = __vtime__()
        ((!(!g1))) && break
    end
    v21 = 3
    v22 = (false ? "1" : ((true ? (g1 ? g1 : g1) : ("!β∀" != "y🐛α🐛0")) ? "bx" : (((-9) == (-8)) ? "!a" : string("α🐛b∀x", v21))))
    __obs__(v22)
    __obs__(v21)
    __obs__(v16)
    __obs__(g1)
end
