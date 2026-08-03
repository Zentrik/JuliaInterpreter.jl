# The enter_call axis: fuzz the *public entry points* with synthesized calls.
#
# Why this exists. Every other axis reaches the interpreter through the
# harness's own plumbing (`ExprSplitter` + `Frame` + the budgeted executor),
# so the entry points a real user calls — `enter_call`, `prepare_args`,
# `prepare_call`, `prepare_frame`, `debug_command` on a *method* frame,
# `get_return` — had literally zero coverage (coverage-report.md: `enter_call`,
# `enter_call_expr`, `extract_args`, `interpret`, `prepare_args`,
# `determine_method_for_expr` all never compiled). This is the Debugger.jl
# path: `@enter f(args...)` is `enter_call` plus a command loop.
#
# What it does. Define the generated program *natively* (`Core.eval`; semantics
# of the toplevel run are irrelevant here — the differential axis owns that),
# then harvest the program's own callables and call them with *synthesized*
# arguments — drawn per parameter type, including values the program itself
# never passes (typemin/typemax, NaN, empty strings/vectors, wrong-ish kwargs).
# Each call runs three times in the same module:
#
#   native #1, native #2  — the reference, twice. If the two native runs do not
#       agree (the call mutates state it also reads, or is otherwise
#       call-count-sensitive), the call is *uncertified* and skipped — the same
#       self-agreement trick the corpus axis uses (determinism.md §6), which is
#       what makes calling arbitrary generated functions sound.
#   enter_call + walk     — the system under test: build the frame with the
#       public API and drive it to completion with a random `debug_command`
#       walk (bounded, with the drain trick from the step axis).
#
# A certified call whose interpreted outcome (status, exception type,
# normalized return value) differs from the native one is a finding. Because
# all three runs share one module, there are no cross-module identity issues:
# `__fjnorm__` normalization is only doing value work.
#
# Replay: everything — target order, argument synthesis, kwarg subsets, the
# command walk — is drawn from one `Xoshiro(callseed)`, so `(src, callseed)`
# reproduces a candidate exactly (the callseed is derived from the generator
# stream the same way the step axis derives its walkseed).

using JuliaInterpreter: enter_call, get_return
using Random: randperm

struct CallOutcome
    status::Symbol   # :done | :threw | :skip (noframe / budget / unsynthesizable)
    excname::Symbol
    norm::Any        # __fjnorm__-normalized return value (nothing unless :done)
    site::Symbol     # innermost JuliaInterpreter fn for a thrown walk (:none otherwise)
    detail::String
end

# --- argument synthesis ------------------------------------------------------
#
# A thunk per parameter, built once from RNG draws and materialized fresh for
# every run of the call, so a callee that mutates its argument (push! on a
# Vector, setfield! on a mutable struct) mutates a private copy each time.
# Returns `nothing` for a parameter type it cannot synthesize — the method is
# skipped, and `metrics`-style counters make the skip rate visible.

const SYNTH_DEPTH = 3

function synththunk(rng::AbstractRNG, @nospecialize(T), m::Module, depth::Int=0)
    depth > SYNTH_DEPTH && return nothing
    T === Any && return synththunk(rng, rand(rng, (Int64, Float64, Bool, String, Symbol,
                                                   Char, Nothing, Vector{Int64})), m, depth)
    if T isa Union
        parts = Base.uniontypes(T)
        isempty(parts) && return nothing
        return synththunk(rng, rand(rng, parts), m, depth)
    end
    T isa DataType || return nothing
    if T === Int64
        v = rand(rng, (-2, -1, 0, 1, 3, 9, 42, typemax(Int64), typemin(Int64)))
        return () -> v
    elseif T === Float64
        v = rand(rng, (0.0, -0.0, 1.5, -2.25, NaN, Inf, -Inf))
        return () -> v
    elseif T === Bool
        v = rand(rng, Bool)
        return () -> v
    elseif T === String
        v = rand(rng, ("", "a", "0", "🐛x", " 1x"))
        return () -> v
    elseif T === Symbol
        v = rand(rng, (:a, :b, Symbol(""), :🐛))
        return () -> v
    elseif T === Char
        v = rand(rng, ('a', '0', '🐛'))
        return () -> v
    elseif T === Nothing
        return () -> nothing
    elseif T <: Vector && isconcretetype(T)
        et = eltype(T)
        n = rand(rng, 0:3)
        elts = [synththunk(rng, et === Any ? rand(rng, (Int64, String, Bool)) : et, m, depth + 1)
                for _ in 1:n]
        any(isnothing, elts) && return nothing
        return () -> begin
            v = Vector{et}(undef, 0)
            for t in elts
                push!(v, t())
            end
            v
        end
    elseif T <: Tuple && isconcretetype(T)
        elts = [synththunk(rng, p, m, depth + 1) for p in T.parameters]
        any(isnothing, elts) && return nothing
        return () -> Tuple(t() for t in elts)
    elseif isabstracttype(T)
        (Int64 <: T) && return synththunk(rng, Int64, m, depth)
        (Float64 <: T) && return synththunk(rng, Float64, m, depth)
        (String <: T) && return synththunk(rng, String, m, depth)
        return nothing
    elseif isstructtype(T) && parentmodule(T) === m && isconcretetype(T)
        # A struct the program defined: construct one from synthesized fields.
        fts = [fieldtype(T, i) for i in 1:fieldcount(T)]
        thunks = [synththunk(rng, ft, m, depth + 1) for ft in fts]
        any(isnothing, thunks) && return nothing
        return () -> Base.invokelatest(T, (t() for t in thunks)...)
    end
    return nothing
