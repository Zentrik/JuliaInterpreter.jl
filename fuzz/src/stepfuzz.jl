# The stepping axis: fuzz the *debugger* surface, not just execution.
#
# Why this exists. The differential execution axis (execute.jl) tests
# run-to-completion semantics — the surface Julia's own test suite already
# exercises under the interpreter (test/juliatests.jl), and the one every
# Debugger.jl/Revise user hits constantly. The debugger machinery is different:
# `debug_command`, `next_line!`, `until_line!`, frame entry/exit through
# wrappers and kwarg preparation, breakpoint arming and condition evaluation.
# Historically that is where this package's bugs are — counting fix commits per
# file, construct.jl/utils.jl/commands.jl/breakpoints.jl dominate interpret.jl
# and builtins.jl — and none of it had systematic testing.
#
# The oracle. Stepping is not differential against compiled Julia (there is
# nothing to compare a pause against), so this axis asserts the *invariants a
# debugger must satisfy no matter which commands the user types*:
#
#   1. Stepping terminates. A command sequence must drive the frame to
#      completion within a bounded number of commands. Exceeding the bound is a
#      finding: the historical failure mode is a command that returns the frame
#      unchanged forever (next_line! not advancing past a statement kind).
#   2. No internal error. An exception raised *by JuliaInterpreter's own code*
#      is a bug. An exception raised by the interpreted program is not — the
#      generated programs throw deliberately — so the two are told apart by
#      looking for JuliaInterpreter frames in the backtrace (`internalerror`).
#   3. Stepping agrees with running. Driving a program to completion by
#      stepping must produce the same observation stream as running it
#      normally. This catches the subtle class where a command silently
#      executes or skips statements: the fix history has several
#      (`next_line!` stopping on assignment-only lines, argument-destructuring
#      preambles, self-field-access wrappers) — all of which are "the debugger
#      ran the wrong statements", invisible without this check.
#
# Replay note. The command walk draws from its own `Xoshiro(walkseed)`, not from
# the generator's stream. That separation is what makes this axis shrinkable: if
# the walk continued the generator's RNG, deleting a statement would change every
# draw the walk makes afterwards, so a shrunk program could never be replayed
# with a comparable command sequence and no shrink step could be judged. With an
# independent seed, `(src, walkseed)` reproduces a walk exactly, and a *shrunk*
# `src` replays the same seed from scratch.
#
# What replay does NOT promise is an identical command trace. A shorter program
# has fewer pause points, so the same draws land on different statements and the
# walk legitimately diverges. The shrink predicate therefore asks for the same
# verdict *class* (and fingerprint salt), never for trace equality.

using JuliaInterpreter: debug_command, root, leaf, BreakpointRef, Frame,
                        break_on, break_off, breakpoint, remove, is_toplevel_frame,
                        breakpoints, enable, disable, toggle

# The command vocabulary. Includes the "advanced" commands, which are exactly
# the thinly-tested ones.
const STEP_COMMANDS = (:n, :s, :c, :finish, :nc, :se, :si, :until, :sl, :sr)

# Commands that can only make progress and never enter a callee: used to force
# termination once a walk has spent its randomness budget.
const DRAIN_COMMANDS = (:se, :n, :finish)

struct StepOutcome
    status::Symbol      # :done | :threw | :stuck | :budget
    obs::Vector{Any}
    detail::String
    ncommands::Int
    cmds::Vector{Symbol}
    site::Symbol        # innermost JuliaInterpreter function in the backtrace (:none if absent)
    excname::Symbol     # exception type (:none unless status === :threw)
    nbp::Int            # breakpoint actions performed during the walk
    ingen::Bool         # a `:sg` landed in a @generated function's *generator*
                        # frame: by design the generator's returned expression
                        # then becomes the call's value, so the stepped program
                        # legitimately computes something different from plain
                        # interpretation — obs/exception comparison is unsound
                        # for this walk (termination/stuck invariants still hold)
