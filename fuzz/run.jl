# CLI entry point.
#
#   julia --project=fuzz fuzz/run.jl [--n N] [--seed S] [--budget NSTMTS] [--selftest]
#
# For long unattended runs, wrap in a restart loop so a crash of the worker
# process (itself a finding — see journal/current.jl) doesn't end the campaign:
#   while true; julia --project=fuzz fuzz/run.jl --n 100000 --seed $RANDOM; done

include(joinpath(@__DIR__, "src", "FuzzJI.jl"))
using .FuzzJI

function parseargs(args)
    o = Dict{String,Any}("n" => 1000, "seed" => 1, "budget" => 300_000, "selftest" => false, "noshrink" => false)
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--n"
            o["n"] = parse(Int, args[i += 1])
        elseif a == "--seed"
            o["seed"] = parse(Int, args[i += 1])
        elseif a == "--budget"
            o["budget"] = parse(Int, args[i += 1])
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

if o["selftest"]
    include(joinpath(@__DIR__, "selftest.jl"))
else
    stats = campaign(n=o["n"], baseseed=o["seed"], nstmts=o["budget"], doshrink=!o["noshrink"])
    @info "campaign complete" stats.cases stats.agreed stats.aborted stats.discarded stats.findings stats.duplicates stats.suppressed
    # Non-zero exit when new findings were reported, for CI.
    exit(stats.findings == 0 ? 0 : 2)
end