end

# Positional-argument thunks for one method, handling a trailing Vararg.
# Returns nothing if any parameter is unsynthesizable.
function synthargs(rng::AbstractRNG, meth::Method, m::Module)
    sig = Base.unwrap_unionall(meth.sig)
    sig isa DataType || return nothing
    thunks = Function[]
    for p in sig.parameters[2:end]
        if p isa Core.TypeofVararg
            vt = isdefined(p, :T) ? p.T : Any
            for _ in 1:rand(rng, 0:2)
                t = synththunk(rng, vt, m)
                t === nothing && return nothing
                push!(thunks, t)
            end
        else
            t = synththunk(rng, p, m)
            t === nothing && return nothing
            push!(thunks, t)
        end
    end
    return thunks
end

# Keyword thunks: a random subset of the method's declared keywords, sometimes
# none (the no-kw path through a kw method is its own lowering shape). Values
# come from the Any menu — a wrongly-typed keyword is fine, because the native
# reference receives the identical value and must fail the identical way.
function synthkwargs(rng::AbstractRNG, meth::Method, m::Module)
    kwnames = try
        # :world/:method_table are enter_call's own keywords; a generated kwarg
        # sharing the name would be swallowed by the API instead of forwarded.
        filter(k -> Base.isidentifier(k) && k !== :world && k !== :method_table,
               Base.kwarg_decl(meth))
    catch
        Symbol[]
    end
    (isempty(kwnames) || rand(rng) < 0.4) && return Pair{Symbol,Function}[]
    picked = [k for k in kwnames if rand(rng, Bool)]
    out = Pair{Symbol,Function}[]
    for k in picked
        t = synththunk(rng, Any, m)
        t === nothing && continue
        push!(out, k => t)
    end
    return out
end

# --- the three runs ----------------------------------------------------------

function callnative(f, thunks::Vector{Function}, kwthunks::Vector{Pair{Symbol,Function}},
                    fjnorm)::CallOutcome
    args, kws = try
        Any[t() for t in thunks], Any[k => t() for (k, t) in kwthunks]
    catch err
        return CallOutcome(:skip, scrubexc(err), nothing, :none, "argument materialization threw")
    end
    try
        v = isempty(kws) ? Base.invokelatest(f, args...) :
                           Base.invokelatest(f, args...; NamedTuple(kws)...)
        return CallOutcome(:done, :none, Base.invokelatest(fjnorm, v), :none, "")
    catch err
        return CallOutcome(:threw, scrubexc(err), nothing, :none, shortstr(err))
    end
end

function callinterp(rng::AbstractRNG, f, thunks::Vector{Function},
                    kwthunks::Vector{Pair{Symbol,Function}}, fjnorm;
                    maxcmds::Int)::CallOutcome
    args, kws = try
        Any[t() for t in thunks], Any[k => t() for (k, t) in kwthunks]
    catch err
        return CallOutcome(:skip, scrubexc(err), nothing, :none, "argument materialization threw")
    end
    local fr
    try
        fr = isempty(kws) ? Base.invokelatest(enter_call, f, args...) :
                            Base.invokelatest(enter_call, f, args...; NamedTuple(kws)...)
    catch err
        # enter_call itself broke. Compared against the native outcome like any
        # other throw; if native completed, this is a public-API finding.
        bt = stacktrace(catch_backtrace())
        site = internalframe(bt)
        return CallOutcome(:threw, scrubexc(err), nothing,
                           site === nothing ? :enter_call : Symbol(site[1]),
                           string("enter_call threw: ", shortstr(err)))
    end
    # `nothing` means the call cannot be interpreted (e.g. it resolved to
    # Compiled); `@interpret` falls back to a direct call there, so there is
    # nothing differential to say.
    fr === nothing && return CallOutcome(:skip, :none, nothing, :none, "enter_call returned nothing")
    try
        status, n, stuckcmd = walkframe!(rng, RecursiveInterpreter(), fr, maxcmds)
        status === :budget &&
            return CallOutcome(:skip, :none, nothing, :none, "walk budget exhausted")
        status === :stuck &&
            return CallOutcome(:threw, :__stuck__, nothing, stuckcmd,
                               "`:$stuckcmd` left execution at the same (framecode, pc) $STUCK_LIMIT times")
        v = Base.invokelatest(get_return, fr)
        return CallOutcome(:done, :none, Base.invokelatest(fjnorm, v), :none, "")
    catch err
        bt = stacktrace(catch_backtrace())
        site = internalframe(bt)
        return CallOutcome(:threw, scrubexc(err), nothing,
                           site === nothing ? :none : Symbol(site[1]),
                           string(shortstr(err), "\n",
                                  first(sprint(Base.show_backtrace, catch_backtrace(); context=:limit => true), 2000)))
    end