end
StepOutcome(status, obs, detail, n, cmds) = StepOutcome(status, obs, detail, n, cmds, :none, :none, 0, false)
StepOutcome(status, obs, detail, n, cmds, site) = StepOutcome(status, obs, detail, n, cmds, site, :none, 0, false)
StepOutcome(status, obs, detail, n, cmds, site, excname) = StepOutcome(status, obs, detail, n, cmds, site, excname, 0, false)
StepOutcome(status, obs, detail, n, cmds, site, excname, nbp) = StepOutcome(status, obs, detail, n, cmds, site, excname, nbp, false)

# Did this exception come from JuliaInterpreter itself, rather than from the
# interpreted program? Program-thrown exceptions are expected (the grammar
# generates them on purpose); an error raised inside the stepping machinery is
# the finding. `MethodError`/`ArgumentError` raised *within* a JuliaInterpreter
# frame counts as internal.
#
# Returns the innermost JuliaInterpreter frame as (function, file:line), or
# nothing if the package appears nowhere in the backtrace. That location is the
# fingerprint salt: without it every internal error — whatever broke, wherever —
# would share one dedup bucket, and the first one reported would mask the rest.

# The package's own source directory, resolved once. Everything under it is
# "internal" — no list of file names to maintain, and a file added to the
# package tomorrow is covered automatically.
const JI_SRCDIR = let p = pathof(JuliaInterpreter)
    p === nothing ? "" : dirname(abspath(p))
end

isinternalfile(path::AbstractString) = !isempty(JI_SRCDIR) && startswith(abspath(path), JI_SRCDIR)

function internalframe(bt)
    for fr in bt
        s = try
            string(fr.file)
        catch
            continue
        end
        # The harness lives outside the package's src/, so its own frames never
        # match. Frames from `interpret.jl` count too: an internal error there
        # during stepping is still a bug in the path that reached it.
        isinternalfile(s) && return (fr.func, string(basename(s), ":", fr.line))
    end
    return nothing
end

# How many consecutive commands may leave execution at exactly the same
# (framecode, pc) before the walk is considered stuck. A command that cannot
# advance repeats forever, which is the shape of the historical bug
# (`next_line!` not getting past a statement kind).
#
# Only commands that return a *normal* pc count. Parking at a breakpoint and
# reporting the same position is legal and expected: with break_on(:error)
# armed, a statement that always throws re-triggers the same error breakpoint
# every time it is retried, so execution genuinely does not advance until the
# user unwinds. Counting those made the whole class false positives — every
# report from the first campaign was a walk parked on an error breakpoint, not
# a command that could not step.
const STUCK_LIMIT = 200

# --- Real breakpoints, driven from the walk ---------------------------------
#
# Until now the axis only ever armed `break_on(:error)`; the entire breakpoint
# API — `breakpoint(f)`, method/conditional/line breakpoints, enable/disable/
# toggle/remove — never ran, and the coverage report showed it: 30 of 34
# definitions in src/breakpoints.jl never executed, 13% of its lines hit.
# That file has a real fix history (3 fix commits), which is exactly the
# "untested surface with prior bugs" this axis exists for.
#
# So the walk now *manages breakpoints as it steps*, the way a Debugger.jl user
# does: with a small per-command probability (and between fragments, when new
# definitions have just appeared) it performs one random breakpoint action.
# Every draw comes from the walk RNG, so `(src, walkseed)` still reproduces a
# run exactly, and the shrink predicate replays breakpoint decisions along with
# the commands.
#
# Breakpoints must not change what the program computes — pausing is
# observable only as extra (frame, BreakpointRef) returns from debug_command,
# which the walk already handles — so invariant 3 (stepping reaches the same
# observations as running) is unchanged. Conditions are drawn only from shapes
# that cannot throw and have no side effects: literal comparisons, and
# `<argname> isa Any` where the name comes from the chosen *method's* own
# argument list (a condition is only ever attached to the specific Method whose
# names it uses — attached to the whole function it would hit sibling methods
# that lack the slot and throw an UndefVarError from inside `shouldbreak`,
# which would be our bug, not the interpreter's).
mutable struct BpDriver
    mod::Module          # the module the program defines things in
    prob::Float64        # per-command probability of one breakpoint action
    count::Int           # actions performed (drives the per-walk cap)
    nset::Int            # breakpoints actually SET on a program callable — the
                         # teeth metric; the world-age bug this axis shipped
                         # with had count > 0 and nset == 0
