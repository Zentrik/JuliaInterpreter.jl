# Generation context: the environment model is the spine of the generator.
# Every rule draws candidates from it (in-scope variables by summary, defined
# functions by signature) and pushes its effects back into it (new bindings,
# captures, new methods).

using Random: Xoshiro, AbstractRNG

mutable struct VInfo
    name::Symbol
    sum::TySum
    isglobal::Bool
end
VInfo(name::Symbol, sum::TySum) = VInfo(name, sum, false)

mutable struct FnInfo
    name::Symbol
    sigs::Vector{Vector{TySum}}  # one entry per method (positional sums)
    ret::TySum                   # join over methods
    kwnames::Vector{Symbol}      # optional keyword params (callers may pass any subset)
    vararg::Bool                 # last method accepts trailing args
end
FnInfo(name::Symbol, sigs, ret::TySum) = FnInfo(name, sigs, ret, Symbol[], false)

Base.@kwdef struct Cfg
    maxdepth::Int = 4          # expression nesting
    nglobals::UnitRange{Int} = 0:3
    nstructs::UnitRange{Int} = 0:2
    nfundefs::UnitRange{Int} = 0:3
    nmidstmts::UnitRange{Int} = 0:3   # extra bare-toplevel statements
    nbodystmts::UnitRange{Int} = 5:14
    maxblockstmts::Int = 5     # statements inside if/for/while/let/try blocks
    maxloop::Int = 4           # for-loop trip count / while fuel
    maxstring::Int = 6         # literal string length
end

mutable struct Ctx
    rng::AbstractRNG
    cfg::Cfg
    scopes::Vector{Vector{VInfo}}   # scopes[1] is module-global; closure bodies see all (capture)
    fns::Vector{FnInfo}
    structs::Vector{StructT}
    depth::Int                      # remaining expression depth
    namecounter::Int
    infunc::Bool                    # generating inside a function/closure body
end

Ctx(rng::AbstractRNG, cfg::Cfg=Cfg()) = Ctx(rng, cfg, [VInfo[]], FnInfo[], StructT[], cfg.maxdepth, 0, false)

# Is generation currently inside a local (non-module) scope? Determines
# whether writing to a module global needs the `global` keyword.
inlocal(ctx::Ctx) = length(ctx.scopes) > 1 || ctx.infunc

# Run `f()` with every FnT-summarized variable hidden. Used when generating
# the rhs of a reassignment to an FnT variable: a closure built there must not
# be able to reach any reassignable function variable, or reassignment could
# tie a call cycle (f = () -> g(); g = () -> f()) — unbounded recursion that
# breaks termination-by-construction.
function withoutfns(f, ctx::Ctx)
    saved = [copy(sc) for sc in ctx.scopes]
    for sc in ctx.scopes
        filter!(v -> !(v.sum isa FnT), sc)
    end
    try
        return f()
    finally
        for (sc, sv) in zip(ctx.scopes, saved)
            empty!(sc)
            append!(sc, sv)
        end
    end
end

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

# Struct types with at least one field whose summary satisfies `want` (so a
# field read can produce a `want` value).
structswithfield(ctx::Ctx, want::TySum) =
    [s for s in ctx.structs if any(fs -> compat(want, fs), s.fieldsums)]

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
