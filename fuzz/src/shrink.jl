# Shrinking: greedy IR-level minimization with repair, plus a statement-level
# delta-debugger for source text that did not come from the generator.
#
# Soundness comes from re-running the candidate after every edit and keeping it
# only if the finding is still there. The repair pass therefore only needs to be
# *usually* valid: an edit that produces a program with a different failure is
# simply rejected.
#
# "Is the finding still there" is a **predicate over rendered source**,
# `keep(src::String)::Bool`, supplied by the caller. That is what lets the four
# axes share one shrinker: the differential axis re-runs `run_both`, compares
# fingerprints and answers yes/no; the stepping axis replays its command walk;
# the eval_code axis replays its pause-and-check procedure; the corpus axis
# re-runs the fragment. Each axis owns its property; the search strategy is
# common code.

# -- budget ------------------------------------------------------------------
# One finding must not be able to stall a campaign. Every candidate evaluation
# goes through `attempt!`, which counts re-executions and watches the clock; the
# search loops stop as soon as either cap is reached and return the best
# candidate found so far. `runs` is also the natural progress number to report.
mutable struct ShrinkBudget
    maxruns::Int        # candidate re-executions
    seconds::Float64    # wall clock, from construction
    runs::Int
    t0::Float64
end
ShrinkBudget(; maxruns::Int=400, seconds::Real=600.0) =
    ShrinkBudget(maxruns, Float64(seconds), 0, time())

exhausted(b::ShrinkBudget) = b.runs >= b.maxruns || (time() - b.t0) >= b.seconds

# Evaluate one candidate against the property, under the budget. A predicate
# that throws (a shrunk corpus fragment that no longer parses, an axis whose
# harness code trips over the edit) counts as "finding not preserved" rather
# than taking the campaign down: rejecting the edit is always safe.
function attempt!(b::ShrinkBudget, keep, src::AbstractString)::Bool
    exhausted(b) && return false
    b.runs += 1
    return try
        keep(String(src))::Bool
    catch err
        err isa InterruptException && rethrow()   # Ctrl-C must still reach the user
        false
    end
end

# -- deep copy (IR nodes are immutable structs over mutable vectors) ---------
cloneex(e::Ex) = Ex(e.kind, e.sum, e.meta, Ex[cloneex(k) for k in e.kids])
clonest(s::St) = St(s.kind, s.meta, Ex[cloneex(e) for e in s.exs], [St[clonest(x) for x in b] for b in s.blocks])
cloneprog(p::Program) = Program(St[clonest(s) for s in p.pre], St[clonest(s) for s in p.fundefs],
                                St[clonest(s) for s in p.mid], St[clonest(s) for s in p.body],
                                p.rngseed)

# -- name accounting ---------------------------------------------------------
function allbound!(out::Set{Symbol}, st::St)
    for n in binds(st)
        push!(out, n)
    end
    if st.kind === :fundef
        for (pn, _, _) in st.meta[2]
            push!(out, pn)
        end
        if length(st.meta) >= 5 && st.meta[5]::Bool     # vararg name
            push!(out, st.meta[6]::Symbol)
        end
        if length(st.meta) >= 4                          # kwparam names
            for (kn, _) in st.meta[4]
                push!(out, kn)
            end
        end
    elseif st.kind === :recdef
        push!(out, :n); push!(out, :acc)
    elseif st.kind === :for
        push!(out, st.meta[1])
    elseif st.kind === :while
        push!(out, st.meta[1])
    elseif st.kind === :let
        for (n, _) in st.meta
            push!(out, n)
        end
    elseif st.kind === :try
        push!(out, st.meta[1])
    elseif st.kind === :assign   # any assignment can (re)create a local
        push!(out, st.meta[1])
    elseif st.kind === :structdef
        push!(out, (st.meta::StructT).name)
    elseif st.kind === :typedlocal
        push!(out, st.meta[1])
    elseif st.kind === :maybeundef
        push!(out, st.meta::Symbol)
    elseif st.kind === :loopundef
        push!(out, st.meta[1])
        push!(out, st.meta[2])
    end
    for e in st.exs
        closureparams!(out, e)
    end
    for b in st.blocks, s in b
        allbound!(out, s)
    end
    return out
