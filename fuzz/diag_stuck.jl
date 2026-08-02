# Diagnose a step_nonterminating report: is a command failing to advance, or is
# the program merely large?
#
#   julia --project=fuzz fuzz/diag_stuck.jl SEED
#
# A command budget is only a proxy for "stuck". This looks at the real thing:
# whether (frame, pc) ever repeats across commands, and which command was
# issued when it did.

include(joinpath(@__DIR__, "src", "FuzzJI.jl"))
using .FuzzJI
using .FuzzJI: Xoshiro, genprogram, render, parsegate, freshmodule, run_interp,
               STEP_COMMANDS, pick
using JuliaInterpreter
using JuliaInterpreter: debug_command, Frame, BreakpointRef, is_toplevel_frame, ExprSplitter

seed = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 20168
maxcmds = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 20000

# Mirror step_campaign exactly: one RNG seeded once, used first for generation
# and then continuing into the command walk. A fresh RNG for the walk would
# issue a different command sequence and not reproduce the report.
rng = Xoshiro(seed)
prog = genprogram(rng)
src = render(prog)
ex = parsegate(src)
ex === nothing && error("seed $seed did not survive the parse gate")

println("=== program (seed $seed), ", count(==('\n'), src), " lines ===")

m = freshmodule()
interp = JuliaInterpreter.RecursiveInterpreter()

# Count how often each (framecode, pc) is revisited, and which command was
# issued each time. A command that leaves the state identical is the bug shape.
repeats = Dict{Tuple{UInt,Int},Int}()
stuckcmds = Dict{Symbol,Int}()
cmdcounts = Dict{Symbol,Int}()
total = 0
laststate = nothing

for (mod, frag) in ExprSplitter(m, ex)
    global total, laststate
    fr = Frame(mod, frag)
    while total < maxcmds
        is_toplevel_frame(fr) && (fr.world = Base.get_world_counter())
        cmd = pick(rng, STEP_COMMANDS)
        cmdcounts[cmd] = get(cmdcounts, cmd, 0) + 1
        ret = try
            cmd === :until && rand(rng) < 0.5 ?
                debug_command(interp, fr, cmd, true; line=rand(rng, 1:40)) :
                debug_command(interp, fr, cmd, true)
        catch err
            println("threw after $total commands on :$cmd — ", nameof(typeof(err)))
            break
        end
        total += 1
        ret === nothing && break
        fr, _pc = ret
        state = (objectid(fr.framecode), fr.pc)
        if state == laststate
            stuckcmds[cmd] = get(stuckcmds, cmd, 0) + 1
        end
        laststate = state
        repeats[state] = get(repeats, state, 0) + 1
    end
    total >= maxcmds && break
end

println("commands issued: $total (budget $maxcmds)")
println("distinct (framecode, pc) states visited: ", length(repeats))
top = sort(collect(repeats); by=last, rev=true)[1:min(5, end)]
println("most-revisited states: ", [(s[2], n) for (s, n) in top])
println()
println("commands that left (framecode, pc) UNCHANGED (the stuck shape):")
if isempty(stuckcmds)
    println("  none — every command advanced; the budget was simply too small")
else
    for (c, n) in sort(collect(stuckcmds); by=last, rev=true)
        println("  :", rpad(c, 8), n, " no-ops of ", get(cmdcounts, c, 0), " issued")
    end
end
