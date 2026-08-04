# Re-shrink a finding, harder than a campaign can afford to.
#
#   julia --project=fuzz fuzz/reshrink.jl --seed S [--mode rec|cmp] [--big]
#                                         [--attempts N] [--budget NSTMTS]
#                                         [--out FILE]
#
# A campaign shrinks inline, so its attempt budget has to stay small enough not
# to stall the run — and long runs are usually driven with `--noshrink`
# entirely, which leaves findings unminimized. Both are the right call during a
# campaign and the wrong one afterwards: a finding worth reporting is worth
# thousands of attempts.
#
# Findings are re-derived from their seed rather than parsed back from
# `findings/*/meta.md`, because the greedy shrinker works on the generator's IR
# and only the source survives in a report. Generation is a pure function of
# (seed, config), so the seed reproduces the IR exactly — which is also why the
# config flags here must match the campaign that produced the finding
# (`--big` above all).

include(joinpath(@__DIR__, "src", "FuzzJI.jl"))
using .FuzzJI
using .FuzzJI: Xoshiro, genprogram, render, run_both, classify, fingerprint, isfinding,
               shrink, ShrinkBudget, nstatements, modeinterp, Cfg

function parseargs(args)
    o = Dict{String,Any}("seed" => nothing, "mode" => "rec", "big" => false,
                         "attempts" => 4000, "budget" => 600_000, "out" => nothing)
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--seed";         o["seed"] = parse(Int, args[i += 1])
        elseif a == "--mode";     o["mode"] = args[i += 1]
        elseif a == "--attempts"; o["attempts"] = parse(Int, args[i += 1])
        elseif a == "--budget";   o["budget"] = parse(Int, args[i += 1])
        elseif a == "--out";      o["out"] = args[i += 1]
        elseif a == "--big";      o["big"] = true
        else; error("unknown argument $a")
        end
        i += 1
    end
    o["seed"] === nothing && error("--seed is required")
    return o
end

o = parseargs(ARGS)

cfg = o["big"] ? Cfg(maxdepth=5, nglobals=1:5, nstructs=0:3, nfundefs=1:5, nmidstmts=0:5,
                     nbodystmts=10:26, maxblockstmts=4, maxblockdepth=4, maxloop=6,
                     maxstring=10) : Cfg()
interp = modeinterp(Symbol(o["mode"]))
nstmts = o["budget"]

prog = genprogram(Xoshiro(o["seed"]), cfg)
r = run_both(render(prog); nstmts, interp)
r === nothing && error("seed $(o["seed"]) does not lower — wrong --big/config for this finding?")
v = classify(r...)
isfinding(v) || error("seed $(o["seed"]) does not reproduce a finding under mode $(o["mode"]) " *
                      "(got $(v.class)) — check --mode and --big match the campaign")

fp = fingerprint(v)
@info "reproduced" seed = o["seed"] class = v.class fp statements = nstatements(prog)
println(first(v.detail, 400))

# This branch's shrinker takes a ShrinkBudget (maxruns + wall-clock) rather than
# a bare maxattempts; give it the requested attempts and effectively no time cap,
# which is the whole point of reshrink — spend what a campaign could not.
sh = shrink(prog, fp; nstmts, interp,
            budget=ShrinkBudget(; maxruns=o["attempts"], seconds=1e9))
src = render(sh)

# The shrinker keeps only edits that preserve the fingerprint, but re-check the
# final artifact independently: a report that does not reproduce is worse than
# no report.
r2 = run_both(src; nstmts, interp)
v2 = r2 === nothing ? nothing : classify(r2...)
ok = v2 !== nothing && isfinding(v2) && fingerprint(v2) == fp

@info "shrunk" from = nstatements(prog) to = nstatements(sh) reproduces = ok
o["out"] === nothing || (write(o["out"], src); @info "wrote" file = o["out"])
println("\n", src)
ok || @error "the shrunk program no longer reproduces the finding — report the original"
exit(ok ? 0 : 1)
