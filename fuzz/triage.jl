# Version-aware triage of a finding: which side actually broke, and is it a bug
# that still exists?
#
#   julia --project=fuzz fuzz/triage.jl <path> [--timeout SECS] [--mode rec|cmp]
#                                              [--channel CHAN] [--nowrite]
#
# <path> is either a `findings/<class>-<fp>/` directory, a `repro.jl` from one,
# or a bare candidate `.jl` file (a journal entry, a crashmin output — anything
# that is just the program source).
#
# Two questions, in order:
#
#  1. **Which side broke?** The in-process differential runner cannot answer
#     this once a candidate takes the worker down with it, and it cannot cleanly
#     answer it even for exceptions, because both sides ran in the same process.
#     So run each side alone, in its own `julia`, under a timeout, and attribute
#     by exit status: a signal death or an unusual exit code is a *crash*, exit
#     1 is an uncaught exception, exit 0 is a clean run. Same subprocess +
#     timeout + exit-status shape `crashmin.jl` uses to decide whether an edit
#     preserved a crash; same prelude and same interpreted-side driving as
#     `reprolib.jl`, which this file `include`s rather than re-derives.
#
#  2. **Is it already fixed?** A crash on the *reference* side is compiled
#     Julia crashing on ordinary source — a JULIA bug, not a JuliaInterpreter
#     bug, and one that may well be fixed in a newer release. So re-run that
#     side under the newest installed Julia (`julia +release`, i.e. juliaup) and
#     say whether it still reproduces. NEXT.md item 1 exists because a whole
#     episode — journal replay, minimization, C-Reduce, a delegated reduction
#     agent — was spent on a 1.11 codegen regression that 1.12 had already
#     fixed, and one version check up front would have answered it.
#
# What this deliberately does NOT do: attribute a bug from the *contents* of a
# backtrace. A program-thrown exception unwinds through interpreter frames too,
# so "JuliaInterpreter appears in the stack" is true of every generated program
# that throws on purpose. Attribution here is only ever "this side, run alone,
# did something the other side did not".
#
# Two differences from the in-process harness, both deliberate: the interpreted
# side runs *unbudgeted* (`finish_and_return!`, as `reprolib.jl` does), so a
# candidate the harness classified `aborted` shows up here as a timeout rather
# than an abort; and nothing compares observation *values* — that is what the
# finding's own `repro.jl` is for. This tool answers "which side, and is it
# still a bug", not "what differed".

module Triage

# Reuse rather than re-derive: REPRO_SETUP is the observation prelude every
# `findings/*/repro.jl` already runs, and repro_freshmodule is how a fresh
# module gets it.
include(joinpath(@__DIR__, "reprolib.jl"))

const USAGE = """
usage: julia --project=fuzz fuzz/triage.jl <findings-dir | repro.jl | candidate.jl>
              [--timeout SECS] [--mode rec|cmp] [--channel CHAN] [--nowrite]"""

# ---------------------------------------------------------------------------
# Input: get the program source out of whatever the user pointed at.

"""
    extract_src(text) -> String | nothing

Pull the program out of a `findings/*/repro.jl`, which carries it as
`const SRC = "..."`. Returns nothing if the text is not of that shape (in which
case the text *is* the program: journal entries and crashmin output are raw).
"""
function extract_src(text::AbstractString)
    ex = try
        Meta.parseall(String(text))
    catch
        return nothing
    end
    found = Ref{Union{Nothing,String}}(nothing)
    function walk(x)
        x isa Expr || return nothing
        if x.head === :const && length(x.args) == 1 && Meta.isexpr(x.args[1], :(=))
            lhs, rhs = x.args[1].args
            lhs === :SRC && rhs isa String && (found[] = rhs)
        end
        for a in x.args
            walk(a)
        end
        return nothing
    end
    walk(ex)
    return found[]
end

