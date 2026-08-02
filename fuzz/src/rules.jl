# The rule registry: wave-1 grammar plus the closure rules.
#
# Expression rules are grouped by the summary they can produce; statement rules
# carry an applicability predicate over the context. Generation is
# environment-directed throughout: rules only reference bindings the context
# proves are in scope, so every generated program is valid by construction.
# Shrinking re-checks the finding after each edit, so repair (shrink.jl) only
# has to be usually-valid, not provably so.

# ---------------------------------------------------------------------------
# Expressions

function genex(ctx::Ctx, want::TySum)::Ex
    if ctx.depth <= 0
        return genleaf(ctx, want)
    end
    ctx.depth -= 1
    ex = try
        genex_inner(ctx, want)
    finally
        ctx.depth += 1
    end
    return ex
end

function genleaf(ctx::Ctx, want::TySum)::Ex
    vs = varsof(ctx, want)
    if !isempty(vs) && rand(ctx.rng) < 0.6
        v = pick(ctx.rng, vs)
        return Ex(:var, v.sum, v.name)
    end
    return genlit(ctx, want)
end

function genlit(ctx::Ctx, want::TySum)::Ex
    rng = ctx.rng
    if want isa ConcT
        want.t === :Int && return lit(wpick(rng, [
            (5.0, rand(rng, -10:10)),
            (1.0, rand(rng, -1000:1000)),
            (0.3, pick(rng, Any[typemax(Int), typemin(Int), typemax(Int) - 1, -1, 0, 1])),
        ]), want)
        want.t === :Float && return lit(wpick(rng, [
            (5.0, round(rand(rng) * 20 - 10; digits=2)),
            (1.0, pick(rng, Any[0.0, -0.0, 1.5, -2.5, 0.1])),
            (0.4, pick(rng, Any[NaN, Inf, -Inf, floatmax(Float64), floatmin(Float64), eps(Float64)])),
        ]), want)
        want.t === :Bool && return lit(rand(rng, Bool), want)
        want.t === :Str && return lit(randstring_src(ctx), want)
        want.t === :Sym && return lit(pick(rng, [:a, :b, :c, :d, :e]), want)
        want.t === :Nothing && return lit(nothing, want)
    elseif want isa TupT
        return Ex(:tuple, want, nothing, [genleaf(ctx, e) for e in want.elts])
    elseif want isa VecT
        return Ex(:vect, want, nothing, [genleaf(ctx, want.elt) for _ in 1:rand(ctx.rng, 1:3)])
    elseif want isa FnT
        return genclosure(ctx, want)
    end
    # AnyT leaf: any concrete literal
    return genlit(ctx, pick(ctx.rng, TySum[IntT, FloatT, BoolT, StrT, SymT, NothingT]))
end

function randstring_src(ctx::Ctx)
    n = rand(ctx.rng, 0:ctx.cfg.maxstring)
    alphabet = ['a', 'b', 'x', 'y', '0', '1', ' ', '!', 'α', 'β', '∀', '🐛']
    return String([pick(ctx.rng, alphabet) for _ in 1:n])
end

