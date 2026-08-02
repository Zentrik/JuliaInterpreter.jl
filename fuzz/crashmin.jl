# Minimize a program that *kills the process*.
#
#   julia --project=fuzz fuzz/crashmin.jl CANDIDATE.jl [--out repro.jl]
#
# The IR shrinker in shrink.jl re-runs each candidate in-process and keeps it if
# the finding's fingerprint survives. That cannot work for a crash: the run that
# would tell you whether the edit preserved the bug is the run that takes the
# process down with it. So this shrinker runs every candidate in a *subprocess*
# and treats "the subprocess died by signal" as the property to preserve.
#
# It works on source text rather than the generator's IR, because a crashing
# candidate arrives as a journal file — the program that was executing when the
# worker died — and by then the IR that produced it is gone with the process.
# Line-oriented delta debugging is enough for that: generated programs are one
# statement per line, so deleting lines is close to deleting statements.

const USAGE = "usage: julia --project=fuzz fuzz/crashmin.jl CANDIDATE.jl [--out FILE] [--timeout SECS]"

length(ARGS) >= 1 || error(USAGE)
candidate = ARGS[1]
isfile(candidate) || error("no such file: $candidate")
outfile = "crash-repro.jl"
timeoutsecs = 120
let i = 2
    while i <= length(ARGS)
        if ARGS[i] == "--out"
            global outfile = ARGS[i += 1]
        elseif ARGS[i] == "--timeout"
            global timeoutsecs = parse(Int, ARGS[i += 1])
        else
            error(USAGE)
        end
        i += 1
    end
end

# Run `src` in a fresh Julia and report whether it died the way we care about.
# A crash is a signal death (segfault, abort) or any exit code Julia does not
# produce on a clean run or an ordinary Julia-level exception. An uncaught
# exception exits 1, which is *not* a crash — the program merely threw.
function crashes(src::AbstractString; timeoutsecs::Int)
    dir = mktempdir()
    try
        script = joinpath(dir, "case.jl")
        # The reference side is what crashed, so reproduce that: plain Core.eval
        # of each toplevel statement in a fresh module, no interpreter involved.
        open(script, "w") do io
            println(io, "const __M__ = Module(:CrashCase)")
            println(io, "for st in Meta.parseall(read(", repr(joinpath(dir, "prog.jl")), ", String)).args")
            println(io, "    st isa LineNumberNode && continue")
            println(io, "    Core.eval(__M__, st)")
            println(io, "end")
        end
        write(joinpath(dir, "prog.jl"), src)
        cmd = `timeout $timeoutsecs $(Base.julia_cmd()) --startup-file=no $script`
        p = run(pipeline(ignorestatus(cmd), stdout=devnull, stderr=devnull))
        # 124 is timeout(1); treat a hang as "not the crash we are chasing", so
        # minimization does not wander into infinite loops.
        return p.termsignal != 0 || (p.exitcode != 0 && p.exitcode != 1 && p.exitcode != 124)
    finally
        rm(dir; recursive=true, force=true)
    end
end

original = read(candidate, String)
println("candidate: $candidate ($(count(==('\n'), original)) lines)")
print("checking that it still crashes... ")
if !crashes(original; timeoutsecs)
    println("NO")
    println("""
    The candidate did not crash a fresh process. That usually means the crash
    depended on state the worker had accumulated — JIT'd code, GC pressure,
    method tables — rather than on this program alone. Re-run the seed with the
    native engine instead of minimizing.""")
    exit(1)
end
println("yes")

# Line-granularity delta debugging: delete progressively smaller runs of lines,
# keeping any deletion that still crashes. Standard ddmin shape — start coarse,
# halve the chunk size when a pass stops helping.
#
# In a function, not at toplevel: a `while` body at toplevel is a soft scope, so
# assigning to `lines`/`chunk` there silently creates locals and the loop reads
# an undefined variable on its first iteration. (The generator had the same bug
# in its own emitted `while` loops; it is an easy one to write twice.)
function ddmin(original::AbstractString; timeoutsecs::Int)
    lines = split(original, '\n')
    chunk = max(1, length(lines) ÷ 2)
    ntests = 0
    while chunk >= 1
        i = 1
        improved = false
        while i <= length(lines)
            trial = vcat(lines[1:i-1], lines[min(i + chunk, length(lines) + 1):end])
            ntests += 1
            if !isempty(strip(join(trial, '\n'))) && crashes(join(trial, '\n'); timeoutsecs)
                lines = trial
                improved = true
                println("  -$chunk lines -> $(length(lines)) remain (test $ntests)")
            else
                i += chunk
            end
        end
        improved || (chunk ÷= 2)
        chunk == 0 && break
    end
    return join(lines, '\n'), ntests
end

minimized, ntests = ddmin(original; timeoutsecs)
write(outfile, minimized)
println()
println("minimized $(count(==('\n'), original)) -> $(count(==('\n'), minimized)) lines in $ntests subprocess runs")
println("wrote $outfile")
println()
println(minimized)
