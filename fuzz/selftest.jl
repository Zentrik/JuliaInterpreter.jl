# M0 acceptance tests for the harness itself. Run via:
#   julia --project=fuzz fuzz/run.jl --selftest

using Test
using Dates   # for the corpus import-repair assertions
using .FuzzJI
using .FuzzJI: Xoshiro, classify, Outcome, Verdict, fingerprint, isfinding,
               nstatements, Cfg, run_both, run_all, shrink, genprogram, render
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

    @testset "builtin prober: enumeration is version-relative and complete" begin
        # The floor guards against the enumeration silently collapsing (a
        # renamed reflection API, a `names(...)` filter that stops matching):
        # a prober that enumerates nothing looks exactly like a clean run.
        @test FuzzJI.nprobe_enumerated() >= 150
        @test length(FuzzJI.PROBE_TARGETS) >= 100
        spellings = Set(t.spelling for t in FuzzJI.PROBE_TARGETS)
        # Known targets, one per enumeration source: a Base-spelled builtin, a
        # Core-spelled builtin, an intrinsic.
        @test "getfield" in spellings
        @test "Core.apply_type" in spellings
        @test "Core.Intrinsics.add_int" in spellings
        @test "Core.getfield" in spellings
        # Arities come from the compiler's own tfunc tables, like
        # bin/generate_builtins.jl's per-arity clauses do.
        gf = FuzzJI.probetarget("Core.getfield")
        @test gf !== nothing && (gf.minarg, gf.maxarg) == (2, 4)
        # Every intrinsic must have a pinned arity: a wrong operand count is a
        # codegen abort, not a catchable error (see probes.jl).
        @test all(t -> t.maxarg < typemax(Int) && t.minarg <= t.maxarg,
                  FuzzJI.PROBE_INTRINSIC_TARGETS)
        # The denylist is load-bearing, so it must be populated and every entry
        # must carry a reason a human can act on.
        @test FuzzJI.nprobe_denied() >= 15
        @test all(!isempty(r) for (_, _, r) in FuzzJI.PROBE_DENIED)
        @test all(!isempty(b.reason) for b in FuzzJI.PROBE_BANS)
        deniednames = Set(n for (_, n, _) in FuzzJI.PROBE_DENIED)
        for n in (:sdiv_int, :udiv_int, :srem_int, :urem_int,   # uncatchable SIGILL
                  :pointerref, :pointerset, :llvmcall, :cglobal, # raw addresses
                  :finalizer)                                    # GC-scheduled
            @test n in deniednames
        end
        # ... while the *checked* division family is deliberately kept: measured
        # on 1.11.9 it raises DivideError even when compiled.
        @test !(:checked_sdiv_int in deniednames)
        @test FuzzJI.probetarget("Core.Intrinsics.checked_sdiv_int") !== nothing
        # Recipe-only targets are unreachable without a recipe, so each needs one.
        @test all(haskey(FuzzJI.PROBE_RECIPES, t.name)
                  for t in FuzzJI.PROBE_TARGETS if t.reciponly)
        @test FuzzJI.nprobe_reciponly() >= 3
    end

    @testset "builtin prober: no denylisted callee is ever rendered" begin
        # Render probe-heavy programs across many seeds and check that not one
        # denied name appears in call position. Matching excludes an
        # identifier character before the name — so an allowed
        # `checked_sdiv_int(...)` is not mistaken for a banned `sdiv_int(...)`,
        # which is exactly what substring matching gets wrong — but *allows* a
        # `.`, so a qualified `Core.Intrinsics.sdiv_int(...)` is still caught.
        pats = [(String(n), Regex("(?<![A-Za-z0-9_])" * String(n) * "\\("))
                for n in unique(n for (_, n, _) in FuzzJI.PROBE_DENIED)]
        # The pattern must behave: banned name qualified => hit, allowed name
        # that merely contains a banned one => miss.
        divre = last(first(p for p in pats if first(p) == "sdiv_int"))
        @test occursin(divre, "x = Core.Intrinsics.sdiv_int(1, 0)")
        @test !occursin(divre, "x = Core.Intrinsics.checked_sdiv_int(1, 0)")
        offenders = String[]
        nguards = 0
        for seed in 1:300
            prog = FuzzJI.genprogram_policy(Xoshiro(seed), Cfg(), :builtins)
            src = render(prog)
            nguards += count(_ -> true, eachmatch(r"catch __e", src))
            for (name, re) in pats
                occursin(re, src) && push!(offenders, "seed $seed: $name")
            end
        end
        isempty(offenders) || @error "denylisted callee rendered" offenders
        @test isempty(offenders)
        # The check is only meaningful if guarded probes were actually
        # generated (guarded indexing/division share the wrapper, so this is a
        # floor, not a probe count — metrics.jl reports the exact density).
        @test nguards > 300
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

    @testset "probe-heavy programs execute without taking the worker down" begin
        # Probes are the one rule family whose failure mode is a *dead process*
        # rather than a finding: a raw machine divide, a wild memory read, an
        # intrinsic call site codegen refuses to compile. This batch runs
        # probe-heavy programs through the real differential runner, in
        # process, so a denylist regression shows up here as a crashed
        # selftest rather than as a mysteriously truncated campaign.
        #
        # The seed range is fixed and verified clean. It is deliberately small:
        # a wider sweep belongs in a restart-looping campaign (longrun.sh, plus
        # the crash-safe journal), because generated `@atomic` structs can hit
        # the known Julia 1.11 llvm-alloc-opt abort
        # (findings/julia-codegen-abort-allocopt) — a reference-side *Julia*
        # bug, which kills any in-process batch no matter how good the
        # denylist is.
        nbadgate = 0; nran = 0; ndiverge = 0
        for seed in 1:50
            src = render(FuzzJI.genprogram_policy(Xoshiro(seed), Cfg(), :builtins))
            r = run_all(src; nstmts=500_000, modes=(:rec, :cmp))
            if r === nothing
                nbadgate += 1
                @error "probe-heavy program failed the parse/lowering gate" seed src
                continue
            end
            nran += 1
            ref, intruns = r
            for (mode, out) in intruns
                v = classify(ref, out)
                if isfinding(v)
                    ndiverge += 1
                    @warn "probe divergence (a real finding — triage it!)" seed mode v.class v.detail
                end
            end
        end
        # Validity by construction has to hold for probes too: they are
        # rendered source like everything else.
        @test nbadgate == 0
        @test nran == 50
        @test ndiverge <= 2
    end

    @testset "recipe'd probes reach success paths, not just error arms" begin
        # A prober that only ever produces MethodError/TypeError has tested the
        # *guard*, not the builtin. Force recipes for the high-value builtins
        # and require that a real share of the observations are values.
        St = FuzzJI.St
        ctx = FuzzJI.Ctx(Xoshiro(4), Cfg())
        wanted = [:getfield, :tuple, :fieldtype, :isdefined, :apply_type, :setfield!,
                  :_apply_iterate, :invoke, :swapfield!, :modifyfield!, :replacefield!,
                  :setfieldonce!, :invokelatest, :memoryrefget, :getglobal, :typeassert,
                  :svec, :ifelse, :applicable, :compilerbarrier]
        body = St[]
        for nm in wanted
            ts = FuzzJI.probetargets(nm)
            isempty(ts) && continue
            for _ in 1:6
                t = ts[rand(Xoshiro(hash((nm, length(body)))), 1:length(ts))]
                push!(body, St(:observe; exs=[FuzzJI.genprobe_target(ctx, t; forcerecipe=true)]))
            end
        end
        @test length(body) >= 100
        prog = FuzzJI.Program(FuzzJI.St[], FuzzJI.St[], FuzzJI.St[], body)
        src = render(prog)
        r = run_both(src; nstmts=2_000_000)
        @test r !== nothing
        ref, int = r
        v = classify(ref, int)
        v.class === :agree || @warn "recipe probe divergence — triage me" v.class v.detail
        @test v.class === :agree
        thrown(o) = o isa Tuple && length(o) >= 1 && o[1] === :__thrown
        nvalue = count(!thrown, ref.obs)
        @info "recipe'd probes" observations = length(ref.obs) values = nvalue
        # Half the recipes deliberately probe wrong arities and ordering
        # violations, so the bar is "a substantial minority succeeds", not all.
        @test nvalue >= div(length(ref.obs), 4)
        @test nvalue >= 25
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
            st = FuzzJI.step_program(src; rng=Xoshiro(seed), maxcmds=4000)
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

end
