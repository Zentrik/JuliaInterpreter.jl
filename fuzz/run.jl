# CLI entry point.
#
#   julia --project=fuzz fuzz/run.jl [--engine supposition|native] [--n N] [--seed S]
#                                    [--budget NSTMTS] [--modes rec|cmp|both] [--selftest]
#                                    [--big] [--fresh] [--patience K]
#                                    [--noshrink] [--shrinkruns N] [--shrinksecs S]
#                                    [--maxdepth D] [--maxblockdepth D] [--maxblockstmts N]
#                                    [--maxloop N] [--bodystmts LO:HI]
#
# Shrinking: every axis minimizes a finding before writing it, against its own
# property (differential fingerprint / same stepping verdict class / same
# eval_code check / same corpus verdict class). --noshrink reports findings as
# generated; --shrinkruns and --shrinksecs cap the per-finding cost so one
# stubborn case cannot stall a campaign.
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
#   split — the ExprSplitter axis: adversarial *toplevel forms* (nested modules,
#     baremodules, unsplittable blocks, toplevel macros, docstrings, odd
#     declarations) run through ExprSplitter + Frame and compared against
#     Core.eval on failure mode, observation stream, and the resulting module
#     tree. Every case runs in both interpreter modes (:rec and :cmp) against
#     one shared reference, and a gated quarter of cases uses Base.__toplevel__
#     as the parent module (find_or_create_module's package-resolution arm).
#     Targets construct.jl. --splitdepth bounds module nesting,
#     --maxfrags the iteration budget.
#   step — the debugger axis: drives each generated program through a random
#     debug_command walk instead of running it, asserting that stepping
#     terminates, raises no internal error, and reaches the same observations
#     as plain interpretation. The walk also manages *real breakpoints* (entry,
#     per-method, conditional, line — set/enable/disable/toggle/remove) on the
#     program's own callables. Targets commands.jl/breakpoints.jl.
#     --maxcmds bounds the walk; --nobreakpoints disables both the breakpoint
#     driver and break-on-error.
#   call — the public-entry-point axis: defines each program natively, then
#     compares native calls against enter_call + a debug_command walk on
#     synthesized arguments (edge values, structs, varargs, kwargs), with
#     double-native-call self-agreement certification. Targets construct.jl's
#     enter_call/prepare_* path, which every other axis bypasses.
#
# --modes selects the interpreter configurations each candidate runs under:
#   rec (RecursiveInterpreter), cmp (Compiled mode / NonRecursiveInterpreter),
#   or both (default; the reference still runs only once per candidate).

include(joinpath(@__DIR__, "src", "FuzzJI.jl"))
using .FuzzJI

function parseargs(args)
    o = Dict{String,Any}("engine" => "supposition", "n" => 1000, "seed" => 1,
                         "budget" => 600_000, "selftest" => false, "noshrink" => false,
                         "nothreeway" => false,
                         "modes" => "both", "big" => false, "fresh" => false,
                         "patience" => 1, "nosync" => false, "noswarm" => false,
                         "nopolicy" => false, "maxcmds" => 4000, "nobreakpoints" => false,
                         "maxsplice" => 3, "nostep" => false,
                         "shrinkruns" => nothing, "shrinksecs" => nothing,
                         "splitdepth" => 3, "maxfrags" => 4000,
                         "journaldir" => joinpath(@__DIR__, "journal"))
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
        elseif a == "--noshrink"       # report findings unminimized (every axis)
            o["noshrink"] = true
        elseif a == "--nothreeway"     # disable JI adjudication (compiled-only oracle)
            o["nothreeway"] = true
        elseif a == "--shrinkruns"     # per-finding cap on candidate re-executions
            o["shrinkruns"] = parse(Int, args[i += 1])
        elseif a == "--shrinksecs"     # per-finding wall-clock cap, seconds
            o["shrinksecs"] = parse(Float64, args[i += 1])
        elseif a == "--big"
            o["big"] = true
        elseif a == "--fresh"          # ignore findings/ when seeding the dedup set
            o["fresh"] = true
        elseif a == "--nosync"         # drop the per-candidate journal fsync (throughput)
            o["nosync"] = true
        elseif a == "--noswarm"        # enable every feature in every program
            o["noswarm"] = true
        elseif a == "--nopolicy"       # uniform weights (no per-program skew)
            o["nopolicy"] = true
        elseif a == "--maxcmds"        # step engine: command budget per program
            o["maxcmds"] = parse(Int, args[i += 1])
        elseif a == "--nobreakpoints"  # step engine: don't arm break-on-error
            o["nobreakpoints"] = true
        elseif a == "--maxsplice"      # corpus engine: max real fragments per case
            o["maxsplice"] = parse(Int, args[i += 1])
        elseif a == "--nostep"         # corpus engine: run only, don't also step
            o["nostep"] = true
        elseif a == "--splitdepth"     # split engine: max module nesting depth
            o["splitdepth"] = parse(Int, args[i += 1])
        elseif a == "--maxfrags"       # split engine: ExprSplitter iteration budget
            o["maxfrags"] = parse(Int, args[i += 1])
        elseif a == "--journaldir"     # per-shard journal: current.jl is one file,
            o["journaldir"] = args[i += 1]   # so concurrent shards must not share it
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
                 maxstring      = base.maxstring,
                 swarm          = !o["noswarm"],
                 policy         = !o["nopolicy"])
