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
#
# St node kinds:
#   :assign   meta = (name, sum, isnew)                     exs = [rhs]
#   :observe  meta = nothing                                exs = [ex]
#   :if       meta = haselse::Bool                          exs = [cond]  blocks = [then] or [then, else]
#   :for      meta = (ivar, n::Int)                         blocks = [body]
#   :while    meta = (fuelvar, fuel::Int)                   exs = [cond]  blocks = [body]
#   :fundef   meta = (name, params::Vector{Tuple{Symbol,TySum,Bool}}, retsum)  exs = [retex]  blocks = [body]
#   :recdef   meta = (name, accsum)                         exs = [stepex]      # fueled self-recursion template
#   :let      meta = bindings::Vector{Tuple{Symbol,TySum}}  exs = rhs per binding  blocks = [body]
#   :push     meta = vecname::Symbol                        exs = [val]
#   :setindex meta = vecname::Symbol                        exs = [idx, val]    # rendered guarded
#   :alias    meta = (newname, oldname, sum)
#   :try      meta = (excvar, hasfinally::Bool)             blocks = [body, handler] (+ [finally])

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
    fundefs::Vector{St}   # toplevel :fundef/:recdef statements
    body::Vector{St}      # rendered inside a toplevel `let`
end

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
defaultex(::AnyT) = lit(nothing, NothingT)

# All variable/function names a statement references (for cascade removal and
# repair during shrinking).
function refs!(out::Set{Symbol}, e::Ex)
    if e.kind === :var
        push!(out, e.meta::Symbol)
    elseif e.kind === :call || e.kind === :callvar
        push!(out, e.meta::Symbol)
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
    return Symbol[]
end
