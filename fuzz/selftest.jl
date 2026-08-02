# M0 acceptance tests for the harness itself. Run via:
#   julia --project=fuzz fuzz/run.jl --selftest

using Test
using .FuzzJI
using .FuzzJI: Xoshiro, classify, Outcome, Verdict, fingerprint, isfinding,
               nstatements, Cfg, run_both, shrink, genprogram, render
using Supposition: example, @check, Data   # Data must be in scope for @check-expanded code

# The Supposition probes run at file scope, *outside* the testset below: a
# deliberately failing `@check` inside a parent testset would record failures
# into the suite. Standalone, it just returns its report.
supposition_valid = let nbad = 0
    for _ in 1:30
        src = render(example(ProgramGen()))
        lwr = Meta.lower(Main, Meta.parseall(src))
        (Meta.isexpr(lwr, :error) || Meta.isexpr(lwr, :incomplete)) && (nbad += 1)
    end
    nbad == 0
end

supposition_minimal = let smallest = Ref{Any}(nothing)
    # Impossible-to-satisfy property: every program has >= 5 body statements
    # + 3 observations, so this must fail — and shrink toward that floor.
    prop = function (prog)
        if smallest[] === nothing || nstatements(prog) < nstatements(smallest[])
            smallest[] = prog
        end
        return false
    end
    @check max_examples = 100 prop(ProgramGen())
    smallest[] === nothing ? typemax(Int) : nstatements(smallest[])
end

@testset "FuzzJI selftest" begin

    @testset "supposition engine" begin
        @test supposition_valid
        # the config floor is 5 body statements + 3 tail observations
        @test supposition_minimal == 8
    end

    @testset "generator determinism" begin
        for seed in (1, 42, 99)
            a = render(genprogram(Xoshiro(seed)))
            b = render(genprogram(Xoshiro(seed)))
            @test a == b
        end
    end

    @testset "generated programs are valid by construction" begin
        nbad = 0
        for seed in 1:300
            src = render(genprogram(Xoshiro(seed)))
            ex = try
                Meta.parseall(src)
            catch
                nbad += 1
                @error "parse failure" seed src
                continue
            end
            lwr = Meta.lower(Main, ex)
            if Meta.isexpr(lwr, :error) || Meta.isexpr(lwr, :incomplete)
                nbad += 1
                @error "lowering failure" seed lwr src
            end
        end
        @test nbad == 0
    end

    @testset "comparator classifies synthetic outcomes" begin
        done(obs...) = Outcome(:done, :none, Any[obs...], "", "")
        threw(exc, obs...) = Outcome(:threw, exc, Any[obs...], "", "")
        @test classify(done(1, 2), done(1, 2)).class === :agree
        @test classify(done(1, 2), done(1, 3)).class === :value_divergence
        @test classify(done(1, 2), done(1, 3)).dividx == 2
        @test classify(done(1), done(1, 2)).class === :value_divergence
        @test classify(threw(:DomainError, 1), threw(:DomainError, 1)).class === :agree
        @test classify(threw(:DomainError), threw(:BoundsError)).class === :exception_divergence
        @test classify(done(1), threw(:UndefVarError, 1)).class === :interp_only_throw
        @test classify(threw(:DomainError, 1), done(1)).class === :ref_only_throw
        # NaN must compare equal to itself; 0.0 and -0.0 must differ
        @test classify(done(NaN), done(NaN)).class === :agree
        @test classify(done(0.0), done(-0.0)).class === :value_divergence
        # aborted with matching prefix is a discard, mismatched prefix is real
        aborted(obs...) = Outcome(:aborted, :none, Any[obs...], "", "")
        @test classify(done(1, 2, 3), aborted(1)).class === :aborted
        @test classify(done(1, 2, 3), aborted(7)).class === :value_divergence
    end

    @testset "differential smoke test (agreement on real programs)" begin
        ndiverge = 0
        for seed in 1:40
            src = render(genprogram(Xoshiro(seed)))
            r = run_both(src; nstmts=500_000)
            r === nothing && continue
            v = classify(r...)
            if isfinding(v)
                ndiverge += 1
                @warn "smoke test found a divergence (a real finding — triage it!)" seed v.class v.detail
            end
        end
        # Divergences here are findings against JuliaInterpreter, not harness bugs;
        # they should be rare enough that the smoke test still validates the plumbing.
        @test ndiverge <= 5
    end

    @testset "canary: pipeline detects a genuine known divergence" begin
        # Interpreted frames are visible in stacktrace(); compiled ones are not.
        # This is a real, permanent difference — perfect for proving the whole
        # pipeline (execute → observe → classify) can detect divergence.
        canary = """
        let
            v1 = any(fr -> occursin("interpret", String(fr.file)), stacktrace())
            __obs__(v1)
        end
        """
        r = run_both(canary; nstmts=500_000)
        @test r !== nothing
        v = classify(r...)
        @test v.class === :value_divergence
        @test v.dividx == 1
    end

    @testset "shrinker reduces while preserving the finding" begin
        # Embed the canary divergence in generated noise, then shrink.
        noisy = genprogram(Xoshiro(7))
        canaryst = FuzzJI.St(:observe; exs=[FuzzJI.Ex(:stackprobe, FuzzJI.BoolT, nothing, FuzzJI.Ex[])])
        prog = FuzzJI.Program(noisy.fundefs, vcat(noisy.body[1:end-1], [canaryst], noisy.body[end:end]))
        r = run_both(render(prog); nstmts=2_000_000)
        @test r !== nothing
        v = classify(r...)
        @test isfinding(v)
        fp = fingerprint(v)
        shrunk = shrink(prog, fp; nstmts=2_000_000)
        @test nstatements(shrunk) < nstatements(prog)
        r2 = run_both(render(shrunk); nstmts=2_000_000)
        v2 = classify(r2...)
        @test isfinding(v2) && fingerprint(v2) == fp
        @info "shrinker" before = nstatements(prog) after = nstatements(shrunk) src = render(shrunk)
    end

end
