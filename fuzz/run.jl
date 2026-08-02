# CLI entry point.
#
#   julia --project=fuzz fuzz/run.jl [--engine supposition|native] [--n N] [--seed S]
#                                    [--budget NSTMTS] [--modes rec|cmp|both] [--selftest]
#                                    [--big] [--fresh] [--patience K]
#                                    [--maxdepth D] [--maxblockdepth D] [--maxblockstmts N]
#                                    [--maxloop N] [--bodystmts LO:HI]
#
# Generator size: --big selects a larger profile (deeper nesting, more sections,
# longer bodies); the individual knobs override whichever profile is in effect.
# --fresh ignores existing findings/ when seeding the dedup set, so a rerun
# re-reports known findings instead of silently counting them as duplicates.
# --patience K keeps a supposition campaign going until K consecutive rounds
# find nothing new (default 1 = stop at the first empty round).
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
                         "modes" => "both", "big" => false, "fresh" => false,
                         "patience" => 1, "nosync" => false)
    # Cfg overrides start unset (nothing) and fall through to the profile default.
    for k in ("maxdepth", "maxblockdepth", "maxblockstmts", "maxloop", "bodystmts")
        o[k] = nothing
    end
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
        elseif a == "--big"
            o["big"] = true
        elseif a == "--fresh"          # ignore findings/ when seeding the dedup set
            o["fresh"] = true
        elseif a == "--nosync"         # drop the per-candidate journal fsync (throughput)
            o["nosync"] = true
        elseif a == "--patience"       # consecutive empty supposition rounds before stopping
            o["patience"] = parse(Int, args[i += 1])
        elseif a == "--maxdepth"
            o["maxdepth"] = parse(Int, args[i += 1])
        elseif a == "--maxblockdepth"
            o["maxblockdepth"] = parse(Int, args[i += 1])
        elseif a == "--maxblockstmts"
            o["maxblockstmts"] = parse(Int, args[i += 1])
        elseif a == "--maxloop"
            o["maxloop"] = parse(Int, args[i += 1])
        elseif a == "--bodystmts"      # LO:HI range, e.g. --bodystmts 8:24
            lo, hi = split(args[i += 1], ':')
            o["bodystmts"] = parse(Int, lo):parse(Int, hi)
        else
            error("unknown argument $a")
        end
        i += 1
    end
    return o
end

# Build the generator config from CLI options. `--big` selects a larger base
# profile (deeper nesting, more/longer sections); individual --max* / --bodystmts
# flags override whichever base is in effect.
function makecfg(o)
    base = o["big"] ? Cfg(maxdepth=5, nglobals=1:5, nstructs=0:3, nfundefs=1:5,
                          nmidstmts=0:5, nbodystmts=10:26, maxblockstmts=4,
                          maxblockdepth=4, maxloop=6, maxstring=10) : Cfg()
    ov(field, key) = o[key] === nothing ? getfield(base, field) : o[key]
    return Cfg(; maxdepth       = ov(:maxdepth, "maxdepth"),
                 nglobals       = base.nglobals,
                 nstructs       = base.nstructs,
                 nfundefs       = base.nfundefs,
                 nmidstmts      = base.nmidstmts,
                 nbodystmts     = ov(:nbodystmts, "bodystmts"),
                 maxblockstmts  = ov(:maxblockstmts, "maxblockstmts"),
                 minblockstmts  = base.minblockstmts,
                 maxblockdepth  = ov(:maxblockdepth, "maxblockdepth"),
                 blockdecay     = base.blockdecay,
                 maxloop        = ov(:maxloop, "maxloop"),
                 maxstring      = base.maxstring)
end

o = parseargs(ARGS)
cfg = makecfg(o)

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
                                  modes=modes, cfg=cfg, patience=o["patience"],
                                  seeddisk=!o["fresh"], journalsync=!o["nosync"])
    @info "supposition campaign complete" nfound
    exit(nfound == 0 ? 0 : 2)   # non-zero exit on new findings, for CI
elseif o["engine"] == "native"
    stats = campaign(n=o["n"], baseseed=o["seed"], nstmts=o["budget"], doshrink=!o["noshrink"],
                     modes=modes, cfg=cfg, seeddisk=!o["fresh"], journalsync=!o["nosync"])
    @info "campaign complete" stats.cases stats.agreed stats.aborted stats.discarded stats.findings stats.duplicates stats.suppressed
    exit(stats.findings == 0 ? 0 : 2)
else
    error("unknown engine $(o["engine"]) (expected: supposition | native)")
end
