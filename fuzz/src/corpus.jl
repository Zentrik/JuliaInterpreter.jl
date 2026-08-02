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

# Operations a corpus fragment must not perform in the fuzzer's own process:
# they touch the machine outside it, block without bound, or hand execution to
# another task or the compiler in ways this harness cannot bound.
#
# These are *names checked in call position*, not substrings of the rendered
# source. Text matching gets this wrong in both directions: `myopen(x)` contains
# "open(" and would be skipped for no reason, while a call written `Base.rm(p)`
# or `f = rm; f(p)` slips past a search for "rm(". Walking the AST and looking
# at what is actually being called is the same policy expressed precisely.
#
# This is still a policy list rather than a guarantee — an indirect call
# (`getfield(Base, :rm)(p)`) defeats any static check. The guarantee has to come
# from isolation, and the harness's existing answer is the crash-safe journal
# plus a restart loop (see DESIGN.md): a case that kills the worker leaves its
# reproducer behind. This list keeps the common, obviously-unsafe cases from
# needing that recovery at all.
const UNSAFE_NAMES = Set{Symbol}([
    # process, filesystem, network
    :run, :open, :write, :read, :readline, :readuntil, :readlines, :rm, :mkdir, :mkpath,
    :mktemp, :mktempdir, :touch, :cp, :mv, :chmod, :cd, :download, :redirect_stdout,
    :redirect_stderr, :exit, :atexit, :finalizer,
    # concurrency: task bodies escape the interpreter, and blocking hangs the run
    :sleep, :wait, :fetch, :schedule, :yield, :take!, :put!, :lock, :unlock,
    :addprocs, :remotecall, :remotecall_fetch, :remote_do,
    # foreign calls and raw memory
    :ccall, :cglobal, :dlopen, :dlsym, :unsafe_load, :unsafe_store!, :unsafe_wrap,
    :unsafe_pointer_to_objref, :pointer, :pointer_from_objref,
    # reflection that re-enters eval or the package system
    :eval, :include, :include_string, :evalfile,
])

const UNSAFE_MACROS = Set{Symbol}([
    Symbol("@async"), Symbol("@sync"), Symbol("@spawn"), Symbol("@threads"),
    Symbol("@distributed"), Symbol("@everywhere"), Symbol("@eval"), Symbol("@generated"),
    Symbol("@time"), Symbol("@timed"), Symbol("@elapsed"), Symbol("@profile"),
    Symbol("@allocated"), Symbol("@ccall"), Symbol("@cfunction"), Symbol("@test_throws"),
])

# The callee of a call expression, reduced to a bare name: `f`, `Mod.f`, and
# `f{T}` all answer `:f`, so a qualified or parameterized spelling cannot slip
# past the check.
function calleename(@nospecialize(f))
    while true
        if f isa Symbol
            return f
        elseif f isa Expr && f.head === :. && length(f.args) >= 2 && f.args[2] isa QuoteNode
            f = (f.args[2]::QuoteNode).value    # Mod.name -> name
        elseif f isa Expr && (f.head === :curly || f.head === :where)
            f = f.args[1]                       # f{T} -> f
        elseif f isa GlobalRef
            return f.name
        else
            return nothing
        end
    end
end

# Does this expression call, or macro-expand to, anything on the lists above?
# Also rejects `while true`, whose only exits are `break`/`return`/throw and
# which the harness cannot bound if the body has none.
function calls_unsafe(@nospecialize(ex))::Bool
    ex isa Expr || return false
    if ex.head === :call || ex.head === :.
        n = calleename(ex.head === :call ? ex.args[1] : ex)
        n !== nothing && n in UNSAFE_NAMES && return true
    elseif ex.head === :macrocall
        n = calleename(ex.args[1])
        n !== nothing && n in UNSAFE_MACROS && return true
    elseif ex.head === :while
        ex.args[1] === true && return true
    end
    for a in ex.args
        calls_unsafe(a) && return true
    end
    return false
end

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
    # `module` blocks and imports are handled separately: imports become the
    # fragment's prelude, and a nested module pulls in its own world.
    ex.head in (:module, :import, :using, :export, :toplevel) && return false
    defines_foreign_method(ex) && return false
    calls_unsafe(ex) && return false
    # Very large fragments cost interpretation time out of proportion to what
    # they add, and are usually whole test suites rather than units of code.
    exprsize(ex) > 600 && return false
    return true
end

# Node count — a structural size measure, unlike the length of the rendered
# string, which varies with identifier length and formatting.
function exprsize(@nospecialize(ex))
    ex isa Expr || return 1
    n = 1
    for a in ex.args
        n += exprsize(a)
    end
    return n
end

# A fragment plus the imports its own file declared. Carrying the file's
# `using`/`import` lines with it is what makes a lifted snippet runnable: a
# fragment from a Dates test needs `using Dates`, one from SparseArrays needs
# something else entirely, and no fixed list of stdlibs gets that right.
struct Fragment
    ex::Expr
    prelude::Vector{Expr}
end

"""
    load_corpus(dirs; maxfiles, maxperfile) -> Vector{Fragment}

Parse every `.jl` file under `dirs` and collect the top-level expressions that
pass `corpus_ok`, each tagged with the `using`/`import` statements from the
file it came from.
"""
function load_corpus(dirs::Vector{String}; maxfiles::Int=400, maxperfile::Int=40)
    out = Fragment[]
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
                # The file's own imports, in file order, so a fragment can be
                # replayed in an environment resembling the one it was written
                # for.
                prelude = Expr[ex for ex in parsed.args
                               if ex isa Expr && (ex.head === :using || ex.head === :import)]
                taken = 0
                for ex in parsed.args
                    taken >= maxperfile && break
                    corpus_ok(ex) || continue
                    push!(out, Fragment(ex, prelude))
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