end

o = parseargs(ARGS)
cfg = makecfg(o)

# Shrink-budget overrides. Only the knobs actually given on the command line are
# forwarded, so each axis keeps its own default (the stepping and eval_code
# predicates replay a whole command walk per candidate and are correspondingly
# more expensive than a differential re-run).
shrinkopts = merge(o["shrinkruns"] === nothing ? NamedTuple() : (shrinkruns = o["shrinkruns"],),
                   o["shrinksecs"] === nothing ? NamedTuple() : (shrinksecs = o["shrinksecs"],))

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
    res = supposition_campaign(; examples=o["n"], nstmts=o["budget"], doshrink=!o["noshrink"],
                               modes=modes, cfg=cfg, patience=o["patience"],
                               seeddisk=!o["fresh"], journalsync=!o["nosync"],
                               journaldir=o["journaldir"], dothreeway=!o["nothreeway"], shrinkopts...)
    @info "supposition campaign complete" res.nfound res.nondet_discard res.compiler_interp_divergence res.julia_engine_divergence
    exit(res.nfound == 0 ? 0 : 2)   # non-zero exit on new findings, for CI
elseif o["engine"] == "native"
    stats = campaign(; n=o["n"], baseseed=o["seed"], nstmts=o["budget"], doshrink=!o["noshrink"],
                     modes=modes, cfg=cfg, seeddisk=!o["fresh"], journalsync=!o["nosync"],
                     journaldir=o["journaldir"], dothreeway=!o["nothreeway"], shrinkopts...)
    @info "campaign complete" stats.cases stats.agreed stats.aborted stats.nondet_discard stats.compiler_interp_divergence stats.julia_engine_divergence stats.discarded stats.findings stats.duplicates stats.suppressed
    exit(stats.findings == 0 ? 0 : 2)
elseif o["engine"] == "step"
    stats = step_campaign(; n=o["n"], baseseed=o["seed"], nstmts=o["budget"], cfg=cfg,
                          seeddisk=!o["fresh"], journalsync=!o["nosync"],
                          maxcmds=o["maxcmds"], usebreakpoints=!o["nobreakpoints"],
                          doshrink=!o["noshrink"], journaldir=o["journaldir"], shrinkopts...)
    @info "step campaign complete" stats.cases stats.agreed stats.aborted stats.discarded stats.findings stats.duplicates stats.suppressed
    exit(stats.findings == 0 ? 0 : 2)
elseif o["engine"] == "call"
    stats = call_campaign(; n=o["n"], baseseed=o["seed"], cfg=cfg,
                          seeddisk=!o["fresh"], journalsync=!o["nosync"],
                          journaldir=o["journaldir"])
    @info "call campaign complete" stats.cases stats.agreed stats.nondet_discard stats.discarded stats.findings stats.duplicates stats.suppressed
    exit(stats.findings == 0 ? 0 : 2)
elseif o["engine"] == "evalcode"
    stats = evalcode_campaign(; n=o["n"], baseseed=o["seed"], nstmts=o["budget"], cfg=cfg,
                              seeddisk=!o["fresh"], journalsync=!o["nosync"],
                              doshrink=!o["noshrink"], journaldir=o["journaldir"], shrinkopts...)
    @info "evalcode campaign complete" stats.cases stats.agreed stats.discarded stats.findings stats.duplicates stats.suppressed
    exit(stats.findings == 0 ? 0 : 2)
elseif o["engine"] == "split"
    stats = split_campaign(n=o["n"], baseseed=o["seed"], nstmts=o["budget"],
                           cfg=SplitCfg(maxdepth=o["splitdepth"], maxfrags=o["maxfrags"]),
                           seeddisk=!o["fresh"], journalsync=!o["nosync"],
                           doshrink=!o["noshrink"], journaldir=o["journaldir"], shrinkopts...)
    @info "split campaign complete" stats.cases stats.agreed stats.aborted stats.discarded stats.findings stats.duplicates stats.suppressed
    exit(stats.findings == 0 ? 0 : 2)
elseif o["engine"] == "corpus"
    stats = corpus_campaign(; n=o["n"], baseseed=o["seed"], nstmts=o["budget"],
                            maxsplice=o["maxsplice"], maxcmds=o["maxcmds"],
                            dostep=!o["nostep"], seeddisk=!o["fresh"], doshrink=!o["noshrink"],
                            journalsync=!o["nosync"], journaldir=o["journaldir"], shrinkopts...)
    @info "corpus campaign complete" stats.cases ran = stats.agreed - stats.aborted discarded_junk = stats.aborted certified = stats.certified stats.nondet_discard stats.findings stats.duplicates stats.suppressed
    exit(stats.findings == 0 ? 0 : 2)
else
    error("unknown engine $(o["engine"]) (expected: supposition | native | step | call | evalcode | corpus | split)")
end
