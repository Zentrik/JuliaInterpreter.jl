# Julia 1.12.6: segfaults at -O0, -O1 and default -O2. Pure Julia, no unsafe.
# Inference types the catch var as BoundsError (builtin_exct for _svec_ref),
# the runtime object is ArgumentError (1 field); the devirtualized
# showerror(::IO, ::BoundsError) reads field 2 (.i) past the end of the object
# and does `isa` on the garbage pointer → SIGSEGV at errorshow.jl:62.
# Run: julia repro_segfault.jl
@noinline g() = Core._svec_ref(:c)
function f()
    try
        g()
    catch e
        sprint(showerror, e)
    end
end
println(f())