# Build one case: `k` fragments spliced together, carrying the union of their
# files' imports. k == 1 is "run real code as written"; k > 1 produces
# combinations that exist in no file, which is the point of splicing.
function splice_case(rng::AbstractRNG, corpus::Vector{Fragment}, k::Int)
    isempty(corpus) && return nothing
    parts = Fragment[pick(rng, corpus) for _ in 1:k]
    prelude = Expr[]
    for p in parts, imp in p.prelude
        any(isequal(imp), prelude) || push!(prelude, imp)
    end
    return (Expr(:toplevel, (p.ex for p in parts)...), prelude)
end

struct CorpusOutcome
    # :ok    — compiled Julia and the interpreter both handled it
    # :junk  — the fragment doesn't stand alone (compiled Julia threw too), or the
    #          budget ran out: nothing to conclude, and not worth stepping
    status::Symbol   # :ok | :junk | :internal_error | :step_internal_error | :step_stuck
    detail::String
    site::Symbol
    prelude::Vector{Expr}   # the imports the reference run actually needed
end
CorpusOutcome(status, detail, site) = CorpusOutcome(status, detail, site, Expr[])

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
# A module a lifted fragment has a chance of running in: the imports come from
# the fragment's own file, so whatever it was written against is what gets
# loaded. Without any prelude, 128 of 150 cases were discarded for missing
# names and the axis tested almost nothing.
function corpusmodule(prelude::Vector{Expr})
    m = freshmodule()
    for st in prelude
        try
            Core.eval(m, st)
        catch
            # a dependency that will not load just means fewer fragments run
        end
    end
    return m
end

# Which already-loaded module would supply this name? A fragment lifted out of
# Julia's test suite usually does *not* carry the import it needs — the file was
# `include`d by a runtests.jl that had already done `using Test` — so its own
# prelude is incomplete no matter how faithfully it is collected.
#
# Rather than guess a fixed list of stdlibs, ask the failure what it wants:
# `UndefVarError` names the missing binding, and the set of modules that could
# provide it is discoverable from the ones already loaded in this process. That
# covers whatever the corpus happens to need, including modules a future corpus
# directory pulls in.
function supplying_module(name::Symbol)
    for (_, m) in Base.loaded_modules
        m === Main && continue
        try
            name in names(m) && isdefined(m, name) && return m
        catch
            continue
        end
    end
    return nothing
end

# Evaluate with compiled Julia, repairing missing imports as they surface. The
# repaired prelude is returned so the interpreted run sees the same environment.
function eval_ref(ex::Expr, prelude::Vector{Expr}; maxrepairs::Int=4)
    prelude = copy(prelude)
    for _ in 0:maxrepairs
        m = corpusmodule(prelude)
        err = try
            for st in ex.args
                st isa LineNumberNode && continue
                Core.eval(m, st)
            end
            nothing
        catch e
            e
        end
        err === nothing && return (:done, :none, prelude)
        # Unwrap the LoadError that macro expansion wraps failures in.
        while err isa LoadError
            err = err.error
        end
        if err isa UndefVarError
            mod = supplying_module(err.var)
            if mod !== nothing
                imp = Expr(:using, Expr(:., Symbol(mod)))
                if !any(isequal(imp), prelude)
                    push!(prelude, imp)
                    continue      # retry with the name in scope
                end
            end
        end
        return (:threw, scrubexc(err), prelude)
    end
    return (:threw, :UndefVarError, prelude)
end

function corpus_run(ex::Expr, prelude::Vector{Expr}; nstmts::Int)
    # eval_ref returns the prelude it needed, so the interpreted run and the
    # stepping run see exactly the environment the reference succeeded in.
    refstatus, refexc, prelude = eval_ref(ex, prelude)
    m = corpusmodule(prelude)
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
    refstatus === :threw && return CorpusOutcome(:junk, "reference threw $refexc", :none, prelude)
    intstatus === :done && return CorpusOutcome(:ok, "", :none, prelude)
    return CorpusOutcome(:internal_error,
                         "compiled Julia ran this fragment; the interpreter threw $intexc\n$detail",
                         site, prelude)
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
function corpus_step(ex::Expr, prelude::Vector{Expr}, rng::AbstractRNG; maxcmds::Int)
    m = corpusmodule(prelude)
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
# Throughput note: this axis is ~3s/case, roughly 30x slower than the
# generated-program axes, and that is the axis working rather than a problem to
# fix. Generated programs are small and mostly discarded cheaply; real code
# that passes the reference gate actually runs, and running it under
# RecursiveInterpreter means interpreting Base. The statement budget is
# correspondingly lower than the other axes' — a real fragment that needs more
# than this is not going to finish, and aborting it early buys more cases.
function corpus_campaign(; n::Int=500, baseseed::Int=1, nstmts::Int=60_000,
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
            sc = splice_case(rng, corpus, k)
            sc === nothing && continue
            case, prelude = sc
            src = join(vcat([string(p) for p in prelude], [string(a) for a in case.args]), "\n")
            journal_case!(j, seed, src)
            stats.cases += 1
            # Lowering is part of what we are testing, so no parse gate here:
            # a fragment that does not lower is skipped by ExprSplitter itself.
            o = corpus_run(case, prelude; nstmts)
            # Only step fragments compiled Julia already ran cleanly: stepping a
            # fragment that cannot run at all says nothing about the debugger.
            if o.status === :ok && dostep
                o = corpus_step(case, o.prelude, rng; maxcmds)
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
