# Grammar-shape metrics: what does the generator actually *produce*?
#
#   julia --project=fuzz fuzz/metrics.jl [--n SEEDS] [--big] [--maxblockdepth D] ...
#
# Generation is cheap (no execution), so this answers "did that grammar change
# do what I meant?" in seconds instead of waiting on a campaign. Report:
#
#   - program size (statements, rendered lines) — the budget guard: a change
#     that raises feature rates by inflating programs costs throughput and
#     abort rate, and this makes that visible.
#   - control-flow nesting depth histogram — how deep programs actually go, vs
#     the configured cap.
#   - P(program contains X) for the constructs the interpreter is most likely
#     to get wrong. A feature whose probability is ~0 is a grammar gap: either
#     unreachable by construction or diluted below the sampling rate of a
#     campaign, and either way it is not being tested.
#
# Interpreting the interaction rows: `try_in_loop_in_fn` and `exit_through_try`
# are the :enter/:leave and exception-frame-unwinding surface — historically
# the most bug-dense part of an interpreter, and the reason the nesting cap
# matters. `ctrl_in_fn` gates all of them: control flow must be able to appear
# inside an interpreted *function* frame, not just at toplevel.

include(joinpath(@__DIR__, "src", "FuzzJI.jl"))
using .FuzzJI
using .FuzzJI: Xoshiro, St, Program, sections, nstatements

function parseargs(args)
    o = Dict{String,Any}("n" => 500, "big" => false)
    for k in ("maxdepth", "maxblockdepth", "maxblockstmts", "maxloop")
        o[k] = nothing
    end
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--n"
            o["n"] = parse(Int, args[i += 1])
        elseif a == "--big"
            o["big"] = true
        elseif a in ("--maxdepth", "--maxblockdepth", "--maxblockstmts", "--maxloop")
            o[a[3:end]] = parse(Int, args[i += 1])
        else
            error("unknown argument $a")
        end
        i += 1
    end
    return o
end

o = parseargs(ARGS)
base = o["big"] ? Cfg(maxdepth=5, nglobals=1:5, nstructs=0:3, nfundefs=1:5, nmidstmts=0:5,
                      nbodystmts=10:26, maxblockstmts=4, maxblockdepth=4, maxloop=6,
                      maxstring=10) : Cfg()
ov(f, k) = o[k] === nothing ? getfield(base, f) : o[k]
cfg = Cfg(; maxdepth=ov(:maxdepth, "maxdepth"), nglobals=base.nglobals, nstructs=base.nstructs,
            nfundefs=base.nfundefs, nmidstmts=base.nmidstmts, nbodystmts=base.nbodystmts,
            maxblockstmts=ov(:maxblockstmts, "maxblockstmts"), minblockstmts=base.minblockstmts,
            maxblockdepth=ov(:maxblockdepth, "maxblockdepth"), blockdecay=base.blockdecay,
            maxloop=ov(:maxloop, "maxloop"), maxstring=base.maxstring)

const CTRL = (:if, :for, :while, :let, :try)

# Deepest control-flow nesting anywhere in a statement list.
function ctrldepth(sts, d=0)
    m = d
    for st in sts
        nd = st.kind in CTRL ? d + 1 : d
        m = max(m, nd)
        for b in st.blocks
            m = max(m, ctrldepth(b, nd))
        end
    end
    return m
end

# Per-construct occurrence counts, plus the feature *interactions* that matter.
function scan!(counts, sts; infunc=false, inloop=false, intry=false)
    for st in sts
        k = st.kind
        haskey(counts, k) && (counts[k] += 1)
        infunc && k in CTRL && (counts[:ctrl_in_fn] += 1)
        inloop && k === :try && (counts[:try_in_loop] += 1)
        infunc && inloop && k === :try && (counts[:try_in_loop_in_fn] += 1)
        # break/continue/return crossing a try boundary: the unwinding surface
        intry && (k === :brk || k === :cont || k === :ret) && (counts[:exit_through_try] += 1)
        nf = infunc || k === :fundef || k === :recdef
        nl = inloop || k === :for || k === :while
        nt = intry || k === :try
        for b in st.blocks
            scan!(counts, b; infunc=nf, inloop=nl, intry=nt)
        end
    end
end

const TRACKED = (:try, :for, :while, :if, :let, :fundef, :recdef, :structdef, :amodify,
                 :setprop, :alias, :loopundef, :maybeundef, :typedlocal, :brk, :cont, :ret,
                 :compr, :push, :setindex,
                 :ctrl_in_fn, :try_in_loop, :try_in_loop_in_fn, :exit_through_try)

N = o["n"]
counts = Dict{Symbol,Int}(k => 0 for k in TRACKED)
withprog = Dict{Symbol,Int}(k => 0 for k in TRACKED)
depths = Int[]; sizes = Int[]; lines = Int[]
for seed in 1:N
    p = genprogram(Xoshiro(seed), cfg)
    push!(depths, maximum(ctrldepth(sec) for sec in sections(p)))
    push!(sizes, nstatements(p))
    push!(lines, count(==('\n'), render(p)))
    before = copy(counts)
    for sec in sections(p)
        scan!(counts, sec)
    end
    for k in TRACKED
        counts[k] > before[k] && (withprog[k] += 1)
    end
end

mean(xs) = round(sum(xs) / length(xs); digits=2)
pct(x) = string(round(100x / N; digits=1), "%")

println("seeds=$N  maxblockdepth=$(cfg.maxblockdepth) maxblockstmts=$(cfg.maxblockstmts) ",
        "maxdepth=$(cfg.maxdepth) bodystmts=$(cfg.nbodystmts)")
println("statements/program: mean $(mean(sizes))  max $(maximum(sizes))")
println("rendered lines/program: mean $(mean(lines))  max $(maximum(lines))")
println("control-flow depth: mean $(mean(depths))  max $(maximum(depths))  ",
        "histogram(depth 0..) ", [count(==(d), depths) for d in 0:maximum(depths)])
println()
println(rpad("construct", 22), rpad("P(in program)", 15), "occurrences")
for k in TRACKED
    k === :ctrl_in_fn && println("  -- feature interactions --")
    println("  ", rpad(k, 20), rpad(pct(withprog[k]), 15), counts[k])
end
