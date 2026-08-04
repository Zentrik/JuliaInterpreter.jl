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
    kwnames::Vector{Symbol}      # keyword params — first method only (see :kwcall)
    varargs::Vector{Bool}        # per *method*: does this signature accept trailing args?
end
FnInfo(name::Symbol, sigs, ret::TySum) =
    FnInfo(name, sigs, ret, Symbol[], fill(false, length(sigs)))
FnInfo(name::Symbol, sigs, ret::TySum, kwnames::Vector{Symbol}, vararg::Bool) =
    FnInfo(name, sigs, ret, kwnames, fill(vararg, length(sigs)))

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
    swarm::Bool = true         # per-program random feature-subset masking
    policy::Bool = true        # per-program generation-policy weight skew
end

# --- swarm testing + generation policies -----------------------------------
#
# Two ways to stop diluting the interesting rules, both per program.
#
# Swarm (Groce et al., ISSTA 2012): each program disables a random subset of
# optional features instead of enabling everything. Some bugs need feature X
# and are *suppressed* by feature Y also being present — with everything always
# on, those bugs are unreachable no matter how many programs you draw. Turning
# features off also concentrates the remaining budget: a program with only 6 of
# 14 rule families available emits each of them far more often than one
# choosing among all 14.
#
# Policies (YARPGen, OOPSLA 2020): skew the weight distribution toward one
# subsystem per program, so a construct that is ~1% of statements under uniform
# weights becomes common in the programs that target it. Cheap to add, and
# retargetable when a subsystem saturates.

# Rule families a program may switch off. Deliberately excludes :assignnew and
# :observe (a program with neither generates nothing and compares nothing).
const SWARMABLE = (:if, :for, :while, :let, :try, :push, :setindex, :alias, :setprop,
                   :amodify, :compr, :maybeundef, :loopundef, :typedlocal, :brk, :cont,
                   :ret, :reassign,
                   # determinism unlocks (determinism.md §3/§4): explicit-RNG draws,
                   # content-keyed Dict/Set, and the virtual clock, each maskable so
                   # a program that targets them isn't diluted by everything else.
                   :rng, :dict, :vtime)

const POLICIES = (
    :uniform,    # no skew — keeps the historical distribution in the mix
    :exceptions, # try/catch/finally, rethrow, exits crossing a try boundary
    :dispatch,   # multi-method calls, wrong-typed calls, kwargs, closures
    :builtins,   # the intrinsics/builtins probe dictionary and atomics
    :toplevel,   # bare-toplevel statements, globals, undefined-variable probes
    :mutation,   # vectors, structs, aliasing, field and atomic writes
    :determinism,# explicit-RNG draws, content-keyed Dict/Set, virtual clock
)

# Weight multipliers per (policy, rule). Missing entries default to 1.0.
const POLICY_BOOST = Dict{Symbol,Dict{Symbol,Float64}}(
    :uniform    => Dict{Symbol,Float64}(),
    :exceptions => Dict(:try => 6.0, :brk => 3.0, :cont => 3.0, :ret => 3.0,
                        :for => 2.0, :while => 2.0, :guardix => 2.0, :guarddiv => 2.0,
                        :badcall => 2.0),
    :dispatch   => Dict(:callfn => 4.0, :kwcall => 4.0, :badcall => 4.0, :callvar => 3.0,
                        :closure => 3.0),
    :builtins   => Dict(:builtin => 8.0, :amodify => 4.0, :setprop => 2.0),
    :toplevel   => Dict(:maybeundef => 4.0, :loopundef => 4.0, :typedlocal => 3.0,
                        :reassign => 2.0),
    :mutation   => Dict(:push => 3.0, :setindex => 3.0, :alias => 4.0, :setprop => 3.0,
                        :amodify => 3.0, :compr => 2.0),
    # RNG draws (int/float/bool), the vtime clock, and every Dict/Set rule
    # (construction, get/get!/haskey/in/length, setindex/delete/push, keys/values
    # observations). Boosting the rule weights alone is not enough for Dict/Set —
    # every op needs a container in scope — so :determinism also raises the rate
    # of *creating* one (see newvarsum).
    :determinism => Dict(:rngint => 6.0, :rngfloat => 5.0, :rngbool => 5.0, :vtime => 5.0,
                         :dictget => 4.0, :dictlen => 3.0, :haskey => 3.0, :setin => 3.0,
                         :dictset => 4.0, :dictdel => 3.0, :setpush => 3.0, :dictobs => 4.0,
                         :for => 2.0),
)

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
    enabled::Set{Symbol}            # swarm: rule families this program may use
    policy::Symbol                  # generation policy skewing the weights
    rtscopes::Int                   # enclosing constructs that introduce a *runtime* scope
                                    # (for/while/let/try bodies) — `if` does not count
    rngseed::Int                    # literal seed for the inline-PRNG header (`const __LCG__ =
                                    # Ref{UInt64}(seed)` + helpers, render.jl `rngheader`);
                                    # emitted only when the `:rng` feature is on (rngavail)