end

# Setting a breakpoint scans JuliaInterpreter's global framecode caches
# (`add_to_existing_framecodes` walks `framedict`/`genframedict`), which grow
# over a long campaign as rec-mode walks step into Base. Unbounded actions per
# walk would make that scan the axis's dominant cost late in a campaign, so
# each candidate gets a fixed allowance.
const MAX_BP_ACTIONS = 40

# Program-defined callables worth breakpointing: named functions and struct
# types (constructor breakpoints are their own historical bug class, #525).
# Harness prelude (`__obs__` & friends) and closure types (#-names) excluded —
# the former pause on every observation and drown the walk, the latter are not
# reachable by name from a debugger prompt anyway.
function bptargets(m::Module)
    out = Base.Callable[]
    for n in names(m; all=true)
        s = String(n)
        (startswith(s, '#') || startswith(s, "__")) && continue
        isdefined(m, n) || continue
        v = try
            getfield(m, n)
        catch
            continue
        end
        v isa Base.Callable && push!(out, v)
    end
    return out
end

# World age: the program's definitions were `Core.eval`'d after the harness
# functions were compiled, and 1.12's strict binding rules make `names`/
# `isdefined`/`getfield` (and method-table queries) world-sensitive — called
# directly from harness code, the harvest is silently EMPTY. Both the
# breakpoint driver and the call axis must reach these through invokelatest.
latesttargets(m::Module) = Base.invokelatest(bptargets, m)::Vector{Base.Callable}
latestmethods(@nospecialize(f)) = Base.invokelatest(collect, Base.invokelatest(methods, f))

# Safe condition menu for a specific method: literal comparisons (taken/not
# taken), or an `isa Any` on one of the method's own argument names — true even
# for an Unassigned slot, so it exercises the slot-lookup machinery in
# `prepare_slotfunction` without ever throwing.
function bpcondition(rng::AbstractRNG, m::Module, meth::Method)
    r = rand(rng)
    r < 0.3 && return (m, :(1 == 1))
    r < 0.5 && return (m, :(1 == 2))
    argnames = [a for a in Base.method_argnames(meth)[2:end] if Base.isidentifier(a)]
    isempty(argnames) && return (m, :(1 == 1))
    return (m, :($(rand(rng, argnames)) isa Any))
end

# One random breakpoint action. Never wrapped in try/catch: an exception from
# the breakpoint API itself surfaces through step_program's classifier as a
# step-only throw salted with the breakpoints.jl function that raised it —
# which is precisely the kind of finding this exists to produce.
function bpaction!(rng::AbstractRNG, bpd::BpDriver)
    bpd.count >= MAX_BP_ACTIONS && return
    bpd.count += 1
    r = rand(rng)
    if r < 0.55
        # Set a breakpoint on a program-defined callable.
        targets = latesttargets(bpd.mod)
        if isempty(targets)
            rand(rng, Bool) ? break_on(:error) : break_off(:error)
            return
        end
        f = rand(rng, targets)
        ms = latestmethods(f)
        bpd.nset += 1
        u = rand(rng)
        if u < 0.35 || isempty(ms)
            breakpoint(f)                                   # entry, all methods
        elseif u < 0.6
            breakpoint(rand(rng, ms))                       # one specific method
        elseif u < 0.85
            meth = rand(rng, ms)
            breakpoint(meth, bpcondition(rng, bpd.mod, meth))  # conditional
        else
            meth = rand(rng, ms)                            # line (possibly past the
            breakpoint(meth, Int(meth.line) + rand(rng, 0:10))  # end: a legal no-op)
        end
    elseif r < 0.8
        # Flip the state of an existing breakpoint.
        bps = breakpoints()
        isempty(bps) && return
        bp = rand(rng, bps)
        w = rand(rng)
        w < 0.35 ? disable(bp) : w < 0.7 ? enable(bp) : toggle(bp)
    elseif r < 0.92
        # Remove one breakpoint; rarely, all of them.
        bps = breakpoints()
        if rand(rng) < 0.15 || isempty(bps)
            remove()
        else
            remove(rand(rng, bps))
        end
    else
        # The global throw/error switches; :throw was previously never armed.
        s = rand(rng, (:error, :throw))
        rand(rng, Bool) ? break_on(s) : break_off(s)
    end
    return
