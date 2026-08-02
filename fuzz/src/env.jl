# Generation context: the environment model is the spine of the generator.
# Every rule draws candidates from it (in-scope variables by summary, defined
# functions by signature) and pushes its effects back into it (new bindings,
# captures, new methods).

using Random: Xoshiro, AbstractRNG

mutable struct VInfo
    name::Symbol
    sum::TySum
    isglobal::Bool
    isconst::Bool   # `const` global: never a reassignment target
end
VInfo(name::Symbol, sum::TySum) = VInfo(name, sum, false, false)
VInfo(name::Symbol, sum::TySum, isglobal::Bool) = VInfo(name, sum, isglobal, false)

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
    maxblockstmts::Int = 3     # max statements inside if/for/while/let/try blocks
    minblockstmts::Int = 1     # min statements inside a block
    maxblockdepth::Int = 3     # control-flow nesting cap (was a hard-coded 2)
    blockdecay::Float64 = 0.6  # control-flow weight is scaled by blockdecay^depth,
                               # so deep nesting is reachable but rare (keeps program
                               # size and abort rate bounded as the cap rises)
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
    loopdepth::Int                  # enclosing for/while loops (break/continue legality)
    retsum::Union{Nothing,TySum}    # current function's return summary (nothing at toplevel);
                                    # gates `return` statements and fixes their value summary
end

Ctx(rng::AbstractRNG, cfg::Cfg=Cfg()) =
    Ctx(rng, cfg, [VInfo[]], FnInfo[], StructT[], cfg.maxdepth, 0, false, 0, nothing)

# Is generation currently inside a local (non-module) scope? Determines
# whether writing to a module global needs the `global` keyword.
inlocal(ctx::Ctx) = length(ctx.scopes) > 1 || ctx.infunc

# Run `f()` with every variable matching `hide` predicate temporarily removed
# from scope, so the generated sub-expression cannot reference them.
function without(f, ctx::Ctx, hide)
    saved = [copy(sc) for sc in ctx.scopes]
    for sc in ctx.scopes
        filter!(v -> !hide(v), sc)
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

# Hide function-typed vars: a closure built in an FnT reassignment rhs must not
# reach any reassignable function variable, or two closures could tie a call
# cycle (f = () -> g(); g = () -> f()) — unbounded recursion.
withoutfns(f, ctx::Ctx) = without(f, ctx, v -> v.sum isa FnT)

# A binding whose value can grow under concatenation/append: String, Vector,
# or Any (which may hold either).
growablevar(v::VInfo) = (v.sum isa ConcT && (v.sum::ConcT).t === :Str) ||
                        v.sum isa VecT || v.sum isa AnyT

# Hide growable-typed vars: the rhs of a reassignment to a growable variable
# must not reference ANY growable variable. That breaks multiplicative feedback
# — direct (g = string(g, g)) and cross-referential (g = f(h); h = f(g)) alike —
# so growable bindings stay bounded by fixed computations regardless of how many
# times the reassignment runs. Prevents exponential-memory OOM of the (bounded-
# step but unbounded-memory) reference side.
withoutgrowables(f, ctx::Ctx) = without(f, ctx, growablevar)

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
