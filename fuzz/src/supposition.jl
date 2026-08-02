# Supposition.jl front end: choice-sequence generation and shrinking.
#
# The existing generator is reused wholesale via an RNG adapter: `TCRNG`
# forwards every draw the generator makes to Supposition's `TestCase` choice
# recording. Shrinking then replays a shortened/lowered choice sequence
# through the *same* environment-directed generator, so shrunk programs are
# valid by construction — the Hypothesis "generation by replay" property.
#
# The greedy IR shrinker (shrink.jl) still runs as a final polish, and remains
# the only shrinker available for journal-recovered crash cases.

using Supposition
using Supposition: Data, TestCase, produce!
import Random

struct TCRNG <: AbstractRNG
    tc::TestCase
end

# The generator only ever draws through these four entry points (genprogram
# and everything below it). Anything else hitting Random's generic sampler
# machinery would bypass choice recording — better to fail loudly.
Random.rand(r::TCRNG) = produce!(r.tc, Data.Integers(0, 1 << 24 - 1)) / Float64(1 << 24)
Random.rand(r::TCRNG, ::Type{Bool}) = produce!(r.tc, Data.Booleans())
function Random.rand(r::TCRNG, u::UnitRange{Int})
    isempty(u) && throw(ArgumentError("empty range draw in generator"))
    return produce!(r.tc, Data.Integers(first(u), last(u)))
end
Random.rand(r::TCRNG, ::Random.SamplerTrivial) =
    error("FuzzJI generator made an RNG draw TCRNG does not route through Supposition")
Random.rand(r::TCRNG, ::Random.SamplerSimple) =
    error("FuzzJI generator made an RNG draw TCRNG does not route through Supposition")

struct ProgramGen <: Data.Possibility{Program}
    cfg::Cfg
end
ProgramGen() = ProgramGen(Cfg())

Supposition.produce!(tc::TestCase, pg::ProgramGen) = genprogram(TCRNG(tc), pg.cfg)

"""
    supposition_campaign(; rounds, examples, nstmts, outdir, cfg) -> nfindings

Run up to `rounds` Supposition `@check` passes of `examples` cases each.
Each round hunts for a divergence not already suppressed, reported on disk,
or found in an earlier round (found fingerprints are filtered in the property
itself, so successive rounds look for *new* findings). A round with no
finding ends the campaign.

Counterexamples are Supposition-shrunk by choice-sequence replay, then
polished by the greedy IR shrinker, and reported through the same
`writefinding` path as the native driver.
"""
function supposition_campaign(; rounds::Int=20, examples::Int=2000, nstmts::Int=300_000,
                              outdir::String=joinpath(@__DIR__, "..", "findings"),
                              journaldir::String=joinpath(@__DIR__, "..", "journal"),
                              cfg::Cfg=Cfg(), doshrink::Bool=true)
    seen = Set{String}()
    isdir(outdir) && for d in readdir(outdir)
        push!(seen, d)
    end
    # Journal every candidate before it runs: an uncatchable crash (e.g. a
    # generated program that traps compiled Julia's codegen) kills the worker,
    # and journal/current.jl is then the only record of what did it.
    j = Journal(journaldir)
    gen = ProgramGen(cfg)
    nfound = 0
    for round in 1:rounds
        # Track the smallest failing program ourselves: robust against
        # Supposition report internals, and lets us reuse writefinding.
        best = Ref{Union{Nothing,Tuple{Program,Verdict}}}(nothing)
        prop = function (prog::Program)
            src = render(prog)
            journal_case!(j, round, src)
            r = run_both(src; nstmts)
            r === nothing && return true
            v = classify(r...)
            (isfinding(v) && !suppressed(v) && !(fingerprint(v) in seen)) || return true
            cur = best[]
            if cur === nothing || length(render(prog)) < length(render(cur[1]))
                best[] = (prog, v)
            end
            return false
        end
        sr = @check max_examples = examples prop(gen)
        b = best[]
        if b === nothing
            @info "supposition round found nothing new; stopping" round examples
            break
        end
        prog, _ = b
        r = run_both(render(prog); nstmts)
        v = classify(r...)   # verdict of the *minimal* program
        fp = fingerprint(v)
        push!(seen, fp)
        nfound += 1
        @info "FINDING (supposition)" round fp v.class detail = first(v.detail, 300)
        shrunk = doshrink ? shrink(prog, fp; nstmts) : prog
        dir = writefinding(outdir, fp, v, -1, render(prog), render(shrunk))
        @info "  reported" dir nstatements_supposition = nstatements(prog) nstatements_polished = nstatements(shrunk)
    end
    close(j)
    return nfound
end