end

# Drive one toplevel fragment to completion with a random command walk.
# Returns (status, ncommands, stuckcmd) where status is :done, :budget (ran out
# of commands, which is not by itself evidence of anything) or :stuck.
function walkframe!(rng::AbstractRNG, interp::Interpreter, frame::Frame, maxcmds::Int,
                    bpd::Union{BpDriver,Nothing}=nothing)
    fr = frame
    n = 0
    laststate = nothing
    noops = 0
    lastcmd = :none
    drained = false
    ingen = false
    while true
        n >= maxcmds && return (:budget, n, :none, ingen)
        if bpd !== nothing && !drained
            if n > 0.8 * maxcmds
                # Entering the drain phase: silence every pause source so the
                # DRAIN_COMMANDS below can actually finish the frame. Without
                # this, an entry breakpoint on a hot function turns the whole
                # tail of the budget into pauses and the walk ends :budget —
                # a tracked abort, i.e. a wasted candidate.
                drained = true
                foreach(disable, breakpoints())
                break_off(:error, :throw)
            elseif rand(rng) < bpd.prob
                bpaction!(rng, bpd)
            end
        end
        # Toplevel frames run in the latest world, matching what the interpreter
        # itself does in its toplevel loop (`istoplevel && (frame.world = ...)`,
        # src/interpret.jl) and what the differential executor does. Without it,
        # methods this program defined at runtime — including the harness's own
        # `__obs__` in the fresh module — are "too new" for the frame's world and
        # every observation fails. `debug_command` has no toplevel loop of its
        # own, so the caller owns this. Callee frames are left alone: they are
        # supposed to run in their caller's world.
        is_toplevel_frame(fr) && (fr.world = Base.get_world_counter())
        # Once past 80% of the budget, stop stepping *into* callees so the walk
        # can finish: under RecursiveInterpreter, `:s` descends into Base, and a
        # program with deep call nesting would otherwise spend the whole budget
        # there.
        cmd = n > 0.8 * maxcmds ? pick(rng, DRAIN_COMMANDS) : pick(rng, STEP_COMMANDS)
        # `:sg` steps into the *generator* of a @generated callee — the
        # enter_generated=true path (get_source on a GeneratedFunctionStub,
        # prepare_framecode's generator arm). On a non-generated callee it is
        # exactly `:s` (`enter_generated &= is_generated`), so drawing it as a
        # low-probability variant of `:s` leaves plain programs unaffected.
        cmd === :s && rand(rng) < 0.15 && (cmd = :sg)
        # `:until` takes a line number; nothing means "the line after this one".
        ret = cmd === :until && rand(rng) < 0.5 ?
              debug_command(interp, fr, cmd, true; line=rand(rng, 1:40)) :
              debug_command(interp, fr, cmd, true)
        n += 1
        ret === nothing && return (:done, n, :none, ingen)
        # Continue from wherever the command left execution: a callee frame
        # after stepping in, the caller after finishing, or a breakpoint pause.
        fr, pc = ret
        # Landing in a generator frame poisons the value comparison for the
        # whole walk (see StepOutcome.ingen); record it for the classifier.
        fr.framecode.generator && (ingen = true)
        state = (objectid(fr.framecode), fr.pc)
        if state == laststate && !isa(pc, BreakpointRef)
            noops += 1
            noops >= STUCK_LIMIT && return (:stuck, n, lastcmd, ingen)
        else
            noops = 0
        end
        laststate = state
        lastcmd = cmd
    end