"""
    loadcandidate(path) -> (src, mode, label, dir)

`dir` is the findings directory to write `triage.md` into, or nothing.
`mode` is the interpreter configuration the finding was made under, recovered
from the `cmp-` fingerprint prefix or from the `compiled=true` in repro.jl.
"""
function loadcandidate(path::String)
    isdir(path) || isfile(path) || error("no such file or directory: $path")
    dir = nothing
    file = path
    if isdir(path)
        dir = path
        file = joinpath(path, "repro.jl")
        isfile(file) || error("$path is a directory but has no repro.jl")
    end
    text = read(file, String)
    src = extract_src(text)
    if src === nothing
        src = text          # a raw candidate: journal entry, crashmin output
    end
    tag = basename(rstrip(something(dir, file), '/'))
    mode = (occursin("compiled=true", text) || startswith(tag, "cmp-")) ? :cmp : :rec
    return (src, mode, tag, dir)
end

# ---------------------------------------------------------------------------
# Running one side, alone, in its own process.

struct SideResult
    side::Symbol        # :ref | :interp
    status::Symbol      # :ok | :error | :crash | :timeout
    exitcode::Int
    signal::Int         # decoded signal number (0 if none)
    elapsed::Float64
    out::String
    err::String
    julia::String       # version string of the Julia that ran it
end

# `timeout(1)` reports 124 on expiry and 128+N when the child died by signal N;
# a child that dies by signal without the wrapper shows up as termsignal.
# Anything that is not 0 (clean), 1 (uncaught Julia exception) or a timeout is a
# crash — the same rule crashmin.jl uses to decide what it is minimizing.
function classifyexit(exitcode::Integer, termsignal::Integer)
    termsignal != 0 && return (:crash, termsignal)
    exitcode == 124 && return (:timeout, 0)
    exitcode == 0 && return (:ok, 0)
    exitcode == 1 && return (:error, 0)
    exitcode > 128 && exitcode < 192 && return (:crash, exitcode - 128)
    return (:crash, 0)
end

# The reference side needs no packages at all — it is `Core.eval` of each
# toplevel statement in a fresh module carrying the observation prelude. That is
# what makes the newest-Julia re-run trivial: no project, no manifest, nothing
# to resolve against a different Julia version.
function refscript(progpath::String)
    return """
    const __M__ = Module(:TriageRef)
    for st in Meta.parseall($(repr(REPRO_SETUP))).args
        st isa LineNumberNode && continue
        Core.eval(__M__, st)
    end
    for st in Meta.parseall(read($(repr(progpath)), String)).args
        st isa LineNumberNode && continue
        Core.eval(__M__, st)
    end
    println("__TRIAGE_OK__ observations=", length(Base.invokelatest(getglobal, __M__, :__OBS__)))
    """
end

# The interpreted side is the production toplevel path, driven exactly as
# reprolib.jl drives it (which is why it includes reprolib.jl instead of
# restating the prelude).
function interpscript(progpath::String, mode::Symbol)
    interp = mode === :cmp ? "JuliaInterpreter.NonRecursiveInterpreter()" :
                             "JuliaInterpreter.RecursiveInterpreter()"
    return """
    include($(repr(joinpath(@__DIR__, "reprolib.jl"))))
    const __M__ = repro_freshmodule(:Triage)
    const __EX__ = Meta.parseall(read($(repr(progpath)), String))
    const __I__ = $interp
    for (mod, frag) in ExprSplitter(__M__, __EX__)
        JuliaInterpreter.finish_and_return!(__I__, Frame(mod, frag), true)
    end
    println("__TRIAGE_OK__ observations=", length(Base.invokelatest(getglobal, __M__, :__OBS__)))
    """
end

