# The program IR.
#
# Two uniform node types (Ex for expressions, St for statements) rather than a
# struct per construct: the shrinker and the repair pass walk these trees
# generically, and adding a construct means adding a `kind` plus a rule and a
# render case — the walkers don't change.
#
# Ex node kinds and their payloads:
#   :lit      meta = literal value                          kids = []
#   :var      meta = name::Symbol                           kids = []
#   :binop    meta = op::Symbol (infix)                     kids = [a, b]
#   :prefix   meta = op::Symbol (e.g. :!, :-)               kids = [a]
#   :callb    meta = fname::Symbol (Base function)          kids = args
#   :isa      meta = typename::String                       kids = [a]
#   :andor    meta = :&& | :||                              kids = [a, b]
#   :ternary  meta = nothing                                kids = [cond, a, b]
#   :tuple    meta = nothing                                kids = elts
#   :vect     meta = nothing                                kids = elts
#   :index    meta = nothing                                kids = [coll, i]   (rendered guarded unless meta === :unguarded)
#   :call     meta = fname::Symbol (generated function)     kids = args
#   :callvar  meta = name::Symbol (FnT-typed variable)      kids = args
#   :closure  meta = params::Vector{Symbol}                 kids = [bodyex]
#   :closuremut meta = (params::Vector{Symbol}, cap::Symbol) kids = [updateex, retex]
#   :guard    meta = nothing                                kids = [inner]  # try/catch wrapper
#   :src      meta = verbatim source::String                kids = []   # builtin-table literal args
#   :splat    meta = nothing                                kids = [inner]  # renders (inner)... inside calls
#   :prop     meta = fieldname::Symbol                      kids = [obj]    # (obj).field
#   :aprop    meta = fieldname::Symbol                      kids = [obj]    # (@atomic (obj).field)
#   :compr    meta = (ivar, n::Int, hasfilter::Bool)        kids = [bodyex] or [bodyex, cond]
#   :kwcall   meta = (fname::Symbol, kwnames::Vector{Symbol}) kids = positional args, then kwarg values
#
# St node kinds:
#   :assign   meta = (name, sum, isnew, needsglobal::Bool[, decl::Symbol])  exs = [rhs]
#             decl (globals only): :const | :Int64/:Float64 (typed global) | :none
#   :observe  meta = nothing                                exs = [ex]
#   :if       meta = haselse::Bool                          exs = [cond]  blocks = [then] or [then, else]
#   :for      meta = (ivar, n::Int)                         blocks = [body]
#   :while    meta = (fuelvar, fuel::Int[, attoplevel::Bool])  exs = [cond]  blocks = [body]
#             attoplevel renders the fuel decrement as `global fv -= 1`: at module
#             toplevel the body is a soft scope, where a bare decrement would
#             declare a new local and throw UndefVarError instead of counting down
#   :fundef   meta = (name, params, retsum[, kwparams, vararg::Bool])  exs = [retex]  blocks = [body]
#             params::Vector{Tuple{Symbol,TySum,Bool}} (name, sum, typed);
#             kwparams::Vector{Tuple{Symbol,Any}} (name, literal default value)
#   :structdef meta = StructT                               (fields with `typed` = fieldsums[i] isa ConcT)
#   :setprop  meta = (varname, fieldname[, atomic::Bool])   exs = [val]   # mutable struct field write
#   :amodify  meta = (varname, fieldname, op::Symbol)       exs = [rhs]   # @atomic v.f op= rhs (modifyfield! path)
#   :recdef   meta = (name, accsum)                         exs = [stepex]      # fueled self-recursion template
#   :let      meta = bindings::Vector{Tuple{Symbol,TySum}}  exs = rhs per binding  blocks = [body]
#   :push     meta = vecname::Symbol                        exs = [val]
#   :setindex meta = vecname::Symbol                        exs = [idx, val]    # rendered guarded
#   :alias    meta = (newname, oldname, sum)                # sum: VecT or mutable StructT
#   :try      meta = (excvar, hasfinally::Bool[, haselse::Bool])
#             blocks = [body, handler] (+ [else] if haselse) (+ [finally] if hasfinally)
#   :brk      meta = nothing                                exs = [cond]  # (cond) && break
#   :cont     meta = nothing                                exs = [cond]  # (cond) && continue
#   :ret      meta = nothing                                exs = [cond, val]  # (cond) && return val
#   :rethrowif meta = nothing                               exs = [cond]  # (cond) && rethrow(); catch handlers only
#   :maybeundef meta = name::Symbol                         exs = [cond, rhs]
#             if cond; name = rhs; end + observes @isdefined(name) and a guarded read
#   :loopundef meta = (ivar, xname, n::Int, when::Int)      exs = [rhs]
#             for ivar in 1:n — observes xname's (un)definedness at iteration `when`,
#             then assigns it; probes per-iteration slot reset (NewvarNode)
#   :typedlocal meta = (name, sum::TySum)                   exs = [rhs]   # local name::T = rhs