end

"""
    step_program(src; walkseed, interp, maxcmds, usebreakpoints) -> StepOutcome

Execute `src` through `ExprSplitter`, driving every fragment with a random
`debug_command` walk instead of running it. Returns what happened plus the
observation stream the stepped program produced.

The walk is driven by a fresh `Xoshiro(walkseed)`, independent of whatever
randomness produced `src`; `(src, walkseed)` is therefore a complete description
of the run, which is what makes the axis replayable and hence shrinkable.
"""
function step_program(src::String; walkseed::Int, interp::Interpreter=RecursiveInterpreter(),
                      maxcmds::Int=4000, usebreakpoints::Bool=false,
                      ex::Union{Nothing,Expr}=nothing)
    rng = Xoshiro(walkseed)
    # `ex` lets a caller that already ran the parse gate on this same source
    # (the campaign and the shrink predicate both do, for the plain run) hand
    # the tree over instead of paying the gate twice per candidate (~13 ms of a
    # ~180 ms case, measured 2026-08-04). Sharing is behavior-identical:
    # parsegate is a pure function of src, and nothing downstream mutates the
    # AST (ExprSplitter copies module exprs and only walks the rest; Frame
    # lowers into fresh objects) — the same sharing run_all already does
    # between run_ref and run_interp.
    ex === nothing && (ex = parsegate(src))
    ex === nothing && return nothing
    m = freshmodule()
    cmds = Symbol[]
    total = 0
    anyingen = false
    bpd = usebreakpoints ? BpDriver(m, 0.04, 0, 0) : nothing
    try
        if usebreakpoints
            # Arm a global break-on-throw: exception handling during stepping is
            # the interaction the fix history keeps flagging. :throw (break even
            # on caught throws) is armed less often — the guarded rules throw on
            # purpose, so it pauses a lot.
            rand(rng) < 0.5 ? break_on(:error) : break_off(:error)
            rand(rng) < 0.25 && break_on(:throw)
        end
        for (mod, frag) in ExprSplitter(m, ex)
            # Between fragments is when new definitions have just appeared, so
            # it is the natural moment for a user to set a breakpoint on one.
            bpd !== nothing && rand(rng) < 0.3 && bpaction!(rng, bpd)
            frame = Frame(mod, frag)
            status, n, stuckcmd, ingen = walkframe!(rng, interp, frame, maxcmds - total, bpd)
            total += n
            anyingen |= ingen
            if status === :stuck
                return StepOutcome(:stuck, getobs(m),
                                   "`:$stuckcmd` left execution at the same (framecode, pc) " *
                                   "$STUCK_LIMIT times in a row after $total commands",
                                   total, cmds, stuckcmd, :none, bpd === nothing ? 0 : bpd.nset,
                                   anyingen)
            end
            # Budget exhaustion is not evidence of a bug — break-on-error stops
            # at every throw, and these programs throw on purpose — so it ends
            # the walk without a verdict rather than reporting one.
            status === :budget && return StepOutcome(:budget, getobs(m),
                                                     "command budget exhausted", total, cmds,
                                                     :none, :none, bpd === nothing ? 0 : bpd.nset,
                                                     anyingen)
        end
        return StepOutcome(:done, getobs(m), "", total, cmds, :none, :none,
                           bpd === nothing ? 0 : bpd.nset, anyingen)
    catch err
        bt = catch_backtrace()
        # Record where it surfaced, but do NOT use that to decide whether it is a
        # bug: an exception thrown by the *interpreted program* also unwinds
        # through JuliaInterpreter frames, so "the backtrace mentions this
        # package" is true of nearly every program-thrown error. Whether the
        # throw is a finding is decided in classify_step by comparing against
        # plain interpretation of the same program.
        site = internalframe(stacktrace(bt))
        sitename = site === nothing ? :none : Symbol(site[1])
        loc = site === nothing ? "" : string(" in ", site[1], " (", site[2], ")")
        return StepOutcome(:threw, getobs(m),
                           string(nameof(typeof(err)), loc, ": ", shortstr(err), "\n",
                                  first(sprint(Base.show_backtrace, bt; context=:limit => true), 2500)),
                           total, cmds, sitename, scrubexc(err),
                           bpd === nothing ? 0 : bpd.nset, anyingen)
    finally
        usebreakpoints && (break_off(:error, :throw); remove())
    end
