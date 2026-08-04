# FuzzJI candidate — seed 5000644
mutable struct S1
    fld2::Float64
    @atomic fld3::Bool
    fld4::Bool
end
mutable struct S5
    fld6::Float64
    fld7::Float64
end
mutable struct S8
    @atomic fld9::Bool
    @atomic fld10::Int64
    fld11::Int64
end
g12 = 3.24
sv13 = S5(g12, 1.38)
function fr14(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr14(n - 1, acc + (-4))
end
let
    try
        v16 = (:d, :e, 0.32)
        local t17::Int64 = 9
        __obs__((fr14(fr14(fr14(7, fr14(1, t17)), fr14((true ? t17 : t17), 0)), fr14(fr14(fr14(3, t17), (t17 - 8)), ((!true) ? fr14(t17, t17) : (-6)))) + (min(((t17 > (-192)) ? ((-10) + t17) : t17), ((t17 + t17) + t17)) + fr14(fr14(fr14(t17, t17), (-1)), (fr14(t17, t17) + fr14(t17, (-5)))))))
    catch err15
        if (g12 < g12)
            u18 = "∀αa!1bbbα"
        end
        __obs__(@isdefined(u18))
        __obs__(try; u18; catch __e; (:__undef, nameof(typeof(__e))) end)
        (((-7) != fr14((((0.1 == 5.94) && (g12 == 5.34)) ? fr14(fr14((-2), (-9)), (-3)) : (-10)), (-6)))) && rethrow()
    end
    v19 = Any[1.7976931348623157e308]
    v20 = fr14((((-2) - (true ? fr14(230, 9) : length(v19))) + ((("" != "a !") || (true || true)) ? fr14(((-10) * 0), fr14((-587), 5)) : (-1))), abs((3 % (-3))))
    v21 = [v20]
    v23 = Float64[(g12 - abs((g12 + (sv13).fld7))) for c22 in 1:2]
    v24 = (((true || ((false ? true : false) ? (true ? true : false) : false)) ? g12 : g12) != g12)
    if (((g12 * ((v24 ? 0.1 : g12) + g12)) / get(v23, fr14((v24 ? v20 : v20), get(v21, v20, v20)), (v24 ? (v24 ? g12 : 0.0) : (sv13).fld7))) != ((!(fr14(v20, v20) == 6)) ? (sv13).fld7 : g12))
        u25 = (((get(v23, fr14(v20, (-3)), (sv13).fld7) isa Any) ? ((abs(-2.5) - -8.12) - 5.11) : (g12 / g12)) * (sv13).fld7)
    end
    __obs__(@isdefined(u25))
    __obs__(try; u25; catch __e; (:__undef, nameof(typeof(__e))) end)
    push!(v23, g12)
    v26 = S8(false, v20, fr14(((abs(-9.18) isa Bool) ? v20 : fr14(175, length(v19))), (fr14((v24 ? 4 : v20), v20) + abs((-1)))))
    local t27::Float64 = (((@atomic (v26).fld9) ? (true ? ((g12 * 6.01) * (g12 / g12)) : (v24 ? -1.93 : (sv13).fld6)) : (true ? abs((g12 / v20)) : ((v20 != v20) ? (sv13).fld7 : 1.43))) * fr14((v26).fld11, min(fr14(((-425) + v20), (v20 - 10)), (v26).fld11)))
    __obs__(-8.96)
    try
        __obs__(get(v23, get(v21, (@atomic (v26).fld10), fr14(fr14(v20, fr14((-10), 1)), fr14(fr14(v20, v20), fr14(3, 10)))), g12))
        v29 = S8(((((!v24) ? string(v24, v20) : (v24 ? "0 " : "x∀0ay🐛β")) isa Bool) || (@atomic (v26).fld9)), (4 % 7), fr14(((!(false || v24)) ? fr14(fr14((-9), v20), (@atomic (v26).fld10)) : (@atomic (v26).fld10)), get(v21, (fr14(v20, v20) - fr14(v20, (-9223372036854775808))), ((v20 * v20) + (v20 ÷ (-3))))))
        @atomic v29.fld10 -= abs((v29).fld11)
    catch err28
        __obs__(((!v24) ? (sv13).fld6 : abs((sv13).fld6)))
        v30 = :c
    end
    @atomic v26.fld10 += fr14(fr14((((!v24) ? v24 : v24) ? (@atomic (v26).fld10) : fr14(((-4) * v20), fr14(v20, v20))), max((v26).fld11, (v20 + v20))), v20)
    al31 = v19
    __obs__(al31)
    __obs__(t27)
    __obs__(v26)
    __obs__(v24)
    __obs__(v23)
    __obs__(v21)
    __obs__(v20)
    __obs__(v19)
    __obs__(sv13)
    __obs__(g12)
end