function genex_inner(ctx::Ctx, want::TySum)::Ex
    rng = ctx.rng
    opts = Tuple{Float64,Symbol}[]
    if want isa ConcT && (want.t === :Int || want.t === :Float)
        push!(opts, (3.0, :leaf), (3.0, :arith), (1.0, :ternary), (0.8, :minmax), (0.8, :vecget))
        want.t === :Int && push!(opts, (0.8, :veclen), (0.6, :strlen), (0.6, :intdiv))
    elseif want isa ConcT && want.t === :Bool
        push!(opts, (2.0, :leaf), (3.0, :cmp), (1.5, :andor), (1.0, :not), (0.8, :isa), (0.6, :egal), (0.6, :ternary))
    elseif want isa ConcT && want.t === :Str
        push!(opts, (3.0, :leaf), (2.0, :strcat), (0.8, :ternary))
    elseif want isa ConcT
        push!(opts, (1.0, :leaf))
    elseif want isa TupT || want isa VecT
        push!(opts, (1.0, :leaf))
    elseif want isa FnT
        push!(opts, (1.0, :closure))
    else # AnyT
        push!(opts, (2.0, :leaf), (1.5, :guardix), (1.0, :callvar), (0.8, :guarddiv), (0.6, :ternary))
    end
    # Calls into generated functions, for any want their return satisfies:
    if !isempty(fnsreturning(ctx, want))
        push!(opts, (2.0, :callfn))
    end
    kind = wpick(rng, opts)

    if kind === :leaf
        return genleaf(ctx, want)
    elseif kind === :arith
        op = want == IntT ? pick(rng, [:+, :-, :*]) : pick(rng, [:+, :-, :*, :/])
        return Ex(:binop, want, op, [genex(ctx, want), genex(ctx, want)])
    elseif kind === :intdiv  # unguarded, denominator a nonzero literal
        op = pick(rng, [:÷, :%])
        d = pick(rng, [1, 2, 3, 7, -1, -3])
        return Ex(:binop, IntT, op, [genex(ctx, IntT), lit(d, IntT)])
    elseif kind === :minmax
        f = pick(rng, [:min, :max, :abs])
        kids = f === :abs ? [genex(ctx, want)] : [genex(ctx, want), genex(ctx, want)]
        return Ex(:callb, want, f, kids)
    elseif kind === :vecget   # get(v, i, default) — total, keeps the summary
        vs = varsof(ctx, VecT(want))
        isempty(vs) && return genleaf(ctx, want)
        v = pick(rng, vs)
        return Ex(:callb, want, :get, [Ex(:var, v.sum, v.name), genex(ctx, IntT), genex(ctx, want)])
    elseif kind === :veclen || kind === :strlen
        eltsum = kind === :veclen ? pick(rng, TySum[IntT, FloatT, AnyT()]) : nothing
        vs = kind === :veclen ? varsof(ctx, VecT(eltsum)) : varsof(ctx, StrT)
        isempty(vs) && return genleaf(ctx, want)
        v = pick(rng, vs)
        return Ex(:callb, IntT, :length, [Ex(:var, v.sum, v.name)])
    elseif kind === :cmp
        s = pick(rng, TySum[IntT, FloatT, StrT])
        op = s == StrT ? pick(rng, [:(==), :(!=), :<]) : pick(rng, [:(==), :(!=), :<, :<=, :>, :>=])
        return Ex(:binop, BoolT, op, [genex(ctx, s), genex(ctx, s)])
    elseif kind === :egal
        s = pick(rng, TySum[IntT, FloatT, SymT, StrT])
        return Ex(:binop, BoolT, :(===), [genex(ctx, s), genex(ctx, s)])
    elseif kind === :andor
        return Ex(:andor, BoolT, pick(rng, [:&&, :||]), [genex(ctx, BoolT), genex(ctx, BoolT)])
    elseif kind === :not
        return Ex(:prefix, BoolT, :!, [genex(ctx, BoolT)])
    elseif kind === :isa
        tn = pick(rng, ["Int64", "Float64", "Bool", "String", "Number", "Integer", "AbstractString", "Any"])
        s = pick(rng, TySum[IntT, FloatT, BoolT, StrT, AnyT()])
        return Ex(:isa, BoolT, tn, [genex(ctx, s)])
    elseif kind === :ternary
        return Ex(:ternary, want, nothing, [genex(ctx, BoolT), genex(ctx, want), genex(ctx, want)])
    elseif kind === :strcat
        n = rand(rng, 2:3)
        args = Ex[genex(ctx, pick(rng, TySum[StrT, StrT, IntT, BoolT, SymT])) for _ in 1:n]
        return Ex(:callb, StrT, :string, args)
    elseif kind === :guardix  # guarded indexing — result is Any (value or (:__thrown, name))
        vs = vcat(varsof(ctx, VecT(IntT)), varsof(ctx, VecT(FloatT)), varsof(ctx, VecT(AnyT())), varsof(ctx, StrT))
        isempty(vs) && return genleaf(ctx, want)
        v = pick(rng, vs)
        inner = Ex(:index, AnyT(), nothing, [Ex(:var, v.sum, v.name), genex(ctx, IntT)])
        return Ex(:guard, AnyT(), nothing, [inner])
    elseif kind === :guarddiv # guarded ÷/% with arbitrary denominator (DivideError probe)
        op = pick(rng, [:÷, :%])
        inner = Ex(:binop, IntT, op, [genex(ctx, IntT), genex(ctx, IntT)])
        return Ex(:guard, AnyT(), nothing, [inner])
    elseif kind === :callvar
        vs = [v for v in visiblevars(ctx) if v.sum isa FnT]
        isempty(vs) && return genleaf(ctx, want)
        v = pick(rng, vs)
        fs = v.sum::FnT
        args = Ex[genex(ctx, p isa AnyT ? pick(rng, TySum[IntT, FloatT, StrT, BoolT]) : p) for p in fs.psums]
        return Ex(:callvar, fs.ret, v.name, args)
    elseif kind === :callfn
        f = pick(rng, fnsreturning(ctx, want))
        sig = pick(rng, f.sigs)
        args = Ex[genex(ctx, p isa AnyT ? pick(rng, TySum[IntT, FloatT, StrT, BoolT]) : p) for p in sig]
        return Ex(:call, f.ret, f.name, args)
    elseif kind === :closure
        return genclosure(ctx, want isa FnT ? want : FnT(TySum[IntT], AnyT()))
    end
    return genleaf(ctx, want)