struct Ex
    kind::Symbol
    sum::TySum
    meta::Any
    kids::Vector{Ex}
end
Ex(kind::Symbol, sum::TySum, meta=nothing) = Ex(kind, sum, meta, Ex[])

struct St
    kind::Symbol
    meta::Any
    exs::Vector{Ex}
    blocks::Vector{Vector{St}}
end
St(kind::Symbol, meta=nothing; exs=Ex[], blocks=Vector{St}[]) = St(kind, meta, exs, blocks)

struct Program
    pre::Vector{St}       # module globals + struct definitions
    fundefs::Vector{St}   # toplevel :fundef/:recdef statements
    mid::Vector{St}       # extra toplevel statements (toplevel-frame surface)
    body::Vector{St}      # rendered inside a toplevel `let`
end
Program(fundefs::Vector{St}, body::Vector{St}) = Program(St[], fundefs, St[], body)
sections(p::Program) = (p.pre, p.fundefs, p.mid, p.body)

lit(v, sum::TySum) = Ex(:lit, sum, v)

# Default literal of a given summary — used by shrinking/repair to replace
# removed bindings and pruned subtrees with something inert of the same shape.
defaultex(s::ConcT) =
    s.t === :Int ? lit(0, s) :
    s.t === :Float ? lit(0.0, s) :
    s.t === :Bool ? lit(false, s) :
    s.t === :Str ? lit("", s) :
    s.t === :Sym ? lit(:a, s) : lit(nothing, s)
defaultex(s::VecT) = Ex(:vect, s, nothing, [defaultex(s.elt)])
defaultex(s::TupT) = Ex(:tuple, s, nothing, [defaultex(e) for e in s.elts])
defaultex(s::FnT) = Ex(:closure, s, [Symbol("__p", i) for i in 1:arity(s)], [defaultex(s.ret isa AnyT ? NothingT : s.ret)])
# `nothing`, not a construction: shrinking may have removed the struct definition.
defaultex(::StructT) = lit(nothing, NothingT)
defaultex(::AnyT) = lit(nothing, NothingT)

# All variable/function names a statement references (for cascade removal and
# repair during shrinking).
function refs!(out::Set{Symbol}, e::Ex)
    if e.kind === :var
        push!(out, e.meta::Symbol)
    elseif e.kind === :call || e.kind === :callvar
        push!(out, e.meta::Symbol)
    elseif e.kind === :kwcall
        push!(out, (e.meta[1])::Symbol)
    elseif e.kind === :closuremut
        push!(out, (e.meta[2])::Symbol)
    end
    for k in e.kids
        refs!(out, k)
    end
    return out
end

function refs!(out::Set{Symbol}, st::St)
    if st.kind === :push || st.kind === :setindex
        push!(out, st.meta::Symbol)
    elseif st.kind === :alias
        push!(out, st.meta[2]::Symbol)
    elseif st.kind === :setprop || st.kind === :amodify
        push!(out, st.meta[1]::Symbol)
    end
    for e in st.exs
        refs!(out, e)
    end
    for b in st.blocks, s in b
        refs!(out, s)
    end
    return out
end

# Names a statement *binds* for following statements in the same block.
function binds(st::St)
    st.kind === :assign && (st.meta[3]::Bool) && return Symbol[st.meta[1]]
    st.kind === :alias && return Symbol[st.meta[1]]
    (st.kind === :fundef || st.kind === :recdef) && return Symbol[st.meta[1]]
    st.kind === :structdef && return Symbol[(st.meta::StructT).name]
    st.kind === :typedlocal && return Symbol[st.meta[1]]
    st.kind === :maybeundef && return Symbol[st.meta::Symbol]
    st.kind === :loopundef && return Symbol[st.meta[1], st.meta[2]]
    return Symbol[]
end
