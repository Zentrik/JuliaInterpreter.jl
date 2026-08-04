# FuzzJI reproducer — julia_engine_divergence (interp mode: rec)
# seed: 1201712
# julia: 1.12.6
# detail: obs[1]: ref=(:__thrown, :BoundsError) interp=(:__thrown, :ArgumentError)
# Run with: julia --project=<repo>/fuzz <this file>
include(joinpath(@__DIR__, "..", "..", "reprolib.jl"))
const SRC = "const g1 = ((-4) * 2)\nglobal g2::Int64 = g1\nv3 = [g2]\nlet\n    v4 = ((g2 ÷ (-3)) * get(v3, g2, abs((5 * g1))))\n    local t5::Int64 = (((g2 + (v4 % 1)) % (-1)) * (-4))\n    v6 = (0, \"1🐛β\", \"0ba\")\n    v7 = g2\n    v8 = -5.73\n    __obs__((try Core._svec_ref() catch __e; (:__thrown, nameof(typeof(__e))) end))\n    let l9 = (min(v8, v8) * (v8 + max(g1, v4))), l10 = (-2)\n        try; v3[get(v3, (((false isa Any) ? min(t5, (-2)) : ((-4) + g1)) - (1 ÷ (-1))), (-8))] = 9; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end\n    end\n    __obs__((((!true) ? ((-0.33 + v8) != v8) : (false ? (4.16 < 1.14) : (true && false))) ? 2.89 : v8))\n    fuel11 = 2\n    while (((!(!false)) ? v8 : abs((v8 / 9223372036854775807))) isa AbstractString) && (fuel11 > 0)\n        fuel11 -= 1\n        v12 = (try Base.rint_llvm(Base.compilerbarrier(:const, 4.07)) catch __e; (:__thrown, nameof(typeof(__e))) end)\n    end\n    let l13 = (string(9223372036854775807, :b) == \"!\")\n        v14 = (v7, (-10), v8)\n    end\n    __obs__(v8)\n    __obs__(v7)\n    __obs__(v6)\n    __obs__(t5)\n    __obs__(v4)\n    __obs__(v3)\n    __obs__(g2)\n    __obs__(g1)\nend\n"
reprorun(SRC)
