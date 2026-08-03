# M0 acceptance tests for the harness itself. Run via:
#   julia --project=fuzz fuzz/run.jl --selftest

using Test
using Dates   # for the corpus import-repair assertions
using .FuzzJI
using .FuzzJI: Xoshiro, classify, Outcome, Verdict, fingerprint, isfinding,
               nstatements, Cfg, run_both, run_all, shrink, genprogram, render,
               shrink_ir, ddmin_source, ShrinkBudget, exhausted, toplevel_statements,
               step_program, step_keep, evalcode_probe, evalcode_keep,
               corpus_split, corpus_run, corpusverdict, quiet_stdout, writefinding,
               Ex, St, Program, lit, IntT, SymT
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
        # The config floor: nbodystmts bottoms out at 5, and choice-sequence
        # shrinking drives each toward the first/highest-weighted statement rule
        # (:assignnew), so a minimal program is 5 assignments — each declaring a
        # binding, and every live binding gets a tail observation — hence 10.
        # This is a canary for "shrinking still reaches the floor": if a grammar
        # change moves the floor, re-derive rather than relax it.
        @test supposition_minimal == 10
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
        # Type divergences are findings: `isequal` alone would call all three of
        # these equal, hiding exactly the promotion/conversion bugs a
        # hand-written interpreter is most likely to have.
        @test classify(done(1), done(1.0)).class === :value_divergence
        @test classify(done(true), done(1)).class === :value_divergence
        @test classify(done(Any[1]), done(Any[1.0])).class === :value_divergence
        @test classify(done((1, 2)), done((1, 2.0))).class === :value_divergence
        # ... while same-type, same-value streams (including nested) still agree
        @test classify(done(Any[1, 2]), done(Any[1, 2])).class === :agree
        @test classify(done((1, "a")), done((1, "a"))).class === :agree
        # aborted with matching prefix is a discard, mismatched prefix is real
        aborted(obs...) = Outcome(:aborted, :none, Any[obs...], "", "")
        @test classify(done(1, 2, 3), aborted(1)).class === :aborted
        @test classify(done(1, 2, 3), aborted(7)).class === :value_divergence
    end

    @testset "fingerprints distinguish unrelated value divergences" begin
        done(obs...) = Outcome(:done, :none, Any[obs...], "", "")
        # Different guarded-exception divergences and different value-shape
        # divergences must not collapse into one dedup bucket: the first
        # value_divergence ever reported would otherwise mask all future ones.
        va = classify(done((:__thrown, :BoundsError)), done((:__thrown, :MethodError)))
        vb = classify(done((:__thrown, :BoundsError)), done((:__thrown, :DomainError)))
        vc = classify(done(1), done(2))
        vd = classify(done(1), done(2.0))
        @test fingerprint(va) != fingerprint(vb)
        @test fingerprint(va) != fingerprint(vc)
        @test fingerprint(vc) != fingerprint(vd)
        # ... while identical shapes still dedup
        @test fingerprint(vc) == fingerprint(classify(done(5), done(7)))

        # Exception-class verdicts must not all share one bucket either: with an
        # unsalted (class, refexc, intexc) key, the first interp-only
        # UndefVarError reported would mask every later, unrelated one.
        threw(exc, obs...) = Outcome(:threw, exc, Any[obs...], "", "")
        ta = classify(done(1, :marker_a), threw(:UndefVarError, 1, :marker_a))
        tb = classify(done(1, 99), threw(:UndefVarError, 1, 99))
        @test ta.class === :interp_only_throw && tb.class === :interp_only_throw
        @test fingerprint(ta) != fingerprint(tb)
        # same shape still dedups, so reruns don't re-report one bug forever
        @test fingerprint(tb) == fingerprint(classify(done(1, 7), threw(:UndefVarError, 1, 7)))
    end

    @testset "targeted differential: wave-3 constructs agree" begin
        # Hand-written deterministic programs covering the constructs added in
        # wave 3. These must run (validity) and agree (any divergence here is
        # either a harness bug or a real finding — triage before shipping).
        targeted = [
        "control-flow exits through try/finally in loops" => """
        let
            acc = 0
            for i in 1:4
                try
                    (i == 2) && continue
                    acc = acc + 10
                    (i == 3) && break
                catch err
                    __obs__(:caught)
                finally
                    acc = acc + 1
                end
            end
            __obs__(acc)
            f = function (n)
                t = 0
                for k in 1:n
                    (k > 2) && return t + 100
                    try
                        t = t + k
                        (k == 2) && throw(DomainError(k))
                    catch e
                        (t > 100) && rethrow()
                        t = t + 1000
                    end
                end
                return t
            end
            __obs__(f(1)); __obs__(f(2)); __obs__(f(5))
        end
        """,
        "per-iteration slot reset (NewvarNode)" => """
        let
            for li in 1:3
                if li >= 2
                    __obs__(@isdefined(lx))
                    __obs__(try; (:__v, lx); catch __e; (:__undef, nameof(typeof(__e))) end)
                end
                lx = li * 2
            end
        end
        """,
        "conditionally-defined locals and globals" => """
        u1 = 3
        if u1 > 10
            u2 = 1
        end
        __obs__(@isdefined(u2))
        __obs__(try; u2; catch __e; (:__undef, nameof(typeof(__e))) end)
        let
            if u1 > 1
                u3 = 2
            end
            __obs__(@isdefined(u3))
            __obs__(try; u3; catch __e; (:__undef, nameof(typeof(__e))) end)
        end
        """,
        "atomic struct fields (get/set/modify, aliasing)" => """
        mutable struct AtS
            @atomic fld1::Int64
            fld2::Float64
        end
        let
            s = AtS(1, 2.0)
            @atomic s.fld1 = 5
            @atomic s.fld1 += 3
            __obs__((@atomic s.fld1))
            s.fld2 = 4.5
            __obs__(s.fld2)
            al = s
            @atomic al.fld1 += 1
            __obs__((@atomic s.fld1))
        end
        """,
        "const and typed globals" => """
        const gc1 = 41
        global gt1::Int64 = 0
        function bump()
            global gt1 = gt1 + gc1
            return gt1
        end
        let
            __obs__(bump())
            __obs__(bump())
            __obs__(gt1)
            __obs__(gc1)
        end
        """,
        "try/catch/else and typed locals" => """
        let
            local tl1::Int64 = 2
            r = try
                tl1 + 1
            catch err
                __obs__(:caught)
                -1
            else
                __obs__(:else)
                tl1 + 10
            end
            __obs__(r)
            r2 = try
                throw(ArgumentError("x"))
            catch err
                __obs__(nameof(typeof(err)))
                -2
            else
                __obs__(:noexc)
                -3
            end
            __obs__(r2)
        end
        """,
        "opaque closure / invoke / atomics-builtin probes" => """
        let
            __obs__(try (Base.Experimental.@opaque x -> x + 1)(41) catch __e; (:__thrown, nameof(typeof(__e))) end)
            __obs__(try invoke(abs, Tuple{Int}, -3) catch __e; (:__thrown, nameof(typeof(__e))) end)
            __obs__(try first(Core.modifyfield!(Ref(2), :x, +, 5)) catch __e; (:__thrown, nameof(typeof(__e))) end)
            __obs__(try getfield(Ref(1), :x, :sequentially_consistent) catch __e; (:__thrown, nameof(typeof(__e))) end)
            __obs__(try let m = Memory{Int}(undef, 2); m[1] = 5; m[1] end catch __e; (:__thrown, nameof(typeof(__e))) end)
        end
        """,
        ]
        for (label, src) in targeted
            r = run_both(src; nstmts=2_000_000)
            @test r !== nothing
            r === nothing && continue
            v = classify(r...)
            v.class === :agree ||
                @warn "targeted divergence — triage me" label v.class v.detail
            @test v.class === :agree
        end
    end

    @testset "compiled-mode (NonRecursiveInterpreter) smoke" begin
        ndiverge = 0
        for seed in 1:40
            src = render(genprogram(Xoshiro(seed)))
            r = run_all(src; nstmts=500_000, modes=(:cmp,))
            r === nothing && continue
            ref, intruns = r
            v = classify(ref, intruns[1][2])
            if isfinding(v)
                ndiverge += 1
                @warn "compiled-mode smoke divergence (a real finding — triage it!)" seed v.class v.detail
            end
        end
        @test ndiverge <= 5
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

    @testset "stepping axis agrees with plain interpretation" begin
        # The step axis asserts three invariants: stepping terminates, raises no
        # error from JuliaInterpreter's own code, and reaches the same
        # observations as running. Random command walks over generated programs
        # must satisfy all three — a failure here is a finding against
        # commands.jl/breakpoints.jl, not a harness bug, so it is worth the
        # noise of reporting it loudly.
        nbad = 0
        for seed in 1:20
            src = render(genprogram(Xoshiro(seed)))
            ex = FuzzJI.parsegate(src)
            ex === nothing && continue
            plain = FuzzJI.run_interp(ex; nstmts=500_000)
            st = FuzzJI.step_program(src; walkseed=seed, maxcmds=4000)
            st === nothing && continue
            v = FuzzJI.classify_step(plain, st)
            if v.class !== :agree
                nbad += 1
                @warn "stepping divergence (a real finding — triage it!)" seed v.class v.detail
            end
        end
        @test nbad == 0
    end

    @testset "stepping oracle detects a planted divergence" begin
        # Prove the step oracle can actually fail: compare a program's real
        # observations against a deliberately wrong stepped stream, and against
        # a stepped run that reported an internal error.
        plain = FuzzJI.Outcome(:done, :none, Any[1, 2, 3], "", "")
        wrong = FuzzJI.StepOutcome(:done, Any[1, 99, 3], "", 10, Symbol[])
        @test FuzzJI.classify_step(plain, wrong).class === :step_divergence
        short = FuzzJI.StepOutcome(:done, Any[1, 2], "", 10, Symbol[])
        @test FuzzJI.classify_step(plain, short).class === :step_divergence
        # A command that cannot advance is the reportable shape...
        stuck = FuzzJI.StepOutcome(:stuck, Any[1], "no-ops", 4000, Symbol[], :n)
        @test FuzzJI.classify_step(plain, stuck).class === :step_stuck
        # ... while merely running out of commands is not: break-on-error stops
        # at every throw and these programs throw on purpose, so budget
        # exhaustion is tracked, not reported.
        budget = FuzzJI.StepOutcome(:budget, Any[1], "budget", 4000, Symbol[])
        @test FuzzJI.classify_step(plain, budget).class === :aborted
        @test !FuzzJI.isfinding(FuzzJI.classify_step(plain, budget))
        # An identical stepped stream agrees.
        @test FuzzJI.classify_step(plain, FuzzJI.StepOutcome(:done, Any[1, 2, 3], "", 5, Symbol[])).class === :agree

        # Throw classification is decided by comparing against plain
        # interpretation, NOT by whether the backtrace mentions
        # JuliaInterpreter: a program-thrown exception unwinds through
        # interpreter frames too, so that heuristic alone reports every
        # deliberately-throwing generated program as an interpreter bug.
        threwplain = FuzzJI.Outcome(:threw, :DomainError, Any[1], "", "")
        samethrow = FuzzJI.StepOutcome(:threw, Any[1], "d", 5, Symbol[], :lookup_var, :DomainError)
        @test FuzzJI.classify_step(threwplain, samethrow).class === :agree
        # ... but throwing where plain interpretation completed is a finding,
        # as is throwing something different than plain interpretation does.
        steponly = FuzzJI.StepOutcome(:threw, Any[1, 2, 3], "d", 5, Symbol[], :next_line!, :UndefVarError)
        @test FuzzJI.classify_step(plain, steponly).class === :step_only_throw
        different = FuzzJI.StepOutcome(:threw, Any[1], "d", 5, Symbol[], :next_line!, :BoundsError)
        @test FuzzJI.classify_step(threwplain, different).class === :step_exception_divergence
        # Breakages in different interpreter functions get different buckets.
        other = FuzzJI.StepOutcome(:threw, Any[1, 2, 3], "d", 5, Symbol[], :until_line!, :UndefVarError)
        @test fingerprint(FuzzJI.classify_step(plain, steponly)) !=
              fingerprint(FuzzJI.classify_step(plain, other))
    end

    @testset "corpus axis: filters and oracle" begin
        # Unsafe or non-standalone fragments must never reach execution.
        @test !FuzzJI.corpus_ok(:(ccall(:puts, Cint, (Cstring,), "x")))
        @test !FuzzJI.corpus_ok(:(run(`ls`)))
        @test !FuzzJI.corpus_ok(:(while true; end))
        @test !FuzzJI.corpus_ok(Expr(:using, Expr(:., :Foo)))
        @test !FuzzJI.corpus_ok(Expr(:module, true, :M, Expr(:block)))

        # The filter looks at what is *called*, not at the rendered text, so a
        # qualified or aliased spelling cannot slip past...
        @test FuzzJI.calls_unsafe(:(Base.rm(p)))
        @test FuzzJI.calls_unsafe(:(let; x = 1; Base.Filesystem.mv(a, b); end))
        @test FuzzJI.calls_unsafe(:(@async f()))
        @test FuzzJI.calls_unsafe(:(f(g(open(path)))))     # nested in an argument
        # ... and an innocent name that merely *contains* a dangerous one is not
        # rejected, which substring matching got wrong.
        @test !FuzzJI.calls_unsafe(:(myopen(path)))
        @test !FuzzJI.calls_unsafe(:(x = runtime_value + 1))
        @test FuzzJI.corpus_ok(:(myopen(path)))
        # Callee reduction handles qualified, parameterized and GlobalRef forms.
        @test FuzzJI.calleename(:(Base.Foo.bar)) === :bar
        @test FuzzJI.calleename(:(f{Int})) === :f
        @test FuzzJI.calleename(GlobalRef(Base, :rm)) === :rm
        # Method definitions on another module's function register globally and
        # would leak between cases.
        @test FuzzJI.defines_foreign_method(:(Base.foo(x) = 1))
        @test FuzzJI.defines_foreign_method(:(function Base.bar(x::Int) 1 end))
        @test !FuzzJI.defines_foreign_method(:(localfn(x) = 1))
        @test !FuzzJI.corpus_ok(:(Base.foo(x) = 1))
        # ... while ordinary code is kept.
        @test FuzzJI.corpus_ok(:(function f(x); x + 1; end))
        @test FuzzJI.corpus_ok(:(const zzz = [i^2 for i in 1:3]))

        # A fragment compiled Julia cannot run either is junk, not a finding:
        # this is what stops "@testset not defined" being reported as a bug.
        junk = FuzzJI.CorpusOutcome(:junk, "reference threw UndefVarError", :none)
        @test FuzzJI.corpusverdict(junk).class === :agree
        real = FuzzJI.CorpusOutcome(:internal_error, "interp threw", :step_expr!)
        @test FuzzJI.corpusverdict(real).class === :corpus_internal_error
        # An actual round trip: a self-contained fragment must run on both
        # sides, and one that needs a missing name must be discarded.
        @test FuzzJI.corpus_run(Expr(:toplevel, :(zqx = 1 + 1)), Expr[]; nstmts=100_000).status === :ok
        # A name nothing can supply stays junk...
        @test FuzzJI.corpus_run(Expr(:toplevel, :(znotdefined_xyz + 1)), Expr[]; nstmts=100_000).status === :junk

        # ... but a name some loaded module *does* export is repaired rather
        # than discarded. Fragments lifted from a test file rarely carry the
        # import they need (their runtests.jl did the `using`), so the missing
        # import is recovered from the UndefVarError itself instead of from a
        # hardcoded list of stdlibs.
        @test FuzzJI.supplying_module(:Date) === Dates
        @test FuzzJI.supplying_module(Symbol("@testset")) === Test
        @test FuzzJI.supplying_module(:znotdefined_xyz) === nothing
        needsdates = Expr(:toplevel, :(zdt = Date(2020, 1, 1)))
        o = FuzzJI.corpus_run(needsdates, Expr[]; nstmts=100_000)
        @test o.status === :ok
        # and the repaired prelude is handed on, so the stepping stage runs in
        # the same environment the reference succeeded in
        @test any(isequal(:(using Dates)), o.prelude)
    end

    @testset "eval_code axis: probe selection and verdicts" begin
        Variable = FuzzJI.Variable
        # Plumbing names and non-scalar values are not round-trip candidates.
        @test !FuzzJI.probeable(Variable(1, Symbol("#self#")))
        @test !FuzzJI.probeable(Variable([1, 2], :v))
        @test FuzzJI.probeable(Variable(1, :x))
        @test FuzzJI.probeable(Variable("s", :y))
        # Write probes stay in the original type, so the round trip tests the
        # write-back plumbing rather than conversion.
        rng = Xoshiro(1)
        @test FuzzJI.writeprobe(rng, 3) isa Int
        @test FuzzJI.writeprobe(rng, 1.5) isa Float64
        @test FuzzJI.writeprobe(rng, true) isa Bool
        @test FuzzJI.writeprobe(rng, [1]) === nothing   # unsupported: skipped
        # Verdict mapping, including the collateral-write class that catches a
        # write landing in the wrong slot.
        @test FuzzJI.evalverdict(FuzzJI.EvalOutcome(:ok, "", :none, 3)).class === :agree
        @test FuzzJI.evalverdict(FuzzJI.EvalOutcome(:write_lost, "d", :none, 3)).class ===
              :evalcode_write_lost
        @test FuzzJI.evalverdict(FuzzJI.EvalOutcome(:collateral_write, "d", :none, 3)).class ===
              :evalcode_collateral_write
        @test FuzzJI.evalverdict(FuzzJI.EvalOutcome(:internal_error, "d", :eval_code, 3)).class ===
              :evalcode_internal_error
    end

    @testset "eval_code agrees with the frame's own locals" begin
        # The real oracle, on real frames: every local eval_code reports must
        # match what the interpreter holds, and a write must round-trip without
        # disturbing any other local.
        nbad = 0
        for seed in 1:12
            src = render(genprogram(Xoshiro(seed)))
            ex = FuzzJI.parsegate(src)
            ex === nothing && continue
            m = FuzzJI.freshmodule()
            try
                for (mod, frag) in FuzzJI.ExprSplitter(m, ex)
                    fr = FuzzJI.Frame(mod, frag)
                    for _ in 1:15
                        FuzzJI.is_toplevel_frame(fr) && (fr.world = Base.get_world_counter())
                        o = FuzzJI.check_evalcode(Xoshiro(seed), fr)
                        if o.status !== :ok
                            nbad += 1
                            @warn "eval_code divergence (a real finding — triage it!)" seed o.status o.detail
                            break
                        end
                        ret = try
                            FuzzJI.debug_command(FuzzJI.RecursiveInterpreter(), fr, :se, true)
                        catch
                            nothing
                        end
                        ret === nothing && break
                        fr, _pc = ret
                    end
                end
            catch
                # the program's own errors end the walk; not this test's concern
            end
        end
        @test nbad == 0
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
        # Embed the canary divergence in deterministic, guaranteed-clean noise,
        # then shrink. Hand-built (not generated) so the fixture can't randomly
        # throw before reaching the canary; the shrinker must strip the inert
        # assignments and leave the one divergent observation.
        Ex, St = FuzzJI.Ex, FuzzJI.St
        IntT = FuzzJI.IntT
        inert(i) = St(:assign, (Symbol("z", i), IntT, true, false); exs=[FuzzJI.lit(i, IntT)])
        canaryst = St(:observe; exs=[Ex(:stackprobe, FuzzJI.BoolT, nothing, FuzzJI.Ex[])])
        noise = St[inert(i) for i in 1:12]
        newbody = vcat(noise[1:6], [canaryst], noise[7:12])
        prog = FuzzJI.Program(St[], St[], St[], newbody)
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

    # -- the predicate shrinker, exercised without needing a real bug --------
    # `shrink_ir` takes the property as `keep(src)::Bool`, so it can be tested
    # against a synthetic one. A pure string-containment predicate isolates the
    # *search* (statement removal, simplification, repair, budget) from any
    # axis's oracle: if these fail, the shrinker is broken, not the oracle.
    marker = St(:observe; exs=[lit(:zzmarker, SymT)])
    inertst(i) = St(:assign, (Symbol("zz", i), IntT, true, false); exs=[lit(i, IntT)])
    padded(k) = Program(St[], St[], St[],
                        vcat(St[inertst(i) for i in 1:k], [marker], St[inertst(i) for i in k+1:2k]))

    @testset "predicate shrinker minimizes against an arbitrary property" begin
        prog = padded(10)                      # 20 inert statements around the marker
        keepmarker = src -> occursin("__obs__(:zzmarker)", src)
        budget = ShrinkBudget(; maxruns=500, seconds=60)
        shrunk = shrink_ir(prog, keepmarker; budget)
        @test nstatements(shrunk) < nstatements(prog)
        @test nstatements(shrunk) <= 3          # the marker, and essentially nothing else
        # The property must still hold, and — this is what repair buys — the
        # result must still be a *valid program*, not just a string that happens
        # to contain the marker.
        src = render(shrunk)
        @test keepmarker(src)
        lwr = Meta.lower(Main, Meta.parseall(src))
        @test !(Meta.isexpr(lwr, :error) || Meta.isexpr(lwr, :incomplete))
        # A property nothing satisfies leaves the program untouched rather than
        # returning something the predicate rejected.
        @test nstatements(shrink_ir(prog, _ -> false;
                                    budget=ShrinkBudget(; maxruns=40, seconds=60))) ==
              nstatements(prog)
    end

    @testset "shrink budget caps the work spent on one finding" begin
        prog = padded(10)
        budget = ShrinkBudget(; maxruns=7, seconds=60)
        shrink_ir(prog, src -> occursin("__obs__(:zzmarker)", src); budget)
        @test budget.runs <= 7
        @test exhausted(budget)
        # A wall-clock cap stops it too, even with runs to spare.
        tbudget = ShrinkBudget(; maxruns=10_000, seconds=0.0)
        shrink_ir(prog, src -> occursin("__obs__(:zzmarker)", src); budget=tbudget)
        @test tbudget.runs == 0
        @test exhausted(tbudget)
    end

    @testset "ddmin shrinks source text at statement granularity" begin
        # Corpus findings are real code, not generator IR, so they are minimized
        # by delta debugging over parsed statements — crashmin.jl's loop, made
        # reusable and given the same keep-predicate interface.
        src = """
        zd1 = 1
        zd2 = 2
        function zdf(x)
            q1 = x + 1
            q2 = q1 * 2
            zdmarker = q2
            q3 = zdmarker
            return q3
        end
        zd3 = 3
        """
        budget = ShrinkBudget(; maxruns=400, seconds=60)
        out = ddmin_source(src, s -> occursin("zdmarker", s); budget)
        @test occursin("zdmarker", out)
        @test length(toplevel_statements(out)) == 1          # only `zdf` survives
        @test !occursin("zd1", out) && !occursin("zd3", out)
        # ... and the recursion into block bodies removed the statements inside
        # `zdf` that the property does not need.
        @test !occursin("q3", out)
        @test count(==('\n'), out) < count(==('\n'), src)
        # Line-number comments from the reparse are stripped, not printed.
        @test !occursin("#=", out)
        # A property that does not hold at all leaves the source alone.
        @test ddmin_source(src, _ -> false;
                           budget=ShrinkBudget(; maxruns=40, seconds=60)) == src
    end

    @testset "step walks replay from their own seed" begin
        # The walk used to continue the generator's RNG stream, which made the
        # command sequence a function of the program's size: deleting a
        # statement changed every later draw, so no shrunk candidate could be
        # judged. It now draws from `Xoshiro(walkseed)`, so `(src, walkseed)`
        # fully describes a run and a shrunk candidate replays the same seed.
        src = render(genprogram(Xoshiro(3)))
        a = step_program(src; walkseed=77, maxcmds=1500)
        b = step_program(src; walkseed=77, maxcmds=1500)
        @test a !== nothing && b !== nothing
        @test a.status === b.status
        @test a.ncommands == b.ncommands
        @test isequal(a.obs, b.obs)
        # The same walk seed applies unchanged to a *different* (here, shorter)
        # program — which is the property the shrink predicate relies on.
        @test step_program(render(genprogram(Xoshiro(4))); walkseed=77, maxcmds=1500) !== nothing
        # The axis predicates are conservative: a program with no finding must
        # never be reported as preserving one.
        @test !step_keep("step_stuck-deadbeef"; walkseed=77, nstmts=500_000,
                         maxcmds=1500, usebreakpoints=false)(src)
    end

    @testset "eval_code probes replay from their own seed" begin
        src = render(genprogram(Xoshiro(5)))
        a = evalcode_probe(src; walkseed=99, pausesper=10)
        b = evalcode_probe(src; walkseed=99, pausesper=10)
        @test a !== nothing && b !== nothing
        @test a.status === b.status
        @test a.nchecks == b.nchecks
        @test a.nchecks > 0        # the axis actually checked something
        @test !evalcode_keep("evalcode_write_lost-deadbeef"; walkseed=99,
                             nstmts=500_000, pausesper=10)(src)
    end

    @testset "corpus findings shrink through the same interface" begin
        # A corpus case is `prelude ++ fragments` as toplevel statements; the
        # predicate re-splits a candidate and re-runs the pipeline, so deleting
        # an import the fragment needs simply makes the case junk and the edit is
        # rejected. (Here the import is recovered by corpus_run's own repair,
        # which is why `using Dates` is droppable.)
        src = """
        using Dates
        zc1 = 1 + 1
        zc2 = [i^2 for i in 1:3]
        function zcf(x)
            y = x + 1
            zcmarker = Date(2020, 1, 1)
            y
        end
        zc3 = zcf(2)
        """
        sp = corpus_split(src)
        @test sp !== nothing
        @test any(isequal(:(using Dates)), sp[2])
        @test length(sp[1].args) == 4          # prelude removed from the case
        keep = function (s::String)
            occursin("zcmarker", s) || return false
            p = corpus_split(s)
            p === nothing && return false
            o = quiet_stdout() do
                corpus_run(p[1], p[2]; nstmts=100_000)
            end
            return o.status === :ok
        end
        budget = ShrinkBudget(; maxruns=200, seconds=90)
        out = ddmin_source(src, keep; budget)
        @test count(==('\n'), out) < count(==('\n'), src)
        @test keep(out)                        # never returns a rejected candidate
    end

    @testset "step-axis findings are written shrunk" begin
        # End-to-end through the axis's real machinery, with a deliberately
        # broken oracle standing in for a bug that does not exist: plain
        # interpretation is made to *lie* about the marker observation, so any
        # program that observes the marker classifies as a genuine
        # `step_divergence`. Everything else is the production path — replay the
        # walk from `walkseed`, classify against plain interpretation, require
        # the same fingerprint — so this covers generate → step → classify →
        # shrink → writefinding without waiting for a live finding.
        WALKSEED = 4242
        prog = padded(7)
        orig = render(prog)
        # `keep` for a given fingerprint, exactly the shape of `step_keep`.
        stubverdict = function (s::String)
            ex = FuzzJI.parsegate(s)
            ex === nothing && return nothing
            plain = FuzzJI.run_interp(ex; nstmts=500_000)
            lying = FuzzJI.Outcome(plain.status, plain.excname,
                                   Any[x === :zzmarker ? :notmarker : x for x in plain.obs],
                                   "", "")
            st = step_program(s; walkseed=WALKSEED, maxcmds=600)
            st === nothing && return nothing
            return FuzzJI.classify_step(lying, st)
        end
        v0 = stubverdict(orig)
        @test v0 !== nothing && v0.class === :step_divergence
        fp0 = fingerprint(v0)
        stubkeep = function (s::String)
            v = stubverdict(s)
            return v !== nothing && isfinding(v) && fingerprint(v) == fp0
        end
        budget = ShrinkBudget(; maxruns=200, seconds=90)
        shrunk = render(shrink_ir(prog, stubkeep; budget))
        @test length(shrunk) < length(orig)
        # The shrunk program still reproduces the *same class and salt* under a
        # replay of the same walk seed — the criterion the real predicate uses.
        @test stubkeep(shrunk)
        @test fingerprint(stubverdict(shrunk)) == fp0
        # writefinding records both programs plus the walk seed, so the report
        # describes the run and not just the source.
        mktempdir() do dir
            d = writefinding(dir, "step-stub", v0, 1, orig, shrunk; mode=:step, walkseed=WALKSEED)
            meta = read(joinpath(d, "meta.md"), String)
            @test occursin("walk seed: `$WALKSEED`", meta)
            @test occursin(shrunk, meta) && occursin(orig, meta)
            @test occursin("# walk seed: $WALKSEED", read(joinpath(d, "repro.jl"), String))
        end
        @info "step-axis shrink (stub oracle)" runs = budget.runs
        @info "  before" src = orig
        @info "  after" src = shrunk
    end

end