end

# Closures: the acceptance-test rule for the environment model. The body is
# generated with the enclosing scopes visible (capture), plus a params scope.
# The mutating variant reassigns a captured numeric variable — that forces the
# variable into a Box, one of the interpreter's trickier paths.
function genclosure(ctx::Ctx, want::FnT)::Ex
    rng = ctx.rng
    params = [freshname(ctx, "p") for _ in want.psums]
    caps = [v for v in visiblevars(ctx) if isnumeric(v.sum)]
    if !isempty(caps) && !isempty(want.psums) && rand(rng) < 0.35
        # (p, ...) -> (cap = cap <op> p′; cap)   where p′ is a param of cap's summary
        cap = pick(rng, caps)
        pushscope!(ctx)
        for (p, s) in zip(params, want.psums)
            declare!(ctx, VInfo(p, s))
        end
        # the update must keep cap's summary: mix cap with an expression of the same summary
        upd = Ex(:binop, cap.sum, cap.sum == IntT ? pick(rng, [:+, :-, :*]) : pick(rng, [:+, :*]),
                 [Ex(:var, cap.sum, cap.name), genex(ctx, cap.sum)])
        popscope!(ctx)
        retex = Ex(:var, cap.sum, cap.name)
        return Ex(:closuremut, FnT(want.psums, cap.sum), (params, cap.name), [upd, retex])
    end
    pushscope!(ctx)
    for (p, s) in zip(params, want.psums)
        declare!(ctx, VInfo(p, s isa AnyT ? AnyT() : s))
    end
    retsum = want.ret isa AnyT ? pick(rng, TySum[IntT, FloatT, BoolT, StrT]) : want.ret
    body = genex(ctx, retsum)
    popscope!(ctx)
    return Ex(:closure, FnT(want.psums, retsum), params, [body])
end

# ---------------------------------------------------------------------------
# Statements

const CONCRETE_MENU = TySum[IntT, IntT, IntT, FloatT, FloatT, BoolT, StrT, SymT]

function newvarsum(ctx::Ctx)
    r = rand(ctx.rng)
    r < 0.55 && return pick(ctx.rng, CONCRETE_MENU)
    r < 0.70 && return VecT(pick(ctx.rng, TySum[IntT, FloatT, AnyT()]))
    r < 0.80 && return TupT(TySum[pick(ctx.rng, CONCRETE_MENU) for _ in 1:rand(ctx.rng, 2:3)])
    r < 0.92 && return FnT(TySum[pick(ctx.rng, TySum[IntT, FloatT, AnyT()]) for _ in 1:rand(ctx.rng, 1:2)], AnyT())
    return AnyT()
end

