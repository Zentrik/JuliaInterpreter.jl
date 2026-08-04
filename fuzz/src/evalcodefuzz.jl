# The eval_code axis: fuzz expression evaluation at a paused frame.
#
# `eval_code(frame, "x")` is what a debugger's prompt calls when you type a
# variable name while stopped, and `eval_code(frame, "x = 3")` is what it calls
# when you assign one. Making that work means building a `let` around the
# frame's locals, evaluating in it, and writing the results *back* into the
# right slots — including static parameters and captured closure variables.
# That write-back is fiddly and historically wrong: `utils.jl` carries the
# second-densest fix history in the package (7 commits), one of which is
# literally "Fix eval_code writing static parameters back to the wrong slots".
# Nothing tests it beyond ~33 hand-written cases.
#
# The oracle needs no determinism, so it works on any paused frame:
#
#   1. Read fidelity. For every local the interpreter reports via `locals`,
#      `eval_code(frame, name)` must return that same value. If it returns
#      something else, the debugger is lying about program state.
#   2. Write-back round trip. After `eval_code(frame, "x = <v>")`, reading `x`
#      back — both through `eval_code` and through the frame's own `locals` —
#      must yield `<v>`. A write that lands in the wrong slot corrupts a
#      *different* variable, so the check also verifies that every other local
#      is unchanged. That is the shape of the static-parameter bug.
#   3. No internal error. `eval_code` may legitimately fail on a name it cannot
#      resolve, so only errors raised from inside JuliaInterpreter count (same
#      `internalframe` test the stepping axis uses).

using JuliaInterpreter: eval_code, locals, Variable

struct EvalOutcome
    status::Symbol      # :ok | :read_mismatch | :write_lost | :collateral_write | :internal_error
    detail::String
    site::Symbol        # innermost JuliaInterpreter function (internal errors)
    nchecks::Int
end

# Values written during the round-trip check. Deliberately boring and of a
# stable type: the point is to test the plumbing, not to provoke conversion.
writeprobe(rng::AbstractRNG, @nospecialize(old)) =
    old isa Int     ? rand(rng, -99:99) :
    old isa Float64 ? round(rand(rng) * 10; digits=3) :
    old isa Bool    ? !old :
    old isa String  ? "fjprobe" :
    old isa Symbol  ? :fjprobe :
    nothing

# Is this local safe to round-trip through eval_code? Skips names that are
# plumbing rather than program state, and values whose identity (not value) is
# what matters.
function probeable(v::Variable)
    s = String(v.name)
    startswith(s, "#") && return false          # #self#, gensyms
    v.is_captured_closure && return false        # reported via #self#, not a slot
    v.name === Symbol("") && return false
    return v.value isa Union{Int,Float64,Bool,String,Symbol}
end

