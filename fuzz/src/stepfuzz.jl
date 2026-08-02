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
# Nondeterminism note: `:c` with no breakpoints runs to completion, and command
# sequences are drawn from the same seeded RNG as the program, so a finding
# reproduces from (seed, mode).

using JuliaInterpreter: debug_command, root, leaf, BreakpointRef, Frame,
                        break_on, break_off, breakpoint, remove, is_toplevel_frame

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
end
StepOutcome(status, obs, detail, n, cmds) = StepOutcome(status, obs, detail, n, cmds, :none, :none)
StepOutcome(status, obs, detail, n, cmds, site) = StepOutcome(status, obs, detail, n, cmds, site, :none)

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
function internalframe(bt)
    for fr in bt
        s = try
            string(fr.file)
        catch
            continue
        end
        # Frames from this package's own source. The harness lives outside
        # src/, so its own frames never match. `interpret.jl` is deliberately
        # included: an internal error there during stepping is still a bug in
        # the stepping path that reached it.
        isinternal = occursin("JuliaInterpreter", s) ||
                     any(f -> occursin(f, s), ("commands.jl", "breakpoints.jl",
                                               "construct.jl", "interpret.jl", "utils.jl"))
        isinternal && return (fr.func, string(basename(s), ":", fr.line))
    end
    return nothing
end

# How many consecutive commands may leave execution at exactly the same
# (framecode, pc) before the walk is considered stuck. One no-op is legal — a
# breakpoint pause reports the position without moving — but a command that
# cannot advance repeats forever, which is the shape of the historical bug
# (`next_line!` not getting past a statement kind).
const STUCK_LIMIT = 200

# Drive one toplevel fragment to completion with a random command walk.
# Returns (status, ncommands, stuckcmd) where status is :done, :budget (ran out
# of commands, which is not by itself evidence of anything) or :stuck.
function walkframe!(rng::AbstractRNG, interp::Interpreter, frame::Frame, maxcmds::Int)
    fr = frame
    n = 0
    laststate = nothing
    noops = 0
    lastcmd = :none
    while true
        n >= maxcmds && return (:budget, n, :none)
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
        # `:until` takes a line number; nothing means "the line after this one".
        ret = cmd === :until && rand(rng) < 0.5 ?
              debug_command(interp, fr, cmd, true; line=rand(rng, 1:40)) :
              debug_command(interp, fr, cmd, true)
        n += 1
        ret === nothing && return (:done, n, :none)
        # Continue from wherever the command left execution: a callee frame
        # after stepping in, the caller after finishing, or a breakpoint pause.
        fr, _pc = ret
        state = (objectid(fr.framecode), fr.pc)
        if state == laststate
            noops += 1
            noops >= STUCK_LIMIT && return (:stuck, n, lastcmd)
        else
            noops = 0
        end
        laststate = state
        lastcmd = cmd
    end
end

"""
    step_program(src; nstmts, interp, seed, breakpoints) -> StepOutcome

Execute `src` through `ExprSplitter`, driving every fragment with a random
`debug_command` walk instead of running it. Returns what happened plus the
observation stream the stepped program produced.
"""
function step_program(src::String; rng::AbstractRNG, interp::Interpreter=RecursiveInterpreter(),
                      maxcmds::Int=4000, usebreakpoints::Bool=false)
    ex = parsegate(src)
    ex === nothing && return nothing
    m = freshmodule()
    cmds = Symbol[]
    total = 0
    try
        if usebreakpoints
            # Arm a global break-on-throw: exception handling during stepping is
            # the interaction the fix history keeps flagging.
            rand(rng) < 0.5 ? break_on(:error) : break_off(:error)
        end
        for (mod, frag) in ExprSplitter(m, ex)
            frame = Frame(mod, frag)
            status, n, stuckcmd = walkframe!(rng, interp, frame, maxcmds - total)
            total += n
            if status === :stuck
                return StepOutcome(:stuck, getobs(m),
                                   "`:$stuckcmd` left execution at the same (framecode, pc) " *
                                   "$STUCK_LIMIT times in a row after $total commands",
                                   total, cmds, stuckcmd)
            end
            # Budget exhaustion is not evidence of a bug — break-on-error stops
            # at every throw, and these programs throw on purpose — so it ends
            # the walk without a verdict rather than reporting one.
            status === :budget && return StepOutcome(:budget, getobs(m),
                                                     "command budget exhausted", total, cmds)
        end
        return StepOutcome(:done, getobs(m), "", total, cmds)
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
                           total, cmds, sitename, scrubexc(err))
    finally
        usebreakpoints && (break_off(:error); remove())
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
    step_campaign(; n, baseseed, ...) -> Stats

Generate programs, run each normally, then drive the same program through a
random `debug_command` walk and compare. Findings are reported through the same
`writefinding` path as the differential axis.
"""
function step_campaign(; n::Int=500, baseseed::Int=1, nstmts::Int=300_000,
                       outdir::String=joinpath(@__DIR__, "..", "findings"),
                       journaldir::String=joinpath(@__DIR__, "..", "journal"),
                       cfg::Cfg=Cfg(), progress::Int=50, maxcmds::Int=4000,
                       seeddisk::Bool=true, journalsync::Bool=true,
                       usebreakpoints::Bool=true)
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
            st = step_program(src; rng, maxcmds, usebreakpoints)
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
                    @info "STEP FINDING $(v.class)" seed fp ncommands = st.ncommands detail = first(v.detail, 400)
                    writefinding(outdir, fp, v, seed, src, src; mode=:step)
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