end

# --- classification ----------------------------------------------------------

function classify_call(ref::CallOutcome, int::CallOutcome, callrepr::String)::Verdict
    if int.excname === :__stuck__
        return Verdict(:call_stuck, "$callrepr: $(int.detail)", :none, :none, 0, int.site, :none)
    end
    if ref.status === :done && int.status === :done
        obseq(ref.norm, int.norm) && return agree()
        return Verdict(:call_value_divergence,
                       "$callrepr: native=$(first(repr(ref.norm), 200)) interp=$(first(repr(int.norm), 200))",
                       :none, :none, 1, obssig(ref.norm), obssig(int.norm))
    end
    if ref.status === :threw && int.status === :threw
        ref.excname === int.excname && return agree()
        return Verdict(:call_exception_divergence,
                       "$callrepr: native threw $(ref.excname) ($(ref.detail)); interp threw $(int.excname) ($(int.detail))",
                       ref.excname, int.excname, 0, :none, int.site)
    end
    if ref.status === :done && int.status === :threw
        return Verdict(:call_only_throw,
                       "$callrepr: interp threw $(int.excname) where the native call completed\n$(int.detail)",
                       :none, int.excname, 0, :none, int.site)
    end
    return Verdict(:call_ref_only_throw,
                   "$callrepr: native threw $(ref.excname) ($(ref.detail)); interp completed",
                   ref.excname, :none, 0, :none, :none)
end

# --- per-candidate driver ----------------------------------------------------

struct CallRun
    verdicts::Vector{Verdict}
    ncalls::Int        # certified, compared calls
    uncertified::Int   # native disagreed with itself → skipped
    skipped::Int       # unsynthesizable / noframe / budget
end

"""
    call_program(src; callseed, maxcalls, maxcmds) -> CallRun | nothing

Define `src` natively in a fresh module, then compare native execution against
`enter_call` + a `debug_command` walk on up to `maxcalls` synthesized calls to
the program's own callables. `(src, callseed)` fully describes the run.
"""
function call_program(src::String; callseed::Int, maxcalls::Int=6, maxcmds::Int=1500)
    ex = parsegate(src)
    ex === nothing && return nothing
    m = freshmodule()
    # Native definition pass. Statement failures are tolerated — a toplevel
    # throw just means fewer harvestable definitions, and toplevel *semantics*
    # are the differential axis's job, not this one's.
    for st in ex.args
        st isa LineNumberNode && continue
        try
            Core.eval(m, st)
        catch
        end
    end
    fjnorm = Base.invokelatest(getglobal, m, :__fjnorm__)
    # Mutable harness state the program's functions read AND advance: the
    # inline PRNG (`__LCG__`, rendered into the program) and the virtual clock.
    # Snapshot it once and restore it before EVERY run of a call — native #1,
    # native #2, and the interpreted run — so all three observe identical
    # state. Without this, a PRNG-reading function's value legitimately differs
    # per call, and double-call certification only catches that
    # *probabilistically*: the first campaign minutes produced a false
    # `call_value_divergence` where both native samples landed in a
    # `max(x, 0)` clamp (both negative products → both 0, certified) and the
    # interpreted call drew the next PRNG value. Restoring the state makes the
    # comparison a true differential; certification still guards the
    # *program's own* globals, where the same masking risk remains and is
    # accepted.
    refs = Pair{Symbol,Any}[]
    for nm in (:__LCG__, :__VTIME__)
        r = try
            Base.invokelatest(getglobal, m, nm)
        catch
            continue
        end
        r isa Ref && push!(refs, nm => (r, r[]))
    end
    resetstate!() = for (_, (r, v0)) in refs
        r[] = v0
    end
    rng = Xoshiro(callseed)
    pairs = Tuple{Any,Method}[]
    for f in latesttargets(m)
        for meth in latestmethods(f)
            push!(pairs, (f, meth))
        end
    end
    isempty(pairs) && return CallRun(Verdict[], 0, 0, 0)
    order = randperm(rng, length(pairs))
    verdicts = Verdict[]
    ncalls = uncert = skipped = 0
    for idx in order
        ncalls >= maxcalls && break
        f, meth = pairs[idx]
        thunks = synthargs(rng, meth, m)
        if thunks === nothing
            skipped += 1
            continue
        end
        kwthunks = synthkwargs(rng, meth, m)
        resetstate!()
        o1 = callnative(f, thunks, kwthunks, fjnorm)
        resetstate!()
        o2 = callnative(f, thunks, kwthunks, fjnorm)
        if o1.status === :skip || o2.status === :skip
            skipped += 1
            continue
        end
        # Self-agreement certification: the reference must reproduce itself
        # before its outcome can judge the interpreter (determinism.md §6).
        if !(o1.status === o2.status && o1.excname === o2.excname && obseq(o1.norm, o2.norm))
            uncert += 1
            continue
        end
        resetstate!()
        into = callinterp(rng, f, thunks, kwthunks, fjnorm; maxcmds)
        if into.status === :skip
            skipped += 1
            continue
        end
        ncalls += 1
        callrepr = string(nameof_safe(f), "/", meth.nargs - 1,
                          isempty(kwthunks) ? "" : string("; kw=", first.(kwthunks)))
        v = classify_call(o1, into, callrepr)
        isfinding(v) && push!(verdicts, v)
    end
    return CallRun(verdicts, ncalls, uncert, skipped)