# Run the eval_code checks against one paused frame.
function check_evalcode(rng::AbstractRNG, frame::Frame)
    vars = try
        locals(frame)
    catch err
        site = internalframe(stacktrace(catch_backtrace()))
        site === nothing && return EvalOutcome(:ok, "", :none, 0)
        return EvalOutcome(:internal_error, "locals() threw $(nameof(typeof(err))): $(shortstr(err))",
                           Symbol(site[1]), 0)
    end
    nchecks = 0
    # (1) read fidelity
    for v in vars
        probeable(v) || continue
        got = try
            eval_code(frame, String(v.name))
        catch err
            site = internalframe(stacktrace(catch_backtrace()))
            site === nothing && continue   # couldn't resolve the name; not our bug
            return EvalOutcome(:internal_error,
                               "eval_code(frame, \"$(v.name)\") threw $(nameof(typeof(err))): " *
                               "$(shortstr(err))", Symbol(site[1]), nchecks)
        end
        nchecks += 1
        if !(typeof(got) === typeof(v.value) && isequal(got, v.value))
            return EvalOutcome(:read_mismatch,
                               "eval_code read `$(v.name)` as $(repr(got))::$(typeof(got)), " *
                               "but the frame holds $(repr(v.value))::$(typeof(v.value))",
                               :none, nchecks)
        end
    end
    # (2) write-back round trip, on one randomly chosen local
    cands = [v for v in vars if probeable(v)]
    isempty(cands) && return EvalOutcome(:ok, "", :none, nchecks)
    target = pick(rng, cands)
    newval = writeprobe(rng, target.value)
    newval === nothing && return EvalOutcome(:ok, "", :none, nchecks)
    # Force the eltype: `Dict(gen)` infers it via grow_to!/dict_with_eltype,
    # whose type-widening over arbitrary frame-local values crashed in Julia's
    # `lookup_typevalue` on the campaign (a pathological local type). A fixed
    # {Symbol,Any} eltype skips that path entirely.
    before = Dict{Symbol,Any}(v.name => v.value for v in cands if v.name !== target.name)
    try
        eval_code(frame, string(target.name, " = ", repr(newval)))
    catch err
        site = internalframe(stacktrace(catch_backtrace()))
        site === nothing && return EvalOutcome(:ok, "", :none, nchecks)
        return EvalOutcome(:internal_error,
                           "eval_code(frame, \"$(target.name) = $(repr(newval))\") threw " *
                           "$(nameof(typeof(err))): $(shortstr(err))", Symbol(site[1]), nchecks)
    end
    nchecks += 1
    # the value must be visible both through eval_code and in the frame itself
    readback = try
        eval_code(frame, String(target.name))
    catch err
        return EvalOutcome(:write_lost,
                           "after `$(target.name) = $(repr(newval))`, reading it back threw " *
                           "$(nameof(typeof(err)))", :none, nchecks)
    end
    if !isequal(readback, newval)
        return EvalOutcome(:write_lost,
                           "assigned `$(target.name) = $(repr(newval))` but eval_code read back " *
                           "$(repr(readback))", :none, nchecks)
    end
    after = Dict{Symbol,Any}(v.name => v.value for v in locals(frame))
    if haskey(after, target.name) && !isequal(after[target.name], newval)
        return EvalOutcome(:write_lost,
                           "assigned `$(target.name) = $(repr(newval))` but the frame's own " *
                           "locals report $(repr(after[target.name]))", :none, nchecks)
    end
    # (3) nothing else may have moved — a write landing in the wrong slot
    # corrupts a different variable, which is exactly the static-parameter bug
    for (name, old) in before
        haskey(after, name) || continue
        if !isequal(after[name], old)
            return EvalOutcome(:collateral_write,
                               "assigning `$(target.name) = $(repr(newval))` also changed " *
                               "`$name` from $(repr(old)) to $(repr(after[name]))", :none, nchecks)
        end
    end
    return EvalOutcome(:ok, "", :none, nchecks)
end

evalverdict(o::EvalOutcome) =
    o.status === :ok ? agree() :
    o.status === :internal_error ?
        Verdict(:evalcode_internal_error, o.detail, :none, :none, 0, o.site, :none) :
        Verdict(Symbol(:evalcode_, o.status), o.detail, :none, :none, 0, :none, :none)

"""
    evalcode_probe(src; walkseed, nstmts, pausesper) -> EvalOutcome or nothing

Run one program's worth of the axis: step it to a series of pause points and run
the `eval_code` checks at each. Returns the first non-`:ok` outcome, an `:ok`
outcome if nothing fired, or `nothing` if the source did not survive the parse
gate.

Like the stepping axis, the pause walk and the write probes draw from a fresh
`Xoshiro(walkseed)` rather than from the generator's stream — that is what makes
`(src, walkseed)` a complete description of the run, and hence what makes the
axis shrinkable.
"""
function evalcode_probe(src::String; walkseed::Int, nstmts::Int=300_000, pausesper::Int=25)
    ex = parsegate(src)
    ex === nothing && return nothing
    rng = Xoshiro(walkseed)
    interp = RecursiveInterpreter()
    m = freshmodule()
    worst = nothing
    nchecks = 0     # kept so a collapse to "this axis checks nothing" stays visible
    try
        for (mod, frag) in ExprSplitter(m, ex)
            fr = Frame(mod, frag)
            # Step a bounded number of times, checking eval_code at each pause.
            # Frames are checked wherever the walk lands — including inside
            # callees, where slots and static parameters actually exist.
            for _ in 1:pausesper
                is_toplevel_frame(fr) && (fr.world = Base.get_world_counter())
                o = check_evalcode(rng, fr)
                nchecks += o.nchecks
                if o.status !== :ok
                    worst = o
                    break
                end
                ret = try
                    debug_command(interp, fr, pick(rng, (:s, :n, :se, :nc)), true)
                catch
                    nothing   # program-level error ends this fragment's walk
                end
                ret === nothing && break
                fr, _pc = ret
            end
            worst === nothing || break
        end
    catch err
        site = internalframe(stacktrace(catch_backtrace()))
        site === nothing || (worst = EvalOutcome(:internal_error,
            "$(nameof(typeof(err))): $(shortstr(err))", Symbol(site[1]), nchecks))
    end
    return worst === nothing ? EvalOutcome(:ok, "", :none, nchecks) : worst