function genstmt(ctx::Ctx; allowobs::Bool=true, blockdepth::Int=0)::St
    rng = ctx.rng
    opts = Tuple{Float64,Symbol}[(4.0, :assignnew)]
    !isempty(visiblevars(ctx)) && push!(opts, (1.5, :reassign))
    allowobs && push!(opts, (2.5, :observe))
    if blockdepth < 2
        push!(opts, (1.2, :if), (1.0, :for), (0.7, :while), (0.6, :let), (0.7, :try))
    end
    anyvec = any(v -> v.sum isa VecT, visiblevars(ctx))
    anyvec && push!(opts, (1.0, :push), (0.7, :setindex), (0.5, :alias))
    kind = wpick(rng, opts)

    if kind === :assignnew
        sum = newvarsum(ctx)
        rhs = genex(ctx, sum)
        name = freshname(ctx, "v")
        st = St(:assign, (name, rhs.sum, true); exs=[rhs])
        declare!(ctx, VInfo(name, rhs.sum))
        return st
    elseif kind === :reassign
        v = pick(rng, visiblevars(ctx))
        rhs = v.sum isa AnyT ? genex(ctx, pick(rng, CONCRETE_MENU)) : genex(ctx, v.sum)
        return St(:assign, (v.name, v.sum, false); exs=[rhs])
    elseif kind === :observe
        s = pick(rng, TySum[IntT, FloatT, BoolT, StrT, SymT, AnyT(), VecT(IntT), TupT(TySum[IntT, StrT])])
        return St(:observe; exs=[genex(ctx, s)])
    elseif kind === :if
        cond = genex(ctx, BoolT)
        haselse = rand(rng, Bool)
        thenb = genblock(ctx, blockdepth; n=rand(rng, 1:3))
        blocks = [thenb]
        haselse && push!(blocks, genblock(ctx, blockdepth; n=rand(rng, 1:3)))
        return St(:if, haselse; exs=[cond], blocks=blocks)
    elseif kind === :for
        ivar = freshname(ctx, "i")
        n = rand(rng, 0:ctx.cfg.maxloop)
        body = genblock(ctx, blockdepth; n=rand(rng, 1:3), extra=[VInfo(ivar, IntT)])
        return St(:for, (ivar, n); blocks=[body])
    elseif kind === :while
        fuelvar = freshname(ctx, "fuel")
        fuel = rand(rng, 1:ctx.cfg.maxloop)
        cond = genex(ctx, BoolT)
        body = genblock(ctx, blockdepth; n=rand(rng, 1:3))
        return St(:while, (fuelvar, fuel); exs=[cond], blocks=[body])
    elseif kind === :let
        nb = rand(rng, 1:2)
        bindings = Tuple{Symbol,TySum}[]
        rhss = Ex[]
        for _ in 1:nb
            s = pick(rng, CONCRETE_MENU)
            rhs = genex(ctx, s)
            push!(bindings, (freshname(ctx, "l"), rhs.sum))
            push!(rhss, rhs)
        end
        body = genblock(ctx, blockdepth; n=rand(rng, 1:3), extra=[VInfo(n, s) for (n, s) in bindings])
        return St(:let, bindings; exs=rhss, blocks=[body])
    elseif kind === :try
        excvar = freshname(ctx, "err")
        hasfinally = rand(rng) < 0.3
        body = genblock(ctx, blockdepth; n=rand(rng, 1:3))
        handler = genblock(ctx, blockdepth; n=rand(rng, 1:2), extra=[VInfo(excvar, AnyT())])
        blocks = [body, handler]
        hasfinally && push!(blocks, genblock(ctx, blockdepth; n=1))
        return St(:try, (excvar, hasfinally); blocks=blocks)
    elseif kind === :push
        vs = [v for v in visiblevars(ctx) if v.sum isa VecT]
        v = pick(rng, vs)
        elt = (v.sum::VecT).elt
        return St(:push, v.name; exs=[genex(ctx, elt isa AnyT ? pick(rng, CONCRETE_MENU) : elt)])
    elseif kind === :setindex
        vs = [v for v in visiblevars(ctx) if v.sum isa VecT]
        v = pick(rng, vs)
        elt = (v.sum::VecT).elt
        return St(:setindex, v.name; exs=[genex(ctx, IntT), genex(ctx, elt isa AnyT ? pick(rng, CONCRETE_MENU) : elt)])
    elseif kind === :alias
        vs = [v for v in visiblevars(ctx) if v.sum isa VecT]
        v = pick(rng, vs)
        name = freshname(ctx, "al")
        st = St(:alias, (name, v.name, v.sum))
        declare!(ctx, VInfo(name, v.sum))
        return st
    end
    error("unreachable stmt kind $kind")
end

function genblock(ctx::Ctx, blockdepth::Int; n::Int=2, extra::Vector{VInfo}=VInfo[])
    pushscope!(ctx)
    for v in extra
        declare!(ctx, v)
    end
    sts = St[]
    for _ in 1:n
        push!(sts, genstmt(ctx; blockdepth=blockdepth + 1))
    end
    popscope!(ctx)
    return sts
end

# ---------------------------------------------------------------------------
# Toplevel function definitions

