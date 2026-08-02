# Greedy IR-level shrinking with repair.
#
# Soundness comes from re-running the candidate after every edit and keeping it
# only if the finding's fingerprint is preserved. The repair pass therefore only
# needs to be *usually* valid: an edit that produces a program with a different
# failure is simply rejected.

# -- deep copy (IR nodes are immutable structs over mutable vectors) ---------
cloneex(e::Ex) = Ex(e.kind, e.sum, e.meta, Ex[cloneex(k) for k in e.kids])
clonest(s::St) = St(s.kind, s.meta, Ex[cloneex(e) for e in s.exs], [St[clonest(x) for x in b] for b in s.blocks])
cloneprog(p::Program) = Program(St[clonest(s) for s in p.pre], St[clonest(s) for s in p.fundefs],
                                St[clonest(s) for s in p.mid], St[clonest(s) for s in p.body])

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
        if st.kind === :push || st.kind === :setindex
            (st.meta::Symbol) in bound || return false
        elseif st.kind === :alias
            (st.meta[2]::Symbol) in bound || return false
        elseif st.kind === :setprop || st.kind === :amodify
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
    shrink(prog, fp; nstmts, maxattempts, interp) -> Program

Greedily minimize `prog` while `run_both ∘ classify` keeps producing a finding
with fingerprint `fp`. `interp` selects which interpreter configuration the
finding was made under (mode-tagged findings must re-check in their own mode).
"""
function shrink(prog::Program, fp::String; nstmts::Int, maxattempts::Int=400,
                interp::Interpreter=RecursiveInterpreter())
    check = function (cand::Program)
        r = run_both(render(cand); nstmts, interp)
        r === nothing && return false
        v = classify(r...)
        return isfinding(v) && fingerprint(v) == fp
    end
    best = cloneprog(prog)
    attempts = 0
    improved = true
    while improved && attempts < maxattempts
        improved = false
        # Pass 1: statement removal. `allsites` enumerates deterministically, so
        # ordinal position `pos` addresses the same statement in a clone.
        nsites = length(allsites(best))
        for pos in nsites:-1:1   # innermost/latest first: big prunes early
            attempts >= maxattempts && break
            cand = cloneprog(best)
            csites = allsites(cand)
            pos <= length(csites) || continue
            csts, ci = csites[pos]
            deleteat!(csts, ci)
            repair!(cand)
            attempts += 1
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
            attempts >= maxattempts && break
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
                csts[ci] = St(st.kind, (st.meta[1], 0), st.exs, st.blocks)
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
            attempts += 1
            if check(cand)
                best = cand
                improved = true
                break
            end
        end
    end
    return best
end
