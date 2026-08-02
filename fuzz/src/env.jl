# Generation context: the environment model is the spine of the generator.
# Every rule draws candidates from it (in-scope variables by summary, defined
# functions by signature) and pushes its effects back into it (new bindings,
# captures, new methods).

using Random: Xoshiro, AbstractRNG

mutable struct VInfo
    name::Symbol
    sum::TySum
end

mutable struct FnInfo
    name::Symbol
    sigs::Vector{Vector{TySum}}  # one entry per method (positional sums)
    ret::TySum                   # join over methods
end

Base.@kwdef struct Cfg
    maxdepth::Int = 4          # expression nesting
    nfundefs::UnitRange{Int} = 0:3
    nbodystmts::UnitRange{Int} = 5:14
    maxblockstmts::Int = 5     # statements inside if/for/while/let/try blocks
    maxloop::Int = 4           # for-loop trip count / while fuel
    maxstring::Int = 6         # literal string length
end

mutable struct Ctx
    rng::AbstractRNG
    cfg::Cfg
    scopes::Vector{Vector{VInfo}}   # innermost last; closure bodies see all (capture)
    fns::Vector{FnInfo}
    depth::Int                      # remaining expression depth
    namecounter::Int
    infunc::Bool                    # generating inside a function/closure body
end

Ctx(rng::AbstractRNG, cfg::Cfg=Cfg()) = Ctx(rng, cfg, [VInfo[]], FnInfo[], cfg.maxdepth, 0, false)

freshname(ctx::Ctx, prefix::String) = Symbol(prefix, ctx.namecounter += 1)

pushscope!(ctx::Ctx) = push!(ctx.scopes, VInfo[])
popscope!(ctx::Ctx) = pop!(ctx.scopes)
declare!(ctx::Ctx, v::VInfo) = push!(ctx.scopes[end], v)

function visiblevars(ctx::Ctx)
    out = VInfo[]
    for sc in ctx.scopes, v in sc
        push!(out, v)
    end
    return out
end

varsof(ctx::Ctx, want::TySum) = [v for v in visiblevars(ctx) if compat(want, v.sum)]

# Variables whose summary *equals* `want` — safe targets for reassignment
# (assigning a Float into a var the generator believes is Int would invalidate
# every later use site).
varseq(ctx::Ctx, want::TySum) = [v for v in visiblevars(ctx) if compat_eq(want, v.sum)]

fnsreturning(ctx::Ctx, want::TySum) = [f for f in ctx.fns if compat(want, f.ret)]

pick(rng::AbstractRNG, xs) = xs[rand(rng, 1:length(xs))]

# Weighted pick over (weight, item) pairs.
function wpick(rng::AbstractRNG, pairs)
    tot = sum(first(p) for p in pairs)
    r = rand(rng) * tot
    acc = 0.0
    for (w, x) in pairs
        acc += w
        r <= acc && return x
    end
    return last(pairs)[2]
end