"""
    runside(side, src; mode, timeoutsecs, juliabin, project) -> SideResult

Run one side of the candidate in a fresh `julia`. `juliabin` defaults to the
running Julia; pass a `Cmd` such as `` `julia +release` `` to test another
version. The reference side runs without any project, so it works under any
Julia; the interpreted side needs the fuzz project for JuliaInterpreter.
"""
function runside(side::Symbol, src::AbstractString; mode::Symbol=:rec,
                 timeoutsecs::Int=120, juliabin::Cmd=Base.julia_cmd(),
                 project::Union{Nothing,String}=nothing,
                 versionlabel::String=string(VERSION))
    dir = mktempdir()
    try
        prog = joinpath(dir, "prog.jl")
        write(prog, src)
        script = joinpath(dir, "side.jl")
        write(script, side === :ref ? refscript(prog) : interpscript(prog, mode))
        outp, errp = joinpath(dir, "out.txt"), joinpath(dir, "err.txt")
        base = project === nothing ? `$juliabin --startup-file=no $script` :
                                     `$juliabin --startup-file=no --project=$project $script`
        cmd = Sys.which("timeout") === nothing ? base : `timeout $timeoutsecs $base`
        t0 = time()
        p = run(pipeline(ignorestatus(cmd), stdout=outp, stderr=errp))
        elapsed = time() - t0
        status, sig = classifyexit(p.exitcode, p.termsignal)
        return SideResult(side, status, Int(p.exitcode), Int(sig), elapsed,
                          read(outp, String), read(errp, String), versionlabel)
    finally
        rm(dir; recursive=true, force=true)
    end
end

# First meaningful line of stderr — the "ERROR: ..." line for an exception, the
# signal message for a crash. Never used to *attribute* anything, only to say
# what happened.
function headline(r::SideResult)
    for ln in split(r.err, '\n')
        s = strip(ln)
        isempty(s) && continue
        startswith(s, "Stacktrace") && break
        return first(s, 300)
    end
    return ""
end

describe(r::SideResult) =
    string(r.status,
           r.status === :crash && r.signal != 0 ? " (signal $(r.signal))" : "",
           r.status === :crash && r.signal == 0 ? " (exit $(r.exitcode))" : "",
           r.status === :timeout ? " (no result within the timeout)" : "",
           " in $(round(r.elapsed; digits=1))s")

# ---------------------------------------------------------------------------
# The newest-Julia question.

"""
    newest_julia(channel) -> Cmd | nothing

The juliaup shim invoked on another channel. Returns nothing when there is no
`julia` on PATH able to serve that channel (a bare Julia install, no juliaup).
"""
function newest_julia(channel::String)
    shim = Sys.which("julia")
    shim === nothing && return nothing
    cmd = `$shim +$channel`
    try
        v = read(pipeline(ignorestatus(`$cmd --version`), stderr=devnull), String)
        occursin("julia version", v) || return nothing
        return cmd
    catch
        return nothing
    end
end

juliaversion(cmd::Cmd) =
    String(strip(replace(read(pipeline(ignorestatus(`$cmd --version`), stderr=devnull), String),
                         "julia version" => "")))

# ---------------------------------------------------------------------------
# Verdict.

crashed(r::SideResult) = r.status === :crash
broke(r::SideResult) = r.status !== :ok

"""
    verdict(ref, int) -> (headline, explanation)

Attribution from what the two isolated runs did — never from backtrace
contents (see the header). `headline` is one line; `explanation` is the
paragraph a human needs before deciding whether to spend time on it.
"""
function verdict(ref::SideResult, int::SideResult)
    if crashed(ref)
        return ("REFERENCE-SIDE CRASH — a JULIA bug, not a JuliaInterpreter bug",
                """
                Compiled Julia (`Core.eval` of this source, no interpreter involved)
                took the process down. JuliaInterpreter cannot be responsible for
                what happens on the reference side, so this belongs upstream:
                report it against Julia, not against this package. The interpreted
                side $(broke(int) ? "also broke ($(int.status)), which is expected once the reference is unsound" : "completed cleanly").""")
    end
    if crashed(int)
        return ("INTERPRETED-SIDE CRASH — JuliaInterpreter bug candidate",
                """
                The interpreted run killed its process while compiled Julia ran the
                same source to completion. That asymmetry is the finding; minimize it
                with `fuzz/crashmin.jl` (adapted to drive the interpreted side) and
                capture it under `julia --bug-report=rr` if it only crashes
                sometimes.""")
    end
    if ref.status === :timeout || int.status === :timeout
        side = ref.status === :timeout ? "reference" : "interpreted"
        return ("TIMEOUT on the $side side — inconclusive",
                """
                No exit status to attribute from. Generated programs terminate by
                construction, so a reference-side timeout means the candidate is not
                one of ours (or the timeout is too short); an interpreted-side
                timeout with a clean reference is the shape of a budget problem
                rather than a hang — re-run in-process with a larger `--budget`
                before treating it as one.""")
    end
    if ref.status === :error && int.status === :ok
        return ("REF-ONLY THROW — divergence, interpreter did not raise",
                """
                Compiled Julia threw and the interpreter completed. Either the
                interpreter failed to raise something it should have, or the two
                sides disagree about a value that decides whether a throw happens.
                Reportable against JuliaInterpreter.""")
    end
    if ref.status === :ok && int.status === :error
        return ("INTERP-ONLY THROW — JuliaInterpreter bug candidate",
                """
                The interpreter threw where compiled Julia completed:
                `$(headline(int))`.
                Note the attribution is the *asymmetry*, not the backtrace: a
                program-thrown exception unwinds through interpreter frames too, so
                the stack alone would say "interpreter" for every generated program
                that throws on purpose.""")
    end
    if ref.status === :error && int.status === :error
        return ("BOTH SIDES THREW — no process-level divergence",
                """
                Reference: `$(headline(ref))`
                Interpreted: `$(headline(int))`
                If the exception types match, the failure mode agrees and whatever
                the harness reported is about *values* or *observation counts*, which
                this tool does not compare — run the finding's `repro.jl` for that.
                If the types differ, it is an exception divergence.""")
    end
    return ("BOTH SIDES COMPLETED — nothing to attribute at the process level",
            """
            Neither side crashed or threw when run alone. The finding, if it is
            still real, is a value or observation-count divergence: run the
            finding's `repro.jl`, which compares the observation streams. A
            candidate that no longer diverges at all is either fixed, budget
            dependent, or was nondeterministic — the confirm-on-divergence gate
            in the harness now discards that last class before reporting.""")
end

# ---------------------------------------------------------------------------

function report(io::IO, label, src, mode, ref, int, rel, relcmd, relver)
    println(io, "# Triage: $label")
    println(io)
    head, why = verdict(ref, int)
    println(io, "**$head**")
    println(io)
    println(io, why)
    println(io)
    println(io, "## Side attribution (each side alone, in its own process)")
    println(io)
    println(io, "| side | result | julia | first stderr line |")
    println(io, "|---|---|---|---|")
    for r in (ref, int)
        nm = r.side === :ref ? "reference (`Core.eval`)" : "interpreted (`$mode`)"
        cell = replace(headline(r), "|" => "\\|")
        println(io, "| $nm | $(describe(r)) | $(r.julia) | `$cell` |")
    end
    println(io)
    println(io, "## Newest installed Julia")
    println(io)
    if rel === nothing
        println(io, relver)
    else
        println(io, "Reference side re-run under $relcmd (Julia $relver): **$(describe(rel))**.")
        println(io)
        if crashed(ref) && !crashed(rel)
            println(io, "The reference-side crash does **not** reproduce on the newest installed Julia: ",
                        "it is fixed upstream. Do not spend minimization effort on it — record the ",
                        "version boundary and move on.")
        elseif crashed(ref) && crashed(rel)
            println(io, "The reference-side crash **still reproduces** on the newest installed Julia. ",
                        "It is worth minimizing (`fuzz/crashmin.jl`) and reporting upstream, against ",
                        "Julia rather than JuliaInterpreter.")
        elseif broke(ref) && !broke(rel)
            println(io, "The reference side no longer fails on the newest installed Julia — the ",
                        "behaviour changed between versions, so check whether the finding is a ",
                        "version artefact before pursuing it.")
        elseif broke(ref) && broke(rel)
            println(io, "The reference side fails the same way on both versions, so this is not a ",
                        "version artefact.")
        else
            println(io, "Recorded for completeness; the reference side is not what broke here.")
        end
    end
    println(io)
    if !isempty(strip(ref.err)) || !isempty(strip(int.err))
        println(io, "## Captured stderr")
        println(io)
        println(io, "Context only. The interpreted side's backtrace runs through ",
                    "JuliaInterpreter for *every* program that throws, including programs ",
                    "that throw on purpose, so nothing above was attributed from it.")
        println(io)
        for r in (ref, int)
            isempty(strip(r.err)) && continue
            println(io, "### $(r.side)")
            println(io)
            println(io, "```")
            println(io, first(strip(r.err), 3000))
            println(io, "```")
            println(io)
        end
    end
    println(io, "## Candidate")
    println(io)
    println(io, "```julia")
    println(io, strip(src))
    println(io, "```")
    return nothing
end

function main(args::Vector{String})
    isempty(args) && (println(USAGE); return 2)
    path = ""
    timeoutsecs = 120
    modeoverride = nothing
    channel = "release"
    nowrite = false
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--timeout"
            timeoutsecs = parse(Int, args[i += 1])
        elseif a == "--mode"
            modeoverride = Symbol(args[i += 1])
        elseif a == "--channel"
            channel = args[i += 1]
        elseif a == "--nowrite"
            nowrite = true
        elseif startswith(a, "--")
            println(USAGE)
            return 2
        else
            path = a
        end
        i += 1
    end
    isempty(path) && (println(USAGE); return 2)

    src, mode, label, dir = loadcandidate(abspath(path))
    modeoverride === nothing || (mode = modeoverride)
    println("triaging: $label")
    println("  interp mode: $mode   timeout: $(timeoutsecs)s   julia: $VERSION")
    println("  $(count(==('\n'), src) + 1) source lines")
    println()

    print("running reference side alone... ")
    ref = runside(:ref, src; timeoutsecs)
    println(describe(ref))
    print("running interpreted side alone... ")
    int = runside(:interp, src; mode, timeoutsecs, project=@__DIR__)
    println(describe(int))

    relcmd = newest_julia(channel)
    rel = nothing
    relver = ""
    if relcmd === nothing
        relver = "No `julia +$channel` available (juliaup not on PATH?) — version check skipped."
        println("newest-Julia check: skipped (no julia +$channel)")
    else
        relver = juliaversion(relcmd)
        if relver == string(VERSION)
            relver = "$relver (same as the Julia running this triage)"
        end
        if broke(ref)
            print("re-running reference side under julia +$channel ($relver)... ")
            rel = runside(:ref, src; timeoutsecs, juliabin=relcmd, versionlabel=relver)
            println(describe(rel))
        else
            println("newest-Julia check: not needed (reference side is clean)")
            relver = "Reference side ran clean on Julia $VERSION, so there was nothing to re-check on `julia +$channel` ($relver)."
        end
    end

    println()
    report(stdout, label, src, mode, ref, int, rel, relcmd, relver)

    if dir !== nothing && !nowrite
        out = joinpath(dir, "triage.md")
        open(out, "w") do io
            report(io, label, src, mode, ref, int, rel, relcmd, relver)
        end
        println()
        println("wrote $out")
    end
    return 0
end

end # module Triage

if abspath(PROGRAM_FILE) == @__FILE__
    exit(Triage.main(String[a for a in ARGS]))
end
