# Standalone reproducer attempt v2 — NO JuliaInterpreter. Targets crash 4.
#
# Crash 4 (crashed/crash4-egal-leafcache-assertbuild.txt) faulted comparing an
# svec inside a *method-table leafcache* (gf.c lookup_leafcache) during
# jl_gf_invoke_lookup_worlds. The fuzz workload populates long-lived method
# tables (Base functions, and a shared local generic function) with cache
# entries whose key tuple-types reference *short-lived types from dropped
# anonymous modules* — old table, young entry: the missed-write-barrier shape.
#
# This driver reproduces exactly that churn, with none of JuliaInterpreter:
#   - fresh anonymous module per iteration defining a struct + methods
#   - methods added to a SHARED long-lived generic function (probe) so its
#     method table and leafcache outlive the module that fed them
#   - lookups via hasmethod/which/invoke — the same ml_matches/leafcache path
#     the crash was on — at both current and pinned older worlds
#   - dynamic dispatch on the fresh types to populate dispatch caches
#   - modules dropped from a rolling window; frequent mixed collections
#
# Run: julia repro-pure-v2.jl [NITER]

const NITER = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 2_000_000

probe(x) = 0            # shared, long-lived generic function; mt outlives feeders
probe(x::Int) = 1

function main()
    t0 = time()
    live = Any[]
    world_floor = Base.get_world_counter()
    for i in 1:NITER
        m = Module(Symbol("GCY", i))
        sname = Symbol("S", i)
        # define a fresh struct + methods on the shared function and on Base names
        Core.eval(m, quote
            struct $sname; a::Int; b::String; end
            Base.length(x::$sname) = x.a
            Base.isempty(x::$sname) = x.a == 0
            $(@__MODULE__).probe(x::$sname) = x.a + 2
        end)
        T = getglobal(m, sname)
        v = Base.invokelatest(T, i, "x"^(i % 9))
        # populate + probe the leafcache of long-lived method tables with
        # tuple-type keys that embed the soon-to-die type T
        Base.invokelatest(probe, v)
        Base.invokelatest(length, v)
        hasmethod(probe, Tuple{T})
        hasmethod(length, Tuple{T})
        hasmethod(push!, Tuple{Vector{Any}, T})
        which(probe, Tuple{T})
        # lookups at a pinned older world (what whichtt does with frame.world)
        w = Base.get_world_counter() - UInt(1)
        ccall(:jl_gf_invoke_lookup_worlds, Any, (Any, Any, Csize_t, Ptr{Csize_t}, Ptr{Csize_t}),
              Tuple{typeof(probe), T}, nothing, w, Ref(UInt(0)), Ref(UInt(0)))
        push!(live, (m, v))
        length(live) > 300 && popfirst!(live)
        if i % 500 == 0
            GC.gc(i % 2000 == 0)
            elapsed = round(time() - t0; digits=1)
            println("iter $i  world+$(Base.get_world_counter()-world_floor)  $(elapsed)s  rss=$(round(Sys.maxrss()/2^20))MB")
            flush(stdout)
        end
    end
    println("completed $NITER iterations with no crash")
end

main()