end

# Classify a stepping run against a plain interpreted run of the same program.
# `plain` is the Outcome from run_interp, i.e. what the program does when it is
# simply executed — stepping through it must not change the answer.
function classify_step(plain::Outcome, st::StepOutcome)::Verdict
    if st.status === :stuck
        # Salted with the command that could not advance.
        return Verdict(:step_stuck, st.detail, :none, :none, 0, st.site, :none)
    end
    # Ran out of commands: the walk never finished, so its observation stream is
    # a prefix and there is nothing sound to compare. Tracked, not reported.
    st.status === :budget && return Verdict(:aborted, st.detail, :none, :none, 0, :none, :none)
    # Budget-aborted plain runs have a truncated stream, so there is nothing
    # sound to compare against.
    plain.status === :aborted && return agree()
    # A `:sg` walk that entered a generator frame: the generator's return value
    # (an expression) replaced the call's value by design, so from that point on
    # the stepped program computes something legitimately different — neither
    # its observations nor its exceptions are comparable to plain interpretation.
    # Invariants 1 (termination, the :stuck check above) still hold; the value
    # oracle stands down for this walk rather than manufacturing divergences.
    st.ingen && return agree()
    if st.status === :threw
        # The generated programs throw on purpose, and a program-thrown
        # exception unwinds through interpreter frames — so the question is not
        # "where did it surface" but "does plain interpretation throw the same
        # thing". Same exception on both: the program threw, not the debugger.
        if plain.status === :threw && plain.excname === st.excname
            return agree()
        end
        if plain.status === :threw
            return Verdict(:step_exception_divergence,
                           "stepping threw $(st.excname), plain interpretation threw " *
                           "$(plain.excname)\n$(st.detail)",
                           plain.excname, st.excname, 0, st.site, :none)
        end
        # Plain interpretation completed and stepping did not: the act of
        # stepping introduced the failure. Salted with the innermost
        # JuliaInterpreter function so distinct breakages get distinct buckets.
        return Verdict(:step_only_throw,
                       "stepping threw where plain interpretation completed\n$(st.detail)",
                       :none, st.excname, 0, st.site, :none)
    end
    d = firstdiff(plain.obs, st.obs)
    if d != 0
        return Verdict(:step_divergence,
                       "obs[$d]: run=$(first(repr(get(plain.obs, d, nothing)), 200)) " *
                       "stepped=$(first(repr(get(st.obs, d, nothing)), 200))",
                       :none, :none, d, sigat(plain, d), obssig(get(st.obs, d, nothing)))
    end
    if length(plain.obs) != length(st.obs)
        return Verdict(:step_divergence,
                       "observation count: run=$(length(plain.obs)) stepped=$(length(st.obs))",
                       :none, :none, min(length(plain.obs), length(st.obs)) + 1, :count, :count)
    end
    return agree()
end

