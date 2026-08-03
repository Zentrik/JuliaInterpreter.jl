# Campaign driver: generate → journal → execute → classify → dedup → shrink →
# report.

Base.@kwdef mutable struct Stats
    cases::Int = 0
    agreed::Int = 0
    aborted::Int = 0
    discarded::Int = 0
    findings::Int = 0
    duplicates::Int = 0
    suppressed::Int = 0
end

# Known, already-reported divergences go here so reruns surface only news.
# Each entry is a predicate over Verdict.
const SUPPRESSIONS = Function[]

suppressed(v::Verdict) = any(p -> p(v)::Bool, SUPPRESSIONS)

function writefinding(outdir::String, fp::String, v::Verdict, seed::Int,
                      origsrc::String, shrunksrc::String; mode::Symbol=:rec)
    dir = joinpath(outdir, fp)
    mkpath(dir)
    # The split axis's verdicts are mostly about the *module tree*, so its
    # reproducer has to compare that too — `reprorun` only diffs observations.
    reprocall = mode === :cmp   ? "reprorun(SRC; compiled=true)" :
                mode === :split ? "reprosplit(SRC)" : "reprorun(SRC)"
    open(joinpath(dir, "repro.jl"), "w") do io
        print(io, """
        # FuzzJI reproducer — $(v.class) (interp mode: $mode)
        # seed: $seed
        # julia: $VERSION
        # detail: $(replace(v.detail, '\n' => ' '))
        # Run with: julia --project=<repo>/fuzz <this file>
        include(joinpath(@__DIR__, "..", "..", "reprolib.jl"))
        const SRC = $(repr(shrunksrc))
        $reprocall
        """)
    end
    open(joinpath(dir, "meta.md"), "w") do io
        print(io, """
        # $(v.class) ($fp)

        - seed: `$seed`
        - interp mode: `$mode`
        - julia: `$VERSION`
        - divergent observation index: $(v.dividx)
        - ref exception: `$(v.refexc)`  interp exception: `$(v.intexc)`

        ## Detail

        ```
        $(v.detail)
        ```

        ## Shrunk program

        ```julia
        $shrunksrc
        ```

        ## Original program

        ```julia
        $origsrc
        ```
        """)
    end
    return dir
end

# Mode tag prefix for dedup/report dirs (:rec is the historical untagged form).
tagfp(mode::Symbol, fp::String) = mode === :rec ? fp : string(mode, "-", fp)

function campaign(; n::Int=1000, baseseed::Int=1, nstmts::Int=300_000,
                  outdir::String=joinpath(@__DIR__, "..", "findings"),
                  journaldir::String=joinpath(@__DIR__, "..", "journal"),
                  cfg::Cfg=Cfg(), progress::Int=200, doshrink::Bool=true,
                  modes::Tuple=(:rec, :cmp), seeddisk::Bool=true, journalsync::Bool=true)
    j = Journal(journaldir; sync=journalsync)
    stats = Stats()
    seen = Set{String}()
    # Pre-seed dedup with findings already on disk so restarts don't re-report.
    # Fingerprint buckets are coarse, so this also suppresses *unrelated* bugs
    # that happen to share a bucket with something already reported — pass
    # seeddisk=false (CLI --fresh) to hunt within already-reported buckets.
    seeddisk && isdir(outdir) && for d in readdir(outdir)
        push!(seen, d)
    end
    t0 = time()
    try
        for i in 1:n
            seed = baseseed + i - 1
            prog = genprogram(Xoshiro(seed), cfg)
            src = render(prog)
            journal_case!(j, seed, src)
            stats.cases += 1
            r = run_all(src; nstmts, modes)
            if r === nothing
                stats.discarded += 1
                continue
            end
            ref, intruns = r
            anyaborted = anyfinding = false
            for (mode, int) in intruns
                v = classify(ref, int)
                if v.class === :agree
                    continue
                elseif v.class === :aborted
                    anyaborted = true
                elseif suppressed(v)
                    anyfinding = true
                    stats.suppressed += 1
                else
                    anyfinding = true
                    fp = tagfp(mode, fingerprint(v))
                    if fp in seen
                        stats.duplicates += 1
                    else
                        push!(seen, fp)
                        stats.findings += 1
                        @info "FINDING $(v.class)" mode seed fp detail = first(v.detail, 300)
                        shrunk = doshrink ? shrink(prog, fingerprint(v); nstmts, interp=modeinterp(mode)) : prog
                        dir = writefinding(outdir, fp, v, seed, src, render(shrunk); mode)
                        @info "  reported" dir nstatements_orig = nstatements(prog) nstatements_shrunk = nstatements(shrunk)
                    end
                end
            end
            # per-case rollup: a case counts once, worst class wins
            anyfinding ? nothing : anyaborted ? (stats.aborted += 1) : (stats.agreed += 1)
            if progress > 0 && i % progress == 0
                rate = round(stats.cases / (time() - t0); digits=1)
                abortpct = round(100 * stats.aborted / max(1, stats.cases); digits=1)
                @info "progress" i rate_per_s = rate abort_pct = abortpct stats.agreed stats.aborted stats.discarded stats.findings stats.duplicates
            end
        end
    finally
        close(j)
    end
    return stats
end
