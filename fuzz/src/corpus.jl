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

# Corpus fragments print: a `@testset` lifted from Julia's test suite writes a
# summary, and a failing one writes a stack trace. That is the fragment doing
# its job, not a finding — but at campaign scale it buries the harness's own
# reports and costs real I/O (measured: 261 KB in 11 minutes from one shard).
# Only stdout is redirected; the harness logs through stderr, so its @info
# output and any finding it reports still reach the log.
function quiet_stdout(f)
    old = stdout
    rd, wr = redirect_stdout()
    # Drain the pipe, or a fragment that prints more than the buffer blocks
    # forever waiting for a reader.
    drain = @async read(rd)
    try
        return f()
    finally
        redirect_stdout(old)
        close(wr)
        wait(drain)
        close(rd)
    end
end

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

# Names that introspect the *execution machinery itself* — backtraces and stack
# frames. A fragment asserting on `stacktrace(catch_backtrace())` sees compiled
# frames on the reference and interpreter frames (extra depth, different file/
# line) under JuliaInterpreter; both are correct, so any divergence is an
# artifact of observing the machinery, not an interpreter bug. Worse, such a
# fragment can *self-certify*: the two compiled certification runs agree with
# each other and the case graduates to the value oracle, where the interpreted
# run then "diverges" on frame details — `corpusvalue-interp_only_throw-390a4eeb`
# was exactly this (a `@test bt[1].line == topline + 4` lifted from Julia's test
# suite). Interpreter-visible frame effects are a *known, permanent* divergence
# (the selftest's `:stackprobe` canary proves the pipeline detects it), so these
# fragments carry no signal on any corpus oracle: filter them at admission,
# same call-position AST check as UNSAFE_NAMES.
const FRAME_INTROSPECTION_NAMES = Set{Symbol}([
    :stacktrace, :backtrace, :catch_backtrace, :catch_stack, :current_exceptions,
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

# Same call-position AST walk as `calls_unsafe`, for the frame-introspection
# names: `f = stacktrace; f()` still defeats it, but the qualified and
# parameterized spellings do not.
function introspects_frames(@nospecialize(ex))::Bool
    ex isa Expr || return false
    if ex.head === :call || ex.head === :.
        n = calleename(ex.head === :call ? ex.args[1] : ex)
        n !== nothing && n in FRAME_INTROSPECTION_NAMES && return true
    end
    for a in ex.args
        introspects_frames(a) && return true
    end
    return false
end

function corpus_ok(ex)::Bool
    ex isa LineNumberNode && return false
    ex isa Expr || return false
    # `module` blocks and imports are handled separately: imports become the
    # fragment's prelude, and a nested module pulls in its own world.
    ex.head in (:module, :import, :using, :export, :toplevel) && return false
    defines_foreign_method(ex) && return false
    calls_unsafe(ex) && return false
    introspects_frames(ex) && return false
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
        # `ExprSplitter`/`Frame` expand macros while building the frame, and the
        # prelude was evaluated *at runtime* — so `using Test` is newer than the
        # world this function was compiled in, and a `@testset` in the fragment
        # resolves against a world that has not seen the import. Compiled Julia
        # does not hit this because `Core.eval` expands in the latest world.
        # Without invokelatest the axis reports "compiled Julia ran this and the
        # interpreter threw UndefVarError: @testset" — a difference manufactured
        # entirely by the harness.
        for (mod, frag) in Base.invokelatest(ExprSplitter, m, ex)
            frame = Base.invokelatest(Frame, mod, frag)
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

# ---------------------------------------------------------------------------
# Self-agreement certification (determinism.md §6)
#
# The corpus axis demotes *all* real code to the failure-mode oracle because
# "real code is not deterministic" — but that property is per-fragment and
# measurable. Seed the sandbox RNG, run the compiled reference twice in two fresh
# modules, and compare the observation streams: if they agree, the fragment is
# certified observationally deterministic on this input, and it graduates to the
# full differential value oracle (`classify` applies unchanged). Fragments that
# are deterministic-but-not-idempotent (mutate a stdlib global, consume a
# counter) fail self-agreement and fall back — the safe direction.
#
# Real fragments do not call `__obs__` themselves, so there is nothing to compare
# unless the harness observes it. After a run completes, observe the fragment's
# top-level assigned bindings (like the differential axis observes live
# bindings), conservatively: only bindings whose normalized value is
# content-comparable.

# A fixed sandbox seed makes any `rand()` inside a fragment reproducible across
# the two reference runs and the interpreted run (task-local RNG).
const CORPUS_CERT_SEED = 0x00C0FFEE

# Top-level bindings a fragment assigns, in source order. Only simple targets:
# `x = ...`, `const x = ...`, `x::T = ...`, and tuple-destructuring `a, b = ...`.
# Function/type/macro definitions are skipped — their values are not
# content-comparable, and observing them teaches nothing.
function toplevel_assigned_names(ex::Expr)
    names = Symbol[]
    seen = Set{Symbol}()
    add(n) = (n isa Symbol && !(n in seen)) && (push!(names, n); push!(seen, n); true)
    function target(@nospecialize(t))
        if t isa Symbol
            add(t)
        elseif t isa Expr && t.head === :tuple
            for e in t.args
                target(e)
            end
        elseif t isa Expr && (t.head === :(::) || t.head === :ref)
            target(t.args[1])
        end
    end
    function scan(sts)
        for st in sts
            st isa LineNumberNode && continue
            if st isa Expr && (st.head === :toplevel || st.head === :block)
                scan(st.args)   # transparent containers keep bindings at top level
            elseif st isa Expr && st.head === :(=)
                lhs = st.args[1]
                # `f(x) = ...` / `f(x) where T = ...` are function defs, not bindings.
                (lhs isa Expr && (lhs.head === :call || lhs.head === :where)) && continue
                target(lhs)
            elseif st isa Expr && st.head === :const && !isempty(st.args)
                inner = st.args[1]
                (inner isa Expr && inner.head === :(=)) && target(inner.args[1])
            end
        end
    end
    scan(ex.args)
    return names
end

# Conservative content-comparability: a value whose `__fjnorm__` normalization is
# a stable, identity-free, cross-run-comparable scalar or an aggregate of such.
# Everything else (functions, types, modules, structs, pointers, big/lazy
# collections) is skipped — the safe direction.
function comparable_value(@nospecialize(x), depth::Int=0)
    depth > 4 && return false
    (x isa Bool || x isa Number || x isa AbstractString || x isa Symbol ||
     x isa Char || x === nothing) && return true
    try
        if x isa Tuple
            length(x) > 64 && return false
            return all(comparable_value(e, depth + 1) for e in x)
        elseif x isa AbstractArray
            length(x) > 64 && return false
            for i in eachindex(x)
                isassigned(x, i) || return false
                comparable_value(x[i], depth + 1) || return false
            end
            return true
        elseif x isa AbstractSet
            length(x) > 64 && return false
            return all(comparable_value(e, depth + 1) for e in x)
        elseif x isa AbstractDict
            length(x) > 64 && return false
            return all(comparable_value(k, depth + 1) && comparable_value(v, depth + 1)
                       for (k, v) in x)
        elseif x isa Pair
            return comparable_value(x.first, depth + 1) && comparable_value(x.second, depth + 1)
        end
    catch
        return false
    end
    return false
end

# Push the fragment's comparable top-level bindings into `m.__OBS__`, in the
# fixed `names` order, so the value oracle has data to compare. The same
# predicate runs on both engines, so a binding present-and-comparable on one side
# and missing (or a different, non-comparable type) on the other becomes a
# stream-length divergence — which is exactly the ExprSplitter/definition-skipped
# bug class surfacing.
function observe_bindings!(m::Module, names::Vector{Symbol})
    obsfn = Base.invokelatest(getglobal, m, :__obs__)
    for n in names
        Base.invokelatest(isdefined, m, n) || continue
        v = try
            Base.invokelatest(getglobal, m, n)
        catch
            continue
        end
        comparable_value(v) || continue
        try
            Base.invokelatest(obsfn, v)
        catch
            # normalization of this binding failed — skip it, don't fail the run
        end
    end
    return nothing
end

# Compiled reference run of the fragment, seeded and observed, repairing missing
# imports as they surface (like `eval_ref`). Returns (Outcome, repaired_prelude).
function eval_ref_observed(ex::Expr, prelude::Vector{Expr}, names::Vector{Symbol};
                           seed=CORPUS_CERT_SEED, maxrepairs::Int=4)
    prelude = copy(prelude)
    for _ in 0:maxrepairs
        m = corpusmodule(prelude)
        Random.seed!(seed)
        err = try
            for st in ex.args
                st isa LineNumberNode && continue
                Core.eval(m, st)
            end
            nothing
        catch e
            e
        end
        if err === nothing
            observe_bindings!(m, names)
            return (Outcome(:done, :none, getobs(m), "", ""), prelude)
        end
        while err isa LoadError
            err = err.error
        end
        if err isa UndefVarError
            mod = supplying_module(err.var)
            if mod !== nothing
                imp = Expr(:using, Expr(:., Symbol(mod)))
                if !any(isequal(imp), prelude)
                    push!(prelude, imp)
                    continue
                end
            end
        end
        return (Outcome(:threw, scrubexc(err), getobs(m), shortstr(err), ""), prelude)
    end
    return (Outcome(:threw, :UndefVarError, Any[], "", ""), prelude)
end

# One seeded+observed compiled run against an already-complete prelude (no
# repair) — the second certification run and the confirm-gate re-runs.
function eval_frag_observed(ex::Expr, prelude::Vector{Expr}, names::Vector{Symbol};
                            seed=CORPUS_CERT_SEED)
    m = corpusmodule(prelude)
    Random.seed!(seed)
    try
        for st in ex.args
            st isa LineNumberNode && continue
            Core.eval(m, st)
        end
        observe_bindings!(m, names)
        return Outcome(:done, :none, getobs(m), "", "")
    catch err
        while err isa LoadError
            err = err.error
        end
        return Outcome(:threw, scrubexc(err), getobs(m), shortstr(err), "")
    end
end

# Seeded+observed interpreted run (the SUT), returning an Outcome the value
# oracle can compare against the certified reference.
function interp_frag_observed(ex::Expr, prelude::Vector{Expr}, names::Vector{Symbol};
                              seed=CORPUS_CERT_SEED, nstmts::Int)
    m = corpusmodule(prelude)
    Random.seed!(seed)
    try
        for (mod, frag) in Base.invokelatest(ExprSplitter, m, ex)
            frame = Base.invokelatest(Frame, mod, frag)
            budget = nstmts
            while true
                ret, budget = evaluate_limited!(RecursiveInterpreter(), frame, budget, true)
                ret isa Aborted && return Outcome(:aborted, :none, getobs(m), "", "")
                ret isa Some && break
                ret === nothing || break
            end
        end
        Base.invokelatest(observe_bindings!, m, names)
        return Outcome(:done, :none, getobs(m), "", "")
    catch err
        err isa AbortException && return Outcome(:aborted, :none, getobs(m), "", "")
        bt = sprint(Base.show_backtrace, catch_backtrace(); context = :limit => true)
        return Outcome(:threw, scrubexc(err), getobs(m), shortstr(err), first(bt, 3000))
    end
end

# Certify a fragment: run the compiled reference twice, seeded, and compare the
# observation streams with the oracle's own `outcomeeq`. Returns
# (:junk | :certified | :uncertified, ref_outcome, repaired_prelude).
#   :junk        — the fragment threw on the reference even after import repair;
#                  it does not stand alone (today's discard).
#   :certified   — both reference runs completed and agreed → value oracle.
#   :uncertified — the reference ran but the two runs disagreed → fall back to
#                  the failure-mode oracle.
function corpus_certify(ex::Expr, prelude::Vector{Expr}, names::Vector{Symbol};
                        seed=CORPUS_CERT_SEED)
    ref1, prelude = eval_ref_observed(ex, prelude, names; seed)
    ref1.status === :threw && return (:junk, ref1, prelude)
    ref2 = eval_frag_observed(ex, prelude, names; seed)
    (ref2.status === :done && outcomeeq(ref1, ref2)) || return (:uncertified, ref1, prelude)
    return (:certified, ref1, prelude)
end

# Confirm-on-divergence for a certified value finding. The reference is already
# double-agreed (that is what certification is), so re-confirm it once more and
# re-run the interpreted side; a side that disagrees with itself → nondet.
function corpus_value_confirm(ex::Expr, prelude::Vector{Expr}, names::Vector{Symbol},
                              ref::Outcome, int::Outcome; seed=CORPUS_CERT_SEED, nstmts::Int)
    outcomeeq(ref, eval_frag_observed(ex, prelude, names; seed)) || return :nondet_ref
    outcomeeq(int, interp_frag_observed(ex, prelude, names; seed, nstmts)) || return :nondet_interp
    return :stable
end

function corpus_value_confirmed(v::Verdict, ex::Expr, prelude::Vector{Expr},
                                names::Vector{Symbol}, ref::Outcome, int::Outcome;
                                seed=CORPUS_CERT_SEED, nstmts::Int)
    isfinding(v) || return v
    st = corpus_value_confirm(ex, prelude, names, ref, int; seed, nstmts)
    st === :stable && return v
    return nondetverdict(st === :nondet_ref ? :ref : :interp)
end

# The full certified-value pipeline for one case: certify, and if certified run
# the interpreted side, classify, and gate. Returns (tag, verdict, prelude):
#   tag :junk       → discard (v is agree())
#   tag :certified  → v is the value verdict (agree or a confirmed finding)
#   tag :uncertified→ caller should fall back to the failure-mode oracle
function corpus_value_run(ex::Expr, prelude::Vector{Expr}; nstmts::Int, seed=CORPUS_CERT_SEED)
    names = toplevel_assigned_names(ex)
    cst, ref, pl = corpus_certify(ex, prelude, names; seed)
    cst === :junk && return (:junk, agree(), pl)
    cst === :uncertified && return (:uncertified, agree(), pl)
    int = interp_frag_observed(ex, pl, names; seed, nstmts)
    v = classify(ref, int)
    v = corpus_value_confirmed(v, ex, pl, names, ref, int; seed, nstmts)
    return (:certified, v, pl)
end

"""
    corpus_value_keep(fp; nstmts, seed) -> keep

Shrink predicate for a certified value finding: re-split the candidate,
re-certify (a shrink that breaks determinism or removes the binding stops
certifying → edit rejected), re-run the value oracle, and require the same
fingerprint plus stability.
"""
function corpus_value_keep(fp::String; nstmts::Int, seed=CORPUS_CERT_SEED)
    return function (src::String)
        sp = corpus_split(src)
        sp === nothing && return false
        case, prelude = sp
        tag, v, _ = quiet_stdout() do
            corpus_value_run(case, prelude; nstmts, seed)
        end
        tag === :certified || return false
        return isfinding(v) && fingerprint(v) == fp
    end
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
        # invokelatest for the same reason as corpus_run: the prelude's imports
        # are newer than this function's world, and frame construction expands
        # the fragment's macros.
        for (mod, frag) in Base.invokelatest(ExprSplitter, m, ex)
            frame = Base.invokelatest(Frame, mod, frag)
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

# -- shrinking corpus findings ----------------------------------------------
# Corpus findings are real code, not generator IR, so the IR shrinker has
# nothing to work with. What they do have is toplevel structure, which is what
# `ddmin_source` (shrink.jl) minimizes: delete toplevel statements first — a
# spliced case is several fragments and usually only one of them matters — then
# recurse into block bodies, because a surviving fragment is typically one large
# `function` or `@testset` with the interesting statement buried in it.
#
# A rendered corpus case is `prelude ++ fragments`, all as toplevel statements,
# so re-splitting a candidate is just sorting `using`/`import` from the rest.
# Deleting an import the fragment needs makes the reference throw, the case
# becomes junk, the verdict becomes `agree`, and the edit is rejected — the
# oracle keeps the prelude honest without special-casing it.
function corpus_split(src::AbstractString)
    stmts = toplevel_statements(src)
    stmts === nothing && return nothing
    isimport(s) = s isa Expr && (s.head === :using || s.head === :import)
    prelude = Expr[s for s in stmts if isimport(s)]
    rest = Any[s for s in stmts if !isimport(s)]
    isempty(rest) && return nothing
    return (Expr(:toplevel, rest...), prelude)
end

"""
    corpus_keep(fp; nstmts, maxcmds, dostep, walkseed) -> keep

The corpus axis's property as a `keep(src)::Bool` predicate: re-run the
candidate through the same reference-then-interpret-then-step pipeline the
campaign uses and require the same verdict fingerprint (class plus the
JuliaInterpreter-function salt).
"""
function corpus_keep(fp::String; nstmts::Int, maxcmds::Int, dostep::Bool, walkseed::Int)
    return function (src::String)
        sp = corpus_split(src)
        sp === nothing && return false
        case, prelude = sp
        o = quiet_stdout() do
            r = corpus_run(case, prelude; nstmts)
            (r.status === :ok && dostep) ? corpus_step(case, r.prelude, Xoshiro(walkseed); maxcmds) : r
        end
        v = corpusverdict(o)
        return isfinding(v) && fingerprint(v) == fp
    end
end

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
                         seeddisk::Bool=true, journalsync::Bool=true,
                         doshrink::Bool=true, shrinkruns::Int=80, shrinksecs::Real=240.0)
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
            # Own seed for the stepping walk, so a shrunk candidate replays the
            # same walk instead of a different one (see stepfuzz.jl's replay note).
            walkseed = rand(rng, 1:typemax(Int))
            journal_case!(j, seed, src)
            stats.cases += 1
            # Lowering is part of what we are testing, so no parse gate here:
            # a fragment that does not lower is skipped by ExprSplitter itself.
            #
            # First try self-agreement certification (determinism.md §6): if the
            # compiled reference agrees with itself on two seeded runs, the
            # fragment is observationally deterministic on this input and gets the
            # full differential VALUE oracle. Otherwise fall back to today's
            # failure-mode-only oracle (plus stepping). `isvalue` picks the shrink
            # predicate and repro mode accordingly.
            isjunk = false
            iscertified = false   # passed self-agreement (graduated to value oracle)
            isvalue = false       # certified AND value-compared to completion
            v = quiet_stdout() do
                tag, vv, _pl = corpus_value_run(case, prelude; nstmts)
                if tag === :junk
                    isjunk = true
                    return agree()
                elseif tag === :certified
                    iscertified = true
                    # An interp-side budget abort on a certified fragment is
                    # inconclusive, never a finding — fold it into the junk/discard
                    # path exactly as the failure-mode oracle folds budget aborts.
                    if vv.class === :aborted
                        isjunk = true
                        return agree()
                    end
                    isvalue = true
                    return vv
                end
                # :uncertified — the reference did not agree with itself, so real
                # code's nondeterminism is in play: failure-mode + stepping only.
                r = corpus_run(case, prelude; nstmts)
                r2 = (r.status === :ok && dostep) ?
                     corpus_step(case, r.prelude, Xoshiro(walkseed); maxcmds) : r
                r2.status === :junk && (isjunk = true)
                return corpusverdict(r2)
            end
            # Certification rate = fragments that passed self-agreement, whether or
            # not the interpreted comparison later completed (determinism.md §6: a
            # collapse means the gate broke, not the corpus).
            iscertified && (stats.certified += 1)
            # Track discards separately: if nearly every case is junk, the
            # corpus filter or the splice arity is wrong and the axis is
            # testing almost nothing, which a 100%-agreed line would hide.
            isjunk && (stats.aborted += 1)
            if v.class === :nondet_discard
                stats.nondet_discard += 1
                @debug "corpus nondet_discard" seed detail = v.detail
            elseif v.class === :agree
                stats.agreed += 1
            elseif suppressed(v)
                stats.suppressed += 1
            else
                fp = tagfp(isvalue ? :corpusvalue : :corpus, fingerprint(v))
                if fp in seen
                    stats.duplicates += 1
                else
                    push!(seen, fp)
                    stats.findings += 1
                    @info "CORPUS FINDING $(v.class)" seed fp walkseed certified = isvalue nfragments = k detail = first(v.detail, 400)
                    shrunk = src
                    if doshrink
                        budget = ShrinkBudget(; maxruns=shrinkruns, seconds=shrinksecs)
                        keep = isvalue ? corpus_value_keep(fingerprint(v); nstmts) :
                                         corpus_keep(fingerprint(v); nstmts, maxcmds, dostep, walkseed)
                        # no quiet_stdout here: the keep predicate already quiets
                        # each candidate, and nesting the redirect buys nothing
                        shrunk = ddmin_source(src, keep; budget)
                        @info "  shrunk" runs = budget.runs lines_orig = countlines(IOBuffer(src)) lines_shrunk = countlines(IOBuffer(shrunk))
                    end
                    writefinding(outdir, fp, v, seed, src, shrunk;
                                 mode=(isvalue ? :corpusvalue : :corpus), walkseed)
                end
            end
            if progress > 0 && i % progress == 0
                @info "corpus progress" i rate_per_s = round(stats.cases / (time() - t0); digits=2) ran = stats.agreed - stats.aborted discarded_junk = stats.aborted certified = stats.certified stats.findings stats.duplicates
            end
        end
    finally
        close(j)
    end
    return stats
end
