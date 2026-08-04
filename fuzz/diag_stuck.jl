# Diagnose a step_stuck / long-walk report for one seed.
#
#   julia --project=fuzz fuzz/diag_stuck.jl SEED [MAXCMDS] [WALKSEED]
#
# Answers the two questions triage actually needs: *which command* fails to
# advance, and *what statement* it is sitting on when it does. A command budget
# only ever said "this took a while", which is not the same thing — with
# break-on-error armed, `:c` legitimately stops at every throw.
#
# Reproducing a report means reproducing its *walk*, and the walk has its own
# seed. `step_campaign` seeds one RNG from the case seed, generates the program
# with it, then draws `walkseed` from it and runs the walk on a fresh
# `Xoshiro(walkseed)` — the separation that makes the axis shrinkable (see
# src/stepfuzz.jl). This script mirrors that derivation, so SEED alone
# reproduces a campaign case; pass WALKSEED explicitly (findings record it in
# meta.md) to replay a walk against a *shrunk* program, whose generator seed no
# longer produces the source.

include(joinpath(@__DIR__, "src", "FuzzJI.jl"))
using .FuzzJI
using .FuzzJI: Xoshiro, genprogram, render, parsegate, freshmodule, run_interp,
               STEP_COMMANDS, DRAIN_COMMANDS, pick, STUCK_LIMIT
using JuliaInterpreter
using JuliaInterpreter: debug_command, Frame, BreakpointRef, is_toplevel_frame, ExprSplitter,
                        break_on, break_off, remove, pc_expr, scopeof

seed = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 20168
maxcmds = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 20000

genrng = Xoshiro(seed)
prog = genprogram(genrng)
src = render(prog)
ex = parsegate(src)
ex === nothing && error("seed $seed did not survive the parse gate")

# Same derivation step_campaign uses, unless the caller supplied the walk seed.
walkseed = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : rand(genrng, 1:typemax(Int))
rng = Xoshiro(walkseed)

println("=== seed $seed (walk seed $walkseed): ", count(==('\n'), src), "-line program ===")

m = freshmodule()
interp = JuliaInterpreter.RecursiveInterpreter()

# Mirror step_program's break-on-error draw so the stream stays aligned.
brk = rand(rng) < 0.5
brk ? break_on(:error) : break_off(:error)
println("break_on(:error) armed: ", brk)

function report_stuck(fr, cmd, noops, total, pc)
    println()
    println("STUCK: `:$cmd` made no progress $noops times in a row (after $total commands)")
    println("  frame scope : ", scopeof(fr))
    println("  pc          : ", fr.pc, " of ", length(fr.framecode.src.code), " statements")
    println("  statement   : ", repr(pc_expr(fr)))
    println("  returned pc : ", repr(pc))
    println("  toplevel?   : ", is_toplevel_frame(fr))
    println("  caller?     : ", fr.caller === nothing ? "none" : "yes")
    println("  callee?     : ", fr.callee === nothing ? "none" : "yes")
    println()
    println("  surrounding statements:")
    code = fr.framecode.src.code
    for i in max(1, fr.pc - 3):min(length(code), fr.pc + 3)
        println("    ", i == fr.pc ? ">>" : "  ", lpad(i, 4), "  ", repr(code[i]))
    end
end

function diagnose(m, ex, rng, interp, maxcmds)
    total = 0
    laststate = nothing
    noops = 0
    lastcmd = :none
    for (mod, frag) in ExprSplitter(m, ex)
        fr = Frame(mod, frag)
        while total < maxcmds
            is_toplevel_frame(fr) && (fr.world = Base.get_world_counter())
            cmd = total > 0.8 * maxcmds ? pick(rng, DRAIN_COMMANDS) : pick(rng, STEP_COMMANDS)
            # Mirror walkframe!'s `:sg` variant draw so the stream stays aligned.
            cmd === :s && rand(rng) < 0.15 && (cmd = :sg)
            ret = try
                cmd === :until && rand(rng) < 0.5 ?
                    debug_command(interp, fr, cmd, true; line=rand(rng, 1:40)) :
                    debug_command(interp, fr, cmd, true)
            catch err
                println("threw after $total commands on :$cmd — ", nameof(typeof(err)))
                return (:threw, total)
            end
            total += 1
            ret === nothing && break
            fr, pc = ret
            state = (objectid(fr.framecode), fr.pc)
            if state == laststate
                noops += 1
                if noops >= STUCK_LIMIT
                    report_stuck(fr, lastcmd, noops, total, pc)
                    return (:stuck, total)
                end
            else
                noops = 0
            end
            laststate = state
            lastcmd = cmd
        end
        total >= maxcmds && return (:budget, total)
    end
    return (:done, total)
end

status, total = try
    diagnose(m, ex, rng, interp, maxcmds)
finally
    break_off(:error)
    remove()
end
status === :stuck || println("status=$status after $total commands (budget $maxcmds)")
