# Julia 1.12.6: sext_int(UInt64, ::Bool) — codegen sign-extends the i1 bit,
# runtime dispatch and inference's constant folder sign-extend the i8 byte.
# Run: julia repro.jl   (any -O level)
const CB = Base.compilerbarrier

g = true                                     # untyped global → runtime intrinsic dispatch
println("runtime  dispatch: ", repr(Base.sext_int(UInt64, g)))       # 0x…01

@noinline fc() = Base.sext_int(UInt64, CB(:const, true))
println("compiled codegen : ", repr(fc()))                           # 0xffffffffffffffff

println("const-folded     : ", repr(Base.sext_int(UInt64, true)))    # 0x…01
