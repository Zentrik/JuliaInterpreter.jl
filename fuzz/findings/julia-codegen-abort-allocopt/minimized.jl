mutable struct S1
end
mutable struct S5
end
mutable struct S8
    @atomic fld9::Bool
    @atomic fld10::Int64
    fld11::Int64
end
function fr14(n::Int64, acc::Int64)
    (n <= 0 || n > 16) && return acc
    return fr14(n - 1, acc + (-4))
end
let
    try
    catch err15
        if (g12 < g12)
        end
    end
    v20 = fr14((((-2) - (true ? fr14(230, 9) : length(v19))) + ((("" != "a !") || (true || true)) ? fr14(((-10) * 0), fr14((-587), 5)) : (-1))), abs((3 % (-3))))
    v23 = Float64[(g12 - abs((g12 + (sv13).fld7))) for c22 in 1:2]
    if (((g12 * ((v24 ? 0.1 : g12) + g12)) / get(v23, fr14((v24 ? v20 : v20), get(v21, v20, v20)), (v24 ? (v24 ? g12 : 0.0) : (sv13).fld7))) != ((!(fr14(v20, v20) == 6)) ? (sv13).fld7 : g12))
    end
    v26 = S8(false, v20, fr14(((abs(-9.18) isa Bool) ? v20 : fr14(175, length(v19))), (fr14((v24 ? 4 : v20), v20) + abs((-1)))))
    try
        v29 = S8(((((!v24) ? string(v24, v20) : (v24 ? "0 " : "x∀0ay🐛β")) isa Bool) || (@atomic (v26).fld9)), (4 % 7), fr14(((!(false || v24)) ? fr14(fr14((-9), v20), (@atomic (v26).fld10)) : (@atomic (v26).fld10)), get(v21, (fr14(v20, v20) - fr14(v20, (-9223372036854775808))), ((v20 * v20) + (v20 ÷ (-3))))))
        @atomic v29.fld10 -= abs((v29).fld11)
    catch err28
    end
end