# The corpus axis: real Julia code, and splices of it.
#
# Why this exists. A grammar can only emit constructs someone wrote a rule for.
# Real Julia uses things this grammar will never invent — generators and
# `do` blocks, broadcasting and `@view`, parametric types with constraints,
# iteration protocols, macros expanding to who-knows-what, `where` clauses,
# nested closures over loop variables, the whole Base idiom vocabulary. Those
# reach interpreter code paths generated programs never touch. This is the
# tree-splicer/icemaker approach: derive inputs from a real corpus instead of
# authoring an ever-larger grammar.
#
# The catch, and why this axis exists separately. Real code is *not
# deterministic and not terminating*, so it cannot use the differential value
# oracle: it does I/O, calls `rand` and `time`, iterates dictionaries, prints,
# depends on machine state. Comparing observation streams against compiled
# Julia would drown in false positives — which is exactly why the grammar
# excludes all of that by construction.
#
# The oracle is instead differential on *failure mode only*:
#
#   1. Run the fragment with `Core.eval` in a fresh module. If that throws, the
#      fragment doesn't stand alone — a snippet lifted out of a test file
#      references names its file imported — and the case is discarded.
#   2. Otherwise run it interpreted. Compiled Julia handled it, so if the
#      interpreter throws, that is a finding.
#   3. Then step it. Values are not comparable, but "the debugger must not fall
#      over or freeze" holds regardless of determinism.
#
# Comparing only *whether* execution failed, never what it computed, is what
# makes nondeterministic real code usable. The tempting shortcut — "an error is
# the interpreter's fault if its backtrace mentions JuliaInterpreter" — does not
# work: a fragment's own UndefVarError unwinds through interpreter frames too,
# and that heuristic reported `@testset not defined` and `Diagonal not defined`
# as interpreter bugs on the first run of this axis.
#
# Splicing unrelated fragments is safe under this oracle: the result is usually
# nonsense that fails on both sides and is discarded. Nonsense that *does* run
# is the prize, since it is code no test suite contains.

using JuliaInterpreter: ExprSplitter, Frame

# Constructs that make a fragment unsafe to execute in-process: side effects on
# the machine, unbounded blocking, or anything that could take the fuzzer down
# with it. Matched textually against the rendered fragment — deliberately
# conservative, since a false skip only costs corpus size.
const CORPUS_DENY = (
    "ccall", "unsafe_", "@threads", "Threads.", "@async", "@spawn", "@distributed",
    "remotecall", "addprocs", "run(", "readline", "readuntil", "stdin", "download",
    "open(", "write(", "rm(", "mkdir", "mktemp", "touch(", "cp(", "mv(",
    "include(", "Pkg.", "exit(", "sleep(", "@time", "@timed", "@profile",
    "while true", "Base.eval", "Core.eval", "@eval", "atexit", "finalizer",
    "ENV[", "cd(", "libc", "dlopen", "@test_throws", "GC.gc",
)

# Method definitions on names owned by another module (`Base.foo(x) = ...`)
# register globally and would leak between cases — and could break the fuzzer
# itself. Cheap syntactic check for a qualified definition target.
function defines_foreign_method(ex)
    (ex isa Expr && (ex.head === :function || ex.head === :(=))) || return false
    sig = ex.args[1]
    while sig isa Expr && (sig.head === :where || sig.head === :(::))
        sig = sig.args[1]
    end
    sig isa Expr && sig.head === :call || return false
    f = sig.args[1]
    while f isa Expr && f.head === :curly
        f = f.args[1]
    end
    return f isa Expr && f.head === :.        # Base.foo, Mod.bar, ...
end

function corpus_ok(ex)::Bool
    ex isa LineNumberNode && return false
    ex isa Expr || return false
    # `module` blocks and imports pull in the world; skip both.
    ex.head in (:module, :import, :using, :export, :toplevel) && return false
    defines_foreign_method(ex) && return false
    src = try
        string(ex)
    catch
        return false
    end
    length(src) > 4000 && return false
    any(d -> occursin(d, src), CORPUS_DENY) && return false
    return true
end

"""
    load_corpus(dirs; maxfiles, maxperfile) -> Vector{Expr}

Parse every `.jl` file under `dirs` and collect the top-level expressions that
pass `corpus_ok`. These are the raw material for both the standalone and
spliced modes.
"""
function load_corpus(dirs::Vector{String}; maxfiles::Int=400, maxperfile::Int=40)
    out = Expr[]
    nfiles = 0
    for dir in dirs
        isdir(dir) || continue
        for (root, _, files) in walkdir(dir)
            for f in files
                endswith(f, ".jl") || continue
                nfiles >= maxfiles && break
                path = joinpath(root, f)
                text = try
                    read(path, String)
                catch
                    continue
                end
                length(text) > 400_000 && continue
                parsed = try
                    Meta.parseall(text)
                catch
                    continue
                end
                (parsed isa Expr && parsed.head === :toplevel) || continue
                nfiles += 1
                taken = 0
                for ex in parsed.args
                    taken >= maxperfile && break
                    corpus_ok(ex) || continue
                    push!(out, ex)
                    taken += 1
                end
            end
        end
    end
    return out
end

# Default corpus locations: Julia's own test suite and stdlib (both ship with a
# normal install), plus this package's tests. Julia's test files are the ideal
# seed — they are dense, idiomatic, and deliberately exercise edge cases.
function default_corpus_dirs()
    dirs = String[]
    for d in (joinpath(dirname(dirname(Sys.BINDIR)), "test"),
              joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "test"))
        isdir(d) && (push!(dirs, d); break)
    end
    isdir(Sys.STDLIB) && push!(dirs, Sys.STDLIB)
    local repotests = joinpath(@__DIR__, "..", "..", "test")
    isdir(repotests) && push!(dirs, repotests)
    return dirs
end

# Build one case: `k` fragments spliced together. k == 1 is "run real code as
# written"; k > 1 produces combinations that exist in no file, which is the
# point of splicing.
function splice_case(rng::AbstractRNG, corpus::Vector{Expr}, k::Int)
    isempty(corpus) && return nothing
    parts = Expr[pick(rng, corpus) for _ in 1:k]
    return Expr(:toplevel, parts...)
end

struct CorpusOutcome
    # :ok    — compiled Julia and the interpreter both handled it
    # :junk  — the fragment doesn't stand alone (compiled Julia threw too), or the
    #          budget ran out: nothing to conclude, and not worth stepping
    status::Symbol   # :ok | :junk | :internal_error | :step_internal_error | :step_stuck
    detail::String
    site::Symbol
end

# Spliced real code fails constantly on its own terms — a fragment lifted out of
# a test file references names its file imported, so `@testset` and `Diagonal`
# are simply not defined in a fresh module. Those errors unwind through
# interpreter frames like any other, so "the backtrace mentions
# JuliaInterpreter" cannot tell them from an interpreter bug (the same trap the
# stepping axis fell into).
#
# The reference here is compiled Julia on the *same* fragment, compared only on
# whether it fails and with what exception type — never on values, which real
# code has no obligation to reproduce. If `Core.eval` also dies, the fragment is
# junk and is discarded. Only "compiled Julia handled this and the interpreter
# did not" is a finding.
# A module that real test-suite code has a chance of running in. Without these
# imports a fragment lifted from Julia's test/ dir dies immediately on `@test`
# or `Random` and is discarded as junk — measured, 128 of 150 cases were thrown
# away for that reason alone, so the axis was testing almost nothing.
const CORPUS_PRELUDE = [:(using Test), :(using Random), :(using LinearAlgebra),
                        :(using Dates), :(using Printf)]

function corpusmodule()
    m = freshmodule()
    for st in CORPUS_PRELUDE
        try
            Core.eval(m, st)
        catch
            # a stdlib that isn't available just means fewer fragments run
        end
    end
    return m
end

function eval_ref(ex::Expr)
    m = corpusmodule()
    try
        for st in ex.args
            st isa LineNumberNode && continue
            Core.eval(m, st)
        end
        return (:done, :none)
    catch err
        return (:threw, scrubexc(err))
    end
end

function corpus_run(ex::Expr; nstmts::Int)
    refstatus, refexc = eval_ref(ex)
    m = corpusmodule()
    intstatus, intexc, detail, site = try
        for (mod, frag) in ExprSplitter(m, ex)
            frame = Frame(mod, frag)
            budget = nstmts
            while true
                ret, budget = evaluate_limited!(RecursiveInterpreter(), frame, budget, true)
                ret isa Aborted && return CorpusOutcome(:junk, "budget", :none)
                ret isa Some && break
                ret === nothing || break
            end
        end
        (:done, :none, "", :none)
    catch err
        err isa AbortException && return CorpusOutcome(:junk, "budget", :none)
        s = internalframe(stacktrace(catch_backtrace()))
        (:threw, scrubexc(err),
         string(nameof(typeof(err)), s === nothing ? "" : string(" in ", s[1], " (", s[2], ")"),
                ": ", shortstr(err)),
         s === nothing ? :none : Symbol(s[1]))
    end
    # The fragment doesn't stand alone (missing imports, bad splice): discard.
    refstatus === :threw && return CorpusOutcome(:junk, "reference threw $refexc", :none)
    intstatus === :done && return CorpusOutcome(:ok, "", :none)
    return CorpusOutcome(:internal_error,
                         "compiled Julia ran this fragment; the interpreter threw $intexc\n$detail",
                         site)
end

# Step the same case. Real code is nondeterministic, so its *values* are not
# comparable — but "the debugger must not fall over or freeze" holds regardless,
# and this is the only way those code paths ever see real Julia.
#
# Only called for fragments compiled Julia already ran cleanly (see
# corpus_campaign), so an exception escaping here is not the fragment's own
# error. A throw is still only reported when it surfaces inside
# JuliaInterpreter: stepping executes the same code, which may legitimately
# throw partway if a command skips an initialization.
function corpus_step(ex::Expr, rng::AbstractRNG; maxcmds::Int)
    m = corpusmodule()
    interp = RecursiveInterpreter()
    total = 0
    try
        for (mod, frag) in ExprSplitter(m, ex)
            frame = Frame(mod, frag)
            status, n, stuckcmd = walkframe!(rng, interp, frame, maxcmds - total)
            total += n
            status === :stuck && return CorpusOutcome(:step_stuck,
                "`:$stuckcmd` made no progress $STUCK_LIMIT times in a row", stuckcmd)
            status === :budget && return CorpusOutcome(:junk, "budget", :none)
        end
        return CorpusOutcome(:ok, "", :none)
    catch err
        site = internalframe(stacktrace(catch_backtrace()))
        site === nothing && return CorpusOutcome(:ok, "", :none)
        return CorpusOutcome(:step_internal_error,
                             string(nameof(typeof(err)), " in ", site[1], " (", site[2], "): ",
                                    shortstr(err)),
                             Symbol(site[1]))
    end
end

corpusverdict(o::CorpusOutcome) =
    (o.status === :ok || o.status === :junk) ? agree() :
    Verdict(Symbol(:corpus_, o.status), o.detail, :none, :none, 0, o.site, :none)

"""
    corpus_campaign(; n, baseseed, maxsplice, dirs, ...) -> Stats

Draw `n` cases by splicing `1:maxsplice` fragments of real Julia source, run
each interpreted and stepped, and report anything that breaks JuliaInterpreter
itself.
"""
function corpus_campaign(; n::Int=500, baseseed::Int=1, nstmts::Int=200_000,
                         outdir::String=joinpath(@__DIR__, "..", "findings"),
                         journaldir::String=joinpath(@__DIR__, "..", "journal"),
                         dirs::Vector{String}=default_corpus_dirs(), maxsplice::Int=3,
                         maxcmds::Int=1500, progress::Int=50, dostep::Bool=true,
                         seeddisk::Bool=true, journalsync::Bool=true)
    corpus = load_corpus(dirs)
    @info "corpus loaded" nfragments = length(corpus) dirs
    isempty(corpus) && (@warn "empty corpus — nothing to do"; return Stats())
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
            k = rand(rng, 1:maxsplice)
            case = splice_case(rng, corpus, k)
            case === nothing && continue
            src = join([string(a) for a in case.args], "\n")
            journal_case!(j, seed, src)
            stats.cases += 1
            # Lowering is part of what we are testing, so no parse gate here:
            # a fragment that does not lower is skipped by ExprSplitter itself.
            o = corpus_run(case; nstmts)
            # Only step fragments compiled Julia already ran cleanly: stepping a
            # fragment that cannot run at all says nothing about the debugger.
            if o.status === :ok && dostep
                o = corpus_step(case, rng; maxcmds)
            end
            v = corpusverdict(o)
            # Track discards separately: if nearly every case is junk, the
            # corpus filter or the splice arity is wrong and the axis is
            # testing almost nothing, which a 100%-agreed line would hide.
            o.status === :junk && (stats.aborted += 1)
            if v.class === :agree
                stats.agreed += 1
            elseif suppressed(v)
                stats.suppressed += 1
            else
                fp = tagfp(:corpus, fingerprint(v))
                if fp in seen
                    stats.duplicates += 1
                else
                    push!(seen, fp)
                    stats.findings += 1
                    @info "CORPUS FINDING $(v.class)" seed fp nfragments = k detail = first(v.detail, 400)
                    writefinding(outdir, fp, v, seed, src, src; mode=:corpus)
                end
            end
            if progress > 0 && i % progress == 0
                @info "corpus progress" i rate_per_s = round(stats.cases / (time() - t0); digits=2) ran = stats.agreed - stats.aborted discarded = stats.aborted stats.findings stats.duplicates
            end
        end
    finally
        close(j)
    end
    return stats
end