function genfundef(ctx::Ctx)::St
    rng = ctx.rng
    if rand(rng) < 0.25
        # fueled self-recursion template
        name = freshname(ctx, "fr")
        pushscope!(ctx)
        declare!(ctx, VInfo(:n, IntT))
        declare!(ctx, VInfo(:acc, IntT))
        stepex = genex(ctx, IntT)
        popscope!(ctx)
        push!(ctx.fns, FnInfo(name, [TySum[IntT, IntT]], IntT))
        return St(:recdef, (name, IntT); exs=[stepex])
    end
    name = freshname(ctx, "f")
    nparams = rand(rng, 0:3)
    params = Tuple{Symbol,TySum,Bool}[]
    for i in 1:nparams
        s = rand(rng) < 0.25 ? AnyT() : pick(rng, CONCRETE_MENU)
        typed = s isa ConcT && rand(rng, Bool)
        push!(params, (freshname(ctx, "a"), s, typed))
    end
    retsum = pick(rng, CONCRETE_MENU)
    pushscope!(ctx)
    for (pn, ps, _) in params
        declare!(ctx, VInfo(pn, ps))
    end
    wasinfunc = ctx.infunc
    ctx.infunc = true
    body = St[]
    for _ in 1:rand(rng, 0:3)
        push!(body, genstmt(ctx; allowobs=true, blockdepth=1))
    end
    retex = genex(ctx, retsum)
    ctx.infunc = wasinfunc
    popscope!(ctx)
    fi = FnInfo(name, [TySum[p[2] for p in params]], retex.sum)
    push!(ctx.fns, fi)
    return St(:fundef, (name, params, retex.sum); exs=[retex], blocks=[body])
end

# A second method for an existing function: same arity, different first-param
# type — call sites then dispatch dynamically.
function genextramethod(ctx::Ctx, fi::FnInfo)::Union{St,Nothing}
    rng = ctx.rng
    sig = fi.sigs[1]
    isempty(sig) && return nothing
    first0 = sig[1]
    alts = [s for s in (IntT, FloatT, StrT, BoolT) if !(first0 isa ConcT && compat_eq(s, first0))]
    isempty(alts) && return nothing
    newsig = TySum[pick(rng, alts); sig[2:end]]
    params = Tuple{Symbol,TySum,Bool}[]
    for s in newsig
        push!(params, (freshname(ctx, "a"), s, s isa ConcT))
    end
    params[1] = (params[1][1], params[1][2], true)  # the distinguishing param must be typed
    retsum = pick(rng, CONCRETE_MENU)
    pushscope!(ctx)
    for (pn, ps, _) in params
        declare!(ctx, VInfo(pn, ps))
    end
    # Hide `fi` while generating this body: a self-call here would be
    # recursion without fuel, breaking termination-by-construction (both
    # sides then die of StackOverflowError at depths that legitimately
    # observe different amounts — noise, not an interpreter bug).
    selfidx = findfirst(f -> f === fi, ctx.fns)
    selfidx === nothing || deleteat!(ctx.fns, selfidx)
    retex = genex(ctx, retsum)
    selfidx === nothing || push!(ctx.fns, fi)
    popscope!(ctx)
    push!(fi.sigs, newsig)
    fi.ret = joinsum(fi.ret, retex.sum)
    return St(:fundef, (fi.name, params, retex.sum); exs=[retex], blocks=[St[]])
end

# ---------------------------------------------------------------------------
# Whole programs

function genprogram(rng::AbstractRNG, cfg::Cfg=Cfg())::Program
    ctx = Ctx(rng, cfg)
    fundefs = St[]
    for _ in 1:rand(rng, cfg.nfundefs)
        push!(fundefs, genfundef(ctx))
        if !isempty(ctx.fns) && rand(rng) < 0.3
            st = genextramethod(ctx, ctx.fns[end])
            st === nothing || push!(fundefs, st)
        end
    end
    pushscope!(ctx)  # the toplevel `let`
    body = St[]
    for _ in 1:rand(rng, cfg.nbodystmts)
        push!(body, genstmt(ctx))
    end
    # Always end by observing a few live variables so every program compares state.
    vars = visiblevars(ctx)
    for v in (length(vars) <= 3 ? vars : vars[randperm(rng, length(vars))[1:3]])
        v.sum isa FnT && continue  # functions normalize to :__fn__; nothing to learn
        push!(body, St(:observe; exs=[Ex(:var, v.sum, v.name)]))
    end
    popscope!(ctx)
    return Program(fundefs, body)
end