end

function closureparams!(out::Set{Symbol}, e::Ex)
    if e.kind === :closure
        for p in e.meta::Vector{Symbol}
            push!(out, p)
        end
    elseif e.kind === :closuremut
        for p in e.meta[1]
            push!(out, p)
        end
    end
    for k in e.kids
        closureparams!(out, k)
    end
end

function allbound(p::Program)
    out = Set{Symbol}()
    for sec in sections(p), s in sec
        allbound!(out, s)
    end
    return out
end

# -- repair: replace references to now-unbound names with inert defaults -----
function repairex(e::Ex, bound::Set{Symbol})::Ex
    if e.kind === :var && !(e.meta::Symbol in bound)
        return defaultex(e.sum)
    end
    if (e.kind === :callvar || e.kind === :call) && !(e.meta::Symbol in bound)
        return defaultex(e.sum)
    end
    if e.kind === :kwcall && !(e.meta[1]::Symbol in bound)
        return defaultex(e.sum)
    end
    if e.kind === :closuremut && !(e.meta[2]::Symbol in bound)
        return defaultex(e.sum)
    end
    return Ex(e.kind, e.sum, e.meta, Ex[repairex(k, bound) for k in e.kids])
end

strefs(st::St) = refs!(Set{Symbol}(), st)

function repairblock!(sts::Vector{St}, bound::Set{Symbol})
    filter!(sts) do st
        if st.kind === :push || st.kind === :setindex ||
           st.kind === :dictset || st.kind === :dictdel || st.kind === :setpush
            (st.meta::Symbol) in bound || return false
        elseif st.kind === :alias
            (st.meta[2]::Symbol) in bound || return false
        elseif st.kind === :setprop || st.kind === :amodify || st.kind === :dictobs
            (st.meta[1]::Symbol) in bound || return false
        end
        return true
    end
    for st in sts
        for i in eachindex(st.exs)
            st.exs[i] = repairex(st.exs[i], bound)
        end
        for b in st.blocks
            repairblock!(b, bound)
        end
    end
end

function repair!(p::Program)
    for _ in 1:4  # removals can unbind further names; a few rounds reach a fixpoint
        bound = allbound(p)
        before = sum(length, sections(p))
        for sec in sections(p)
            repairblock!(sec, bound)
        end
        sum(length, sections(p)) == before && break
    end
    return p
end

# -- candidate edits ---------------------------------------------------------
# Collect every (block, index) pair so removal candidates cover nested blocks.
function allsites(p::Program)
    sites = Tuple{Vector{St},Int}[]
    function walk(sts::Vector{St})
        for (i, st) in enumerate(sts)
            push!(sites, (sts, i))
            for b in st.blocks
                walk(b)
            end
        end
    end
    for sec in sections(p)
        walk(sec)
    end
    return sites
end

function nstatements(p::Program)
    n = 0
    function walk(sts)
        for st in sts
            n += 1
            for b in st.blocks
                walk(b)
            end
        end
    end
    for sec in sections(p)
        walk(sec)
    end
    return n
end