"""
    step_keep(fp; walkseed, nstmts, maxcmds, usebreakpoints) -> keep

The stepping axis's property as a `keep(src)::Bool` predicate, for the shared
shrinker. Replays the *same* `walkseed` walk on the candidate source and asks
whether the verdict still has fingerprint `fp` — i.e. the same class and the
same salt (the stuck command for `step_stuck`, the innermost JuliaInterpreter
function for a step-only/divergent throw, the divergent observation's shape for
`step_divergence`).

Exact command-sequence equality is deliberately *not* required: a shrunk
program has fewer pause points, so the same draws produce a different trace.
Class preservation is the criterion, and it is the one the report is about.
"""
function step_keep(fp::String; walkseed::Int, nstmts::Int, maxcmds::Int,
                   usebreakpoints::Bool)
    return function (src::String)
        ex = parsegate(src)
        ex === nothing && return false
        plain = run_interp(ex; nstmts, interp=RecursiveInterpreter())
        st = step_program(src; walkseed, maxcmds, usebreakpoints, ex)
        st === nothing && return false
        v = classify_step(plain, st)
        return isfinding(v) && fingerprint(v) == fp
    end
end

"""
    step_campaign(; n, baseseed, ...) -> Stats

Generate programs, run each normally, then drive the same program through a
random `debug_command` walk and compare. Findings are reported through the same
`writefinding` path as the differential axis.
"""
function step_campaign(; n::Int=500, baseseed::Int=1, nstmts::Int=600_000,
                       outdir::String=joinpath(@__DIR__, "..", "findings"),
                       journaldir::String=joinpath(@__DIR__, "..", "journal"),
                       cfg::Cfg=Cfg(), progress::Int=50, maxcmds::Int=4000,
                       seeddisk::Bool=true, journalsync::Bool=true,
                       usebreakpoints::Bool=true, doshrink::Bool=true,
                       shrinkruns::Int=150, shrinksecs::Real=180.0)
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
            # The walk gets its own seed, drawn from the generator's stream so a
            # case still reproduces from `seed` alone, but consumed through a
            # *fresh* Xoshiro. Continuing the generator's stream into the walk
            # (what this axis used to do) makes the command sequence a function
            # of the program's size, so no edited candidate can be replayed —
            # see the replay note at the top of this file.
            walkseed = rand(rng, 1:typemax(Int))
            journal_case!(j, seed, src)
            stats.cases += 1
            ex = parsegate(src)
            if ex === nothing
                stats.discarded += 1
                continue
            end
            # Reference for this axis is *plain interpretation* of the same
            # program, not compiled Julia: the question is whether stepping
            # changes the answer, and any interp-vs-compiled divergence is the
            # other axis's job to report.
            plain = run_interp(ex; nstmts, interp=RecursiveInterpreter())
            st = step_program(src; walkseed, maxcmds, usebreakpoints, ex)
            if st === nothing
                stats.discarded += 1
                continue
            end
            v = classify_step(plain, st)
            if v.class === :agree
                stats.agreed += 1
            elseif v.class === :aborted
                stats.aborted += 1
            elseif suppressed(v)
                stats.suppressed += 1
            else
                fp = tagfp(:step, fingerprint(v))
                if fp in seen
                    stats.duplicates += 1
                else
                    push!(seen, fp)
                    stats.findings += 1
                    @info "STEP FINDING $(v.class)" seed fp walkseed ncommands = st.ncommands detail = first(v.detail, 400)
                    shrunk = src
                    if doshrink
                        budget = ShrinkBudget(; maxruns=shrinkruns, seconds=shrinksecs)
                        keep = step_keep(fingerprint(v); walkseed, nstmts, maxcmds, usebreakpoints)
                        shrunk = render(shrink_ir(prog, keep; budget))
                        @info "  shrunk" runs = budget.runs lines_orig = countlines(IOBuffer(src)) lines_shrunk = countlines(IOBuffer(shrunk))
                    end
                    writefinding(outdir, fp, v, seed, src, shrunk; mode=:step, walkseed)
                end
            end
            if progress > 0 && i % progress == 0
                @info "step progress" i rate_per_s = round(stats.cases / (time() - t0); digits=2) stats.agreed stats.aborted stats.findings stats.duplicates stats.discarded
            end
        end
    finally
        close(j)
    end
    return stats
end