end

"""
    evalcode_keep(fp; walkseed, nstmts, pausesper) -> keep

The eval_code axis's property as a `keep(src)::Bool` predicate. Re-runs the
pause-and-check procedure with the same `walkseed` and requires the same verdict
fingerprint — which for this axis means the same *check kind*, since the class
itself distinguishes read-mismatch from write-lost from collateral-write, and
internal errors are additionally salted with the JuliaInterpreter function that
raised.
"""
function evalcode_keep(fp::String; walkseed::Int, nstmts::Int, pausesper::Int)
    return function (src::String)
        o = evalcode_probe(src; walkseed, nstmts, pausesper)
        o === nothing && return false
        v = evalverdict(o)
        return isfinding(v) && fingerprint(v) == fp
    end
end

"""
    evalcode_campaign(; n, baseseed, ...) -> Stats

Generate programs, step each to a series of random pause points, and run the
`eval_code` checks at every pause.
"""
function evalcode_campaign(; n::Int=300, baseseed::Int=1, nstmts::Int=300_000,
                           outdir::String=joinpath(@__DIR__, "..", "findings"),
                           journaldir::String=joinpath(@__DIR__, "..", "journal"),
                           cfg::Cfg=Cfg(), progress::Int=50, pausesper::Int=25,
                           seeddisk::Bool=true, journalsync::Bool=true,
                           doshrink::Bool=true, shrinkruns::Int=150,
                           shrinksecs::Real=180.0)
    j = Journal(journaldir; sync=journalsync)
    stats = Stats()
    seen = Set{String}()
    seeddisk && isdir(outdir) && for d in readdir(outdir)
        push!(seen, d)
    end
    t0 = time()
    try
        for i in 1:n
            seed = baseseed + i - 1
            rng = Xoshiro(seed)
            prog = genprogram(rng, cfg)
            src = render(prog)
            # Own seed for the pause walk, drawn from the generator's stream so
            # the case still reproduces from `seed`, but consumed through a fresh
            # Xoshiro so a shrunk candidate can be replayed identically.
            walkseed = rand(rng, 1:typemax(Int))
            journal_case!(j, seed, src)
            stats.cases += 1
            o = evalcode_probe(src; walkseed, nstmts, pausesper)
            if o === nothing
                stats.discarded += 1
                continue
            end
            v = evalverdict(o)
            if v.class === :agree
                stats.agreed += 1
            elseif suppressed(v)
                stats.suppressed += 1
            else
                fp = tagfp(:evalcode, fingerprint(v))
                if fp in seen
                    stats.duplicates += 1
                else
                    push!(seen, fp)
                    stats.findings += 1
                    @info "EVALCODE FINDING $(v.class)" seed fp walkseed detail = first(v.detail, 400)
                    shrunk = src
                    if doshrink
                        budget = ShrinkBudget(; maxruns=shrinkruns, seconds=shrinksecs)
                        keep = evalcode_keep(fingerprint(v); walkseed, nstmts, pausesper)
                        shrunk = render(shrink_ir(prog, keep; budget))
                        @info "  shrunk" runs = budget.runs lines_orig = countlines(IOBuffer(src)) lines_shrunk = countlines(IOBuffer(shrunk))
                    end
                    writefinding(outdir, fp, v, seed, src, shrunk; mode=:evalcode, walkseed)
                end
            end
            if progress > 0 && i % progress == 0
                @info "evalcode progress" i rate_per_s = round(stats.cases / (time() - t0); digits=2) stats.agreed stats.findings stats.duplicates
            end
        end
    finally
        close(j)
    end
    return stats
end