# -- the shrink loop ---------------------------------------------------------
"""
    shrink_ir(prog, keep; budget) -> Program

Greedily minimize the generated program `prog` while `keep(render(candidate))`
keeps answering `true`. `keep` is the axis's property — "this source still
exhibits the finding" — and is the only thing that decides whether an edit is
accepted, so repair only has to be *usually* right.

Two passes, alternating until neither improves or the budget runs out:
statement removal at any nesting depth, then in-place simplification (loop
bounds to zero, non-trivial operands to inert defaults of the same summary).
"""
function shrink_ir(prog::Program, keep; budget::ShrinkBudget=ShrinkBudget())
    check(cand::Program) = attempt!(budget, keep, render(cand))
    best = cloneprog(prog)
    improved = true
    while improved && !exhausted(budget)
        improved = false
        # Pass 1: statement removal. `allsites` enumerates deterministically, so
        # ordinal position `pos` addresses the same statement in a clone.
        nsites = length(allsites(best))
        for pos in nsites:-1:1   # innermost/latest first: big prunes early
            exhausted(budget) && break
            cand = cloneprog(best)
            csites = allsites(cand)
            pos <= length(csites) || continue
            csts, ci = csites[pos]
            deleteat!(csts, ci)
            repair!(cand)
            if check(cand)
                best = cand
                improved = true
                break   # the site list is stale after a removal; restart the pass
            end
        end
        improved && continue
        # Pass 2: in-place simplifications — loop bounds to zero, non-trivial
        # expression operands to inert defaults.
        for pos in 1:length(allsites(best))
            exhausted(budget) && break
            cand = cloneprog(best)
            csites = allsites(cand)
            pos <= length(csites) || continue
            csts, ci = csites[pos]
            st = csts[ci]
            edited = false
            if st.kind === :for && st.meta[2] > 0
                csts[ci] = St(st.kind, (st.meta[1], 0), st.exs, st.blocks)
                edited = true
            elseif st.kind === :while && st.meta[2] > 0
                # keep the trailing toplevel flag: dropping it would un-qualify
                # the fuel decrement and change the program's meaning
                csts[ci] = St(st.kind, (st.meta[1], 0, st.meta[3:end]...), st.exs, st.blocks)
                edited = true
            else
                for (j, e) in enumerate(st.exs)
                    if e.kind !== :lit && e.kind !== :var
                        st.exs[j] = defaultex(e.sum)
                        edited = true
                        break
                    end
                end
            end
            edited || continue
            if check(cand)
                best = cand
                improved = true
                break
            end
        end
    end
    return best
end

"""
    differential_keep(fp; nstmts, interp) -> keep

The differential axis's property, as a predicate: re-run the source on both
sides, classify, and answer whether the finding with fingerprint `fp` survived.
This is the default `shrink` behaviour, expressed in the shared interface.
"""
differential_keep(fp::String; nstmts::Int, interp::Interpreter=RecursiveInterpreter()) =
    function (src::String)
        r = run_both(src; nstmts, interp)
        r === nothing && return false
        v = classify(r...)
        return isfinding(v) && fingerprint(v) == fp
    end

"""
    shrink(prog, fp; nstmts, maxattempts, interp, budget) -> Program

Greedily minimize `prog` while `run_both ∘ classify` keeps producing a finding
with fingerprint `fp`. `interp` selects which interpreter configuration the
finding was made under (mode-tagged findings must re-check in their own mode).

Thin wrapper over `shrink_ir` with `differential_keep` — kept because it is the
differential axis's entry point and reads better at the call sites.
"""
function shrink(prog::Program, fp::String; nstmts::Int, maxattempts::Int=400,
                interp::Interpreter=RecursiveInterpreter(),
                budget::ShrinkBudget=ShrinkBudget(; maxruns=maxattempts))
    return shrink_ir(prog, differential_keep(fp; nstmts, interp); budget)
end

# -- statement-level delta debugging on source text --------------------------
# The IR shrinker only works on programs the generator built. The corpus axis's
# findings are real Julia source, and a journal-recovered crash arrives as text
# with its IR long gone, so those need a shrinker that edits *parsed source*.
#
# This is `crashmin.jl`'s ddmin, lifted into the package, generalized over the
# same `keep(src)::Bool` interface and moved from line granularity to statement
# granularity — a multi-line `function` or `for` is one deletion candidate
# instead of a run of lines that only sometimes cuts on a statement boundary.
#
# Everything here lives inside functions on purpose. A `while` body at module
# toplevel is a *soft scope*, so `chunk ÷= 2` there would declare a new local
# and read it before assignment; that bug bit the generator's fuel counters and
# then bit crashmin's own ddmin loop (see NEXT.md's lessons).

"""
    toplevel_statements(src) -> Vector{Any} or nothing

Parse `src` and return its toplevel statements with `LineNumberNode`s dropped,
or `nothing` if it does not parse as a toplevel block.
"""
function toplevel_statements(src::AbstractString)
    ex = try
        Meta.parseall(String(src))
    catch
        return nothing
    end
    (ex isa Expr && ex.head === :toplevel) || return nothing
    return Any[a for a in ex.args if !(a isa LineNumberNode)]
end

rendersrc(stmts::Vector{Any}) = join((string(s) for s in stmts), "\n")

