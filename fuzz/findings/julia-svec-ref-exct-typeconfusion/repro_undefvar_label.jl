# Julia 1.12.6: the ":UndefVarError" face of the _svec_ref exct bug (nightly
# findings 1ca00f6b (0-arg) and 5ada7c05 (3-arg)). Because the try block also
# reads non-const globals (exct UndefVarError), the catch var is inferred
# Union{BoundsError,UndefVarError} — the true ArgumentError is excluded — and
# nameof(typeof(e)) union-splits to the wrong label.
# Run: julia repro_undefvar_label.jl   (any -O level)
const CB = Base.compilerbarrier
g6 = -3; v38 = [17, 17]                          # non-const globals
f() = try; Core._svec_ref(CB(:const, g6), CB(:const, v38), CB(:const, Int32(7))); catch e; nameof(typeof(e)) end
println("compiled label: ", f())                 # :UndefVarError
e = try; Core._svec_ref(g6, v38, Int32(7)); catch ex; ex end
println("truth         : ", typeof(e))           # ArgumentError (too many arguments)
