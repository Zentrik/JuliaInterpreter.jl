# Standalone GC-stress reproducer attempt — NO JuliaInterpreter.
#
# Mimics the fuzzing workload that reliably segfaults inside gc-stock.c:
# create many fresh anonymous modules, each parsing + evaluating allocating
# code, with frequent collections. If this segfaults, the bug is pure Julia
# (frontend/module/GC) and needs nothing from JuliaInterpreter.
#
# Run: julia --project=@. gc-repro-pure.jl [NITER]
# Watches for SIGSEGV inside gc-stock.c (the transient cumulative crash).

const NITER = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 200_000

# A few program shapes that allocate the way generated programs do: nested
# Exprs (stresses scm_to_julia / jl_exprn — crash #1's site), arrays, strings,
# dicts, structs, and closures capturing boxes.
progsrc(i) = """
    struct S$i; a::Int; b::Float64; c::String; end
    v = S$i($i, $(i)e0, $(repr("x"^(i % 17))))
    arr = Any[$(join(("($k, $(k)e0)" for k in 1:(i % 13 + 1)), ", "))]
    d = Dict{Int,Any}($(join(("$k => arr" for k in 1:(i % 7 + 1)), ", ")))
    box = Ref(0); f = () -> (box[] += length(arr); box[])
    s = string(v, arr, keys(d), f())
    push!(arr, s); push!(arr, d); push!(arr, f)
    (arr, d, s)
"""

function main()
    t0 = time()
    live = Any[]  # keep some modules alive to build a large marked heap
    for i in 1:NITER
        m = Module(Symbol("GCX", i))
        Core.eval(m, :(const __keep__ = []))
        ex = Meta.parseall(progsrc(i))       # scm_to_julia: the crash-1 alloc site
        r = Core.eval(m, ex)
        # Retain a rolling window of modules + their results so the GC has a
        # large, churning live set to mark (the cumulative condition).
        push!(live, (m, r))
        length(live) > 400 && popfirst!(live)
        if i % 500 == 0
            GC.gc(i % 2000 == 0)             # mix incremental + full collections
            elapsed = round(time() - t0; digits=1)
            println("iter $i  live=$(length(live))  $(elapsed)s  rss=$(round(Sys.maxrss()/2^20))MB")
            flush(stdout)
        end
    end
    println("completed $NITER iterations with no crash")
end

main()