# Drop the `LineNumberNode`s inside block bodies: `string(ex)` prints them as
# `#= none:7 =#` comments, which is most of the noise in a reparsed fragment.
#
# Only `:block`/`:toplevel` args are filtered. A `:macrocall` carries its line
# node as a *required positional argument* that becomes the macro's `__source__`,
# so it is left alone rather than replaced — a corpus fragment is exactly the
# kind of code whose macros might read it.
function striplines!(@nospecialize(ex))
    ex isa Expr || return ex
    if ex.head === :block || ex.head === :toplevel
        filter!(a -> !(a isa LineNumberNode), ex.args)
    end
    for a in ex.args
        striplines!(a)
    end
    return ex
end

# Chunked deletion over a vector of statements: delete progressively smaller
# runs, keep any deletion the property survives, halve the run length when a
# full pass stops helping. Standard ddmin shape.
function ddmin_chunks(items::Vector{Any}, budget::ShrinkBudget, keep)
    best = items
    chunk = max(1, length(best) ÷ 2)
    while chunk >= 1 && !exhausted(budget)
        i = 1
        improved = false
        while i <= length(best) && !exhausted(budget)
            trial = vcat(best[1:i-1], best[min(i + chunk, length(best) + 1):end])
            if !isempty(trial) && attempt!(budget, keep, rendersrc(trial))
                best = trial
                improved = true
            else
                i += chunk
            end
        end
        improved || (chunk ÷= 2)
        chunk == 0 && break
    end
    return best
end

# Every (block, index) pair inside a statement forest, in a deterministic order,
# so an ordinal position addresses the same site in a deep copy.
function blocksites!(sites::Vector{Tuple{Expr,Int}}, @nospecialize(ex))
    ex isa Expr || return sites
    if ex.head === :block
        for i in eachindex(ex.args)
            ex.args[i] isa LineNumberNode && continue
            push!(sites, (ex, i))
        end
    end
    for a in ex.args
        blocksites!(sites, a)
    end
    return sites
end

function blocksites(stmts::Vector{Any})
    sites = Tuple{Expr,Int}[]
    for s in stmts
        blocksites!(sites, s)
    end
    return sites
end

# Second stage: remove statements from *inside* block bodies (function bodies,
# loop bodies, `let`s). Toplevel ddmin can only drop whole fragments; a real
# corpus fragment is usually one large `function` or `@testset`, and everything
# interesting is in its body.
function ddmin_inner(stmts::Vector{Any}, budget::ShrinkBudget, keep)
    best = stmts
    improved = true
    while improved && !exhausted(budget)
        improved = false
        n = length(blocksites(best))
        for pos in n:-1:1     # innermost/latest first
            exhausted(budget) && break
            cand = Any[deepcopy(s) for s in best]
            sites = blocksites(cand)
            pos <= length(sites) || continue
            blk, i = sites[pos]
            deleteat!(blk.args, i)
            if attempt!(budget, keep, rendersrc(cand))
                best = cand
                improved = true
                break     # the site list is stale after a removal
            end
        end
    end
    return best
end

"""
    ddmin_source(src, keep; budget, inner) -> String

Minimize source text at toplevel-statement granularity while `keep(src)` holds,
then (unless `inner=false`) recurse into block bodies.

Returns `src` unchanged if it does not parse, if the round trip through
`Meta.parseall`/`string` does not preserve the property, or if the property does
not hold to begin with — never a candidate the predicate rejected.
"""
function ddmin_source(src::AbstractString, keep; budget::ShrinkBudget=ShrinkBudget(),
                      inner::Bool=true)
    stmts = toplevel_statements(src)
    stmts === nothing && return String(src)
    # The reparsed-and-reprinted form is what every candidate is built from, so
    # it has to reproduce the finding before any of this means anything. Prefer
    # the line-stripped rendering (far more readable), but fall back to the
    # faithful one if dropping line info costs the property.
    stripped = Any[striplines!(deepcopy(s)) for s in stmts]
    best = if attempt!(budget, keep, rendersrc(stripped))
        stripped
    elseif attempt!(budget, keep, rendersrc(stmts))
        stmts
    else
        return String(src)
    end
    best = ddmin_chunks(best, budget, keep)
    inner && (best = ddmin_inner(best, budget, keep))
    return rendersrc(best)
end
