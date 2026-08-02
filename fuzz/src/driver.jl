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
                      origsrc::String, shrunksrc::String)
    dir = joinpath(outdir, fp)
    mkpath(dir)
    open(joinpath(dir, "repro.jl"), "w") do io
        print(io, """
        # FuzzJI reproducer — $(v.class)
        # seed: $seed
        # julia: $VERSION
        # detail: $(replace(v.detail, '\n' => ' '))
        # Run with: julia --project=<repo>/fuzz <this file>
        include(joinpath(@__DIR__, "..", "..", "reprolib.jl"))
        const SRC = $(repr(shrunksrc))
        reprorun(SRC)
        """)
    end
    open(joinpath(dir, "meta.md"), "w") do io
        print(io, """
        # $(v.class) ($fp)

        - seed: `$seed`
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

function campaign(; n::Int=1000, baseseed::Int=1, nstmts::Int=300_000,
                  outdir::String=joinpath(@__DIR__, "..", "findings"),
                  journaldir::String=joinpath(@__DIR__, "..", "journal"),
                  cfg::Cfg=Cfg(), progress::Int=200, doshrink::Bool=true)
    j = Journal(journaldir)
    stats = Stats()
    seen = Set{String}()
    # pre-seed dedup with findings already on disk so restarts don't re-report
    isdir(outdir) && for d in readdir(outdir)
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
            r = run_both(src; nstmts)
            if r === nothing
                stats.discarded += 1
                continue
            end
            v = classify(r...)
            if v.class === :agree
                stats.agreed += 1
            elseif v.class === :aborted
                stats.aborted += 1
            elseif suppressed(v)
                stats.suppressed += 1
            else
                fp = fingerprint(v)
                if fp in seen
                    stats.duplicates += 1
                else
                    push!(seen, fp)
                    stats.findings += 1
                    @info "FINDING $(v.class)" seed fp detail = first(v.detail, 300)
                    shrunk = doshrink ? shrink(prog, fp; nstmts) : prog
                    dir = writefinding(outdir, fp, v, seed, src, render(shrunk))
                    @info "  reported" dir nstatements_orig = nstatements(prog) nstatements_shrunk = nstatements(shrunk)
                end
            end
            if progress > 0 && i % progress == 0
                rate = round(stats.cases / (time() - t0); digits=1)
                @info "progress" i rate_per_s = rate stats.agreed stats.aborted stats.discarded stats.findings stats.duplicates
            end
        end
    finally
        close(j)
    end
    return stats
end
