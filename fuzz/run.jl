# CLI entry point.
#
#   julia --project=fuzz fuzz/run.jl [--engine supposition|native] [--n N] [--seed S]
#                                    [--budget NSTMTS] [--modes rec|cmp|both] [--selftest]
#
# Engines:
#   supposition (default) — Supposition.jl drives generation; counterexamples
#     are choice-sequence-shrunk, then polished by the greedy IR shrinker.
#     --n is examples per round; rounds continue while new findings appear.
#   native — seeded-RNG loop (one integer seed per candidate); the only mode
#     with the crash-safe journal, so use it when hunting worker crashes:
#     while true; julia --project=fuzz fuzz/run.jl --engine native --n 100000 --seed $RANDOM; done
#
# --modes selects the interpreter configurations each candidate runs under:
#   rec (RecursiveInterpreter), cmp (Compiled mode / NonRecursiveInterpreter),
#   or both (default; the reference still runs only once per candidate).

include(joinpath(@__DIR__, "src", "FuzzJI.jl"))
using .FuzzJI

function parseargs(args)
    o = Dict{String,Any}("engine" => "supposition", "n" => 1000, "seed" => 1,
                         "budget" => 300_000, "selftest" => false, "noshrink" => false,
                         "modes" => "both")
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--n"
            o["n"] = parse(Int, args[i += 1])
        elseif a == "--seed"
            o["seed"] = parse(Int, args[i += 1])
        elseif a == "--budget"
            o["budget"] = parse(Int, args[i += 1])
        elseif a == "--engine"
            o["engine"] = args[i += 1]
        elseif a == "--modes"
            o["modes"] = args[i += 1]
        elseif a == "--selftest"
            o["selftest"] = true
        elseif a == "--noshrink"
            o["noshrink"] = true
        else
            error("unknown argument $a")
        end
        i += 1
    end
    return o
end

o = parseargs(ARGS)

# Interpreter configurations to test each candidate under:
#   rec — RecursiveInterpreter (everything interpreted)
#   cmp — Compiled mode (toplevel stepped, calls execute natively)
#   both — each candidate runs under both (default)
modes = o["modes"] == "both" ? (:rec, :cmp) :
        o["modes"] == "rec"  ? (:rec,) :
        o["modes"] == "cmp"  ? (:cmp,) :
        error("unknown --modes $(o["modes"]) (expected: rec | cmp | both)")

if o["selftest"]
    include(joinpath(@__DIR__, "selftest.jl"))
elseif o["engine"] == "supposition"
    nfound = supposition_campaign(examples=o["n"], nstmts=o["budget"], doshrink=!o["noshrink"],
                                  modes=modes)
    @info "supposition campaign complete" nfound
    exit(nfound == 0 ? 0 : 2)   # non-zero exit on new findings, for CI
elseif o["engine"] == "native"
    stats = campaign(n=o["n"], baseseed=o["seed"], nstmts=o["budget"], doshrink=!o["noshrink"],
                     modes=modes)
    @info "campaign complete" stats.cases stats.agreed stats.aborted stats.discarded stats.findings stats.duplicates stats.suppressed
    exit(stats.findings == 0 ? 0 : 2)
else
    error("unknown engine $(o["engine"]) (expected: supposition | native)")
end