end

nameof_safe(@nospecialize(f)) = try
    nameof(f)
catch
    :__anon__
end

"""
    call_campaign(; n, baseseed, ...) -> Stats

Generate programs and run the enter_call differential on each. Confirmation on
divergence is a full candidate re-run: the same `(src, callseed)` must
re-derive the same fingerprint, or the finding is a tracked `nondet_discard`.
"""
function call_campaign(; n::Int=500, baseseed::Int=1,
                       outdir::String=joinpath(@__DIR__, "..", "findings"),
                       journaldir::String=joinpath(@__DIR__, "..", "journal"),
                       cfg::Cfg=Cfg(), progress::Int=50, maxcalls::Int=6, maxcmds::Int=1500,
                       seeddisk::Bool=true, journalsync::Bool=true)
    j = Journal(journaldir; sync=journalsync)
    stats = Stats()
    seen = Set{String}()
    seeddisk && isdir(outdir) && for d in readdir(outdir)
        push!(seen, d)
    end
    ncalls = uncert = 0
    t0 = time()
    try
        for i in 1:n
            seed = baseseed + i - 1
            rng = Xoshiro(seed)
            prog = genprogram(rng, cfg)
            src = render(prog)
            callseed = rand(rng, 1:typemax(Int))
            journal_case!(j, seed, src)
            stats.cases += 1
            r = call_program(src; callseed, maxcalls, maxcmds)
            if r === nothing
                stats.discarded += 1
                continue
            end
            ncalls += r.ncalls
            uncert += r.uncertified
            anyfinding = false
            for v in r.verdicts
                if suppressed(v)
                    stats.suppressed += 1
                    anyfinding = true
                    continue
                end
                fp = tagfp(:call, fingerprint(v))
                if fp in seen
                    stats.duplicates += 1
                    anyfinding = true
                    continue
                end
                # Confirm-on-divergence, whole-candidate flavour: replaying the
                # same (src, callseed) must re-derive this fingerprint.
                r2 = call_program(src; callseed, maxcalls, maxcmds)
                if r2 === nothing || !any(v2 -> fingerprint(v2) == fingerprint(v), r2.verdicts)
                    stats.nondet_discard += 1
                    continue
                end
                push!(seen, fp)
                stats.findings += 1
                anyfinding = true
                @info "CALL FINDING $(v.class)" seed fp callseed detail = first(v.detail, 400)
                writefinding(outdir, fp, v, seed, src, src; mode=:call, walkseed=callseed)
            end
            anyfinding || (stats.agreed += 1)
            if progress > 0 && i % progress == 0
                @info "call progress" i rate_per_s = round(stats.cases / (time() - t0); digits=2) calls_compared = ncalls uncertified = uncert stats.agreed stats.findings stats.duplicates stats.discarded
            end
        end
    finally
        close(j)
    end
    @info "call campaign totals" calls_compared = ncalls uncertified = uncert
    return stats
end
