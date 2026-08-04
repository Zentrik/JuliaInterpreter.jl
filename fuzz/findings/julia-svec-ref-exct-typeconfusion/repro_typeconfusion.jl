# Julia 1.12.6 (and master by code inspection): inference declares
# Core._svec_ref's exception type as BoundsError unconditionally
# (Compiler/src/tfuncs.jl, builtin_exct), but the runtime builtin throws
# ArgumentError (bad arity) or TypeError (bad argument types). Compiled catch
# blocks are typed with the wrong exception type, so typeof/isa fold wrong.
# Run: julia repro_typeconfusion.jl   (any -O level)

@noinline g1() = Core._svec_ref(:c)          # runtime throws ArgumentError
f1() = try; g1(); catch e; (typeof(e), isa(e, BoundsError), isa(e, ArgumentError)) end
println("repro1 (compiled view): ", f1())        # (BoundsError, true, false)
e1 = try; g1(); catch e; e end                   # caught in toplevel interpreter = truth
println("repro1 (truth):         ", typeof(e1))  # ArgumentError

@noinline g2() = Core._svec_ref(1, :x)       # runtime throws TypeError
f2() = try; g2(); catch e; typeof(e) end
println("repro2 (compiled view): ", f2())        # BoundsError
e2 = try; g2(); catch e; e end
println("repro2 (truth):         ", typeof(e2))  # TypeError