end

function Ctx(rng::AbstractRNG, cfg::Cfg=Cfg())
    # Draw the swarm mask and policy first, so they are part of the choice
    # sequence and shrink like everything else.
    enabled = Set{Symbol}()
    for r in SWARMABLE
        # Each feature is kept with p=0.7: enough off per program to get real
        # configuration diversity, few enough that programs stay expressive.
        (!cfg.swarm || rand(rng) < 0.7) && push!(enabled, r)
    end
    policy = cfg.policy ? pick(rng, POLICIES) : :uniform
    # Drawn unconditionally (so the choice sequence is stable whether or not the
    # `:rng` feature is on); used only when `rngavail` is true. A small positive
    # literal keeps repros readable.
    rngseed = rand(rng, 1:1_000_000_000)
    return Ctx(rng, cfg, [VInfo[]], FnInfo[], StructT[], cfg.maxdepth, 0, false, 0, nothing,
               enabled, policy, 0, rngseed)
end

# Swarm gate: is this rule family available in the program being generated?
# Rules not in SWARMABLE are always on.
swarmon(ctx::Ctx, rule::Symbol) = !ctx.cfg.swarm || rule in ctx.enabled || !(rule in SWARMABLE)

# Is the explicit-RNG feature available? Gates both the inline-PRNG header
# (render.jl, via Program.rngseed) and every rand-drawing rule.
rngavail(ctx::Ctx) = swarmon(ctx, :rng)

# Apply the program's policy to a (weight, rule) menu, dropping swarm-disabled
# rules. Every weighted choice over rule names goes through here.
function policyweights(ctx::Ctx, opts::Vector{Tuple{Float64,Symbol}})
    boost = POLICY_BOOST[ctx.policy]
    out = Tuple{Float64,Symbol}[]
    for (w, r) in opts
        swarmon(ctx, r) || continue
        push!(out, (w * get(boost, r, 1.0), r))
    end
    # Never hand back an empty menu: fall back to the unfiltered options.
    return isempty(out) ? opts : out
end

# Weighted pick over rule options, with swarm masking and policy skew applied.
wpickrule(ctx::Ctx, opts::Vector{Tuple{Float64,Symbol}}) =
    wpick(ctx.rng, policyweights(ctx, opts))

# Is generation currently inside a local (non-module) scope? Determines
# whether writing to a module global needs the `global` keyword.
#
# NOTE this counts *generation* scopes, which `genblock` pushes for every block
# including `if`. That is right for name visibility — a binding made inside an
# `if` should not be referenced after it — but wrong for scoping questions,
# because `if` introduces no runtime scope at all. Use `inruntimelocal` for
# those; see its comment.
inlocal(ctx::Ctx) = length(ctx.scopes) > 1 || ctx.infunc

# Is generation inside a construct that introduces a *runtime* scope? Only
# `for`/`while`/`let`/`try` bodies and function bodies do; `if` and `begin` are
# transparent, so a binding created inside a toplevel `if` is a module global.
#
# This distinction decides whether an assignment at this point lands in a global
# or a local, which in turn decides whether a nested loop body — a soft scope at
# toplevel — needs `global` to write it. Getting it wrong makes the loop's write
# silently declare a fresh local and read it before assignment.
inruntimelocal(ctx::Ctx) = ctx.rtscopes > 0 || ctx.infunc

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
# A binding created where no runtime-local scope is open is a module global,
# whatever generation scope it happens to sit in: `if` and `begin` are
# transparent, so `x = 1` inside a toplevel `if` defines a global. Recording
# that is what lets later writes from inside a loop body — a soft scope at
# toplevel — render the `global` keyword they need.
function declare!(ctx::Ctx, v::VInfo)
    v.isglobal |= !inruntimelocal(ctx)
    push!(ctx.scopes[end], v)
end

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
