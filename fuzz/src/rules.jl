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
        want.t === :Char && return lit(pick(rng, ['a', 'b', 'x', 'α', '∀', '🐛', '0', ' ']), want)
        want.t === :Nothing && return lit(nothing, want)
    elseif want isa TupT
        return Ex(:tuple, want, nothing, [genleaf(ctx, e) for e in want.elts])
    elseif want isa VecT
        return Ex(:vect, want, nothing, [genleaf(ctx, want.elt) for _ in 1:rand(ctx.rng, 1:3)])
    elseif want isa DictT
        # Dict{K,V}(k1 => v1, ...) — keys drawn from the content-hashed whitelist.
        npairs = rand(rng, 0:3)
        kids = Ex[]
        for _ in 1:npairs
            push!(kids, genleaf(ctx, want.k))
            push!(kids, genleaf(ctx, want.v))
        end
        return Ex(:dictlit, want, nothing, kids)
    elseif want isa SetT
        nelts = rand(rng, 0:3)
        return Ex(:setlit, want, nothing, [genleaf(ctx, want.elt) for _ in 1:nelts])
    elseif want isa FnT
        return genclosure(ctx, want)
    elseif want isa StructT
        # construct: Name(field values...)
        args = Ex[genleaf(ctx, fs) for fs in want.fieldsums]
        return Ex(:call, want, want.name, args)
    end
    # AnyT leaf: any concrete literal
    return genlit(ctx, pick(ctx.rng, TySum[IntT, FloatT, BoolT, StrT, SymT, NothingT]))
end

function randstring_src(ctx::Ctx)
    n = rand(ctx.rng, 0:ctx.cfg.maxstring)
    alphabet = ['a', 'b', 'x', 'y', '0', '1', ' ', '!', 'α', 'β', '∀', '🐛']
    return String([pick(ctx.rng, alphabet) for _ in 1:n])
end

# The builtins/intrinsics probe rule lives in probes.jl: `genprobe(ctx)`
# enumerates every Core.Builtin and Core.Intrinsics function by reflection
# (the same enumeration bin/generate_builtins.jl uses to *write*
# src/builtins.jl), sweeps arities, and draws arguments from this generator —
# in-scope structs, vectors, closures and symbols mixed with adversarial
# literals — behind a safety denylist. What used to be 76 verbatim strings is
# now three curated tables (PROBE_BANS / PROBE_RECIPES / FIXED_PROBES) over a
# version-relative target list.

function genex_inner(ctx::Ctx, want::TySum)::Ex
    rng = ctx.rng
    opts = Tuple{Float64,Symbol}[]
    if want isa ConcT && (want.t === :Int || want.t === :Float)
        push!(opts, (3.0, :leaf), (3.0, :arith), (1.0, :ternary), (0.8, :minmax), (0.8, :vecget))
        want.t === :Int && push!(opts, (0.8, :veclen), (0.6, :strlen), (0.6, :intdiv))
        # Explicit-RNG draws and the virtual clock: data-dependent Int/Float
        # values that flow into indices, conditions and loop bounds. Both sides
        # execute the same draw, so the values agree bit-for-bit.
        if rngavail(ctx)
            want.t === :Int && push!(opts, (0.8, :rngint), (0.6, :vtime))
            want.t === :Float && push!(opts, (0.8, :rngfloat))
        end
    elseif want isa ConcT && want.t === :Bool
        push!(opts, (2.0, :leaf), (3.0, :cmp), (1.5, :andor), (1.0, :not), (0.8, :isa), (0.6, :egal), (0.6, :ternary))
        rngavail(ctx) && push!(opts, (0.6, :rngbool))
    elseif want isa ConcT && want.t === :Str
        push!(opts, (3.0, :leaf), (2.0, :strcat), (0.8, :ternary))
    elseif want isa ConcT
        push!(opts, (1.0, :leaf))
    elseif want isa TupT || want isa VecT || want isa DictT || want isa SetT
        push!(opts, (1.0, :leaf))
    elseif want isa FnT
        push!(opts, (1.0, :closure))
    elseif want isa StructT
        # Without this, a struct want fell through to the AnyT menu, which can
        # produce Any-summarized expressions (guarded probes, division results)
        # where a struct value is required — passing one to a `::S`-annotated
        # parameter throws MethodError and truncates the program. :leaf builds
        # the struct (existing variable or a fresh construction); the :callfn
        # and :getprop options appended below cover the other two ways to get
        # one, so nothing is lost.
        push!(opts, (1.0, :leaf))
    else # AnyT
        push!(opts, (2.0, :leaf), (1.5, :guardix), (1.0, :callvar), (0.8, :guarddiv), (0.6, :ternary),
              (1.4, :builtin))
        # guarded call with one deliberately wrong-typed argument: MethodError
        # construction / localmethtable miss, or an error deep inside the callee
        # propagating through interpreted frames
        !isempty(ctx.fns) && push!(opts, (0.8, :badcall))
    end
    # (swarm masking / policy skew are applied at the wpickrule call below)
    # Calls into generated functions, for any want their return satisfies:
    if !isempty(fnsreturning(ctx, want))
        push!(opts, (2.0, :callfn))
    end
    # keyword calls into functions that declare kwargs
    if any(f -> !isempty(f.kwnames) && compat(want, f.ret), ctx.fns)
        push!(opts, (1.2, :kwcall))
    end
    # field reads off in-scope struct values
    if !isempty([v for v in visiblevars(ctx) if v.sum isa StructT && any(fs -> compat(want, fs), (v.sum::StructT).fieldsums)])
        push!(opts, (1.5, :getprop))
    end
    # content-keyed Dict/Set value-producing operations (determinism.md §4).
    # These are the associative-container / iteration-protocol paths (two-arg
    # getindex vs three-arg get, haskey, membership, length) untested today.
    if swarmon(ctx, :dict)
        dvars = [v for v in visiblevars(ctx) if v.sum isa DictT]
        svars = [v for v in visiblevars(ctx) if v.sum isa SetT]
        if want isa ConcT && want.t === :Int && (!isempty(dvars) || !isempty(svars))
            push!(opts, (0.8, :dictlen))
        end
        if want isa ConcT && want.t === :Bool
            isempty(dvars) || push!(opts, (0.8, :haskey))
            isempty(svars) || push!(opts, (0.8, :setin))
        end
        if want isa ConcT && any(v -> compat(want, (v.sum::DictT).v), dvars)
            push!(opts, (1.0, :dictget))
        end
    end
    kind = wpickrule(ctx, opts)

    if kind === :leaf
        return genleaf(ctx, want)
    elseif kind === :arith
        op = want == IntT ? pick(rng, [:+, :-, :*]) : pick(rng, [:+, :-, :*, :/])
        # Float arithmetic occasionally mixes in an Int operand (promotion path)
        bsum = (want == FloatT && rand(rng) < 0.25) ? IntT : want
        return Ex(:binop, want, op, [genex(ctx, want), genex(ctx, bsum)])
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
        # No Float operands: `===` is bitwise, and the NaN an operation yields
        # (its payload/sign bits) is not part of Julia's contract — compiled
        # and interpreted execution may pick different NaN bit patterns, so
        # `floatexpr === floatexpr` is nondeterministic across the two engines
        # and not a meaningful differential property. Value observations of
        # bare floats stay fair (`isequal` treats all NaNs equal).
        s = pick(rng, TySum[IntT, SymT, StrT, BoolT])
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
        args = Ex[genex(ctx, p isa AnyT ? anyargsum(ctx) : p) for p in fs.psums]
        return Ex(:callvar, fs.ret, v.name, args)
    elseif kind === :callfn
        f = pick(rng, fnsreturning(ctx, want))
        # Pick the *method*, and consult that method's own vararg flag: only the
        # signature created by genfundef has a `va...`, so appending trailing
        # args because some other method of the same function is variadic builds
        # a call that matches nothing and dies with a MethodError.
        si = rand(rng, 1:length(f.sigs))
        sig = f.sigs[si]
        args = Ex[genex(ctx, p isa AnyT ? anyargsum(ctx) : p) for p in sig]
        # varargs method: sometimes append extra trailing args, occasionally splat a vector
        if f.varargs[si] && rand(rng) < 0.5
            for _ in 1:rand(rng, 0:2)
                push!(args, genex(ctx, pick(rng, CONCRETE_MENU)))
            end
            if rand(rng) < 0.3
                push!(args, Ex(:splat, AnyT(), nothing, [genex(ctx, VecT(IntT))]))
            end
        end
        return Ex(:call, f.ret, f.name, args)
    elseif kind === :kwcall
        cands = [f for f in ctx.fns if !isempty(f.kwnames) && compat(want, f.ret)]
        f = pick(rng, cands)
        sig = f.sigs[1]
        args = Ex[genex(ctx, p isa AnyT ? anyargsum(ctx) : p) for p in sig]
        # pass a random subset of declared kwargs (all default to Int)
        chosen = [kw for kw in f.kwnames if rand(rng, Bool)]
        for kw in chosen
            push!(args, genex(ctx, IntT))
        end
        return Ex(:kwcall, f.ret, (f.name, chosen), args)
    elseif kind === :builtin
        # Reflection-driven prober (probes.jl): enumerated callable, arity
        # sweep, arguments from this generator, always guarded.
        return genprobe(ctx)
    elseif kind === :badcall
        f = pick(rng, ctx.fns)
        sig = pick(rng, f.sigs)
        args = Ex[genex(ctx, p isa AnyT ? anyargsum(ctx) : p) for p in sig]
        # A struct-typed parameter given a scalar is as good a MethodError probe
        # as a mistyped scalar, so include those slots too.
        idxs = [i for i in eachindex(sig) if sig[i] isa ConcT || sig[i] isa StructT]
        if !isempty(idxs)
            i = pick(rng, idxs)
            wrongs = [s for s in TySum[IntT, FloatT, StrT, BoolT, SymT] if !compat_eq(s, sig[i])]
            args[i] = genex(ctx, pick(rng, wrongs))
        end
        return Ex(:guard, AnyT(), nothing, [Ex(:call, AnyT(), f.name, args)])
    elseif kind === :getprop
        cands = [v for v in visiblevars(ctx) if v.sum isa StructT && any(fs -> compat(want, fs), (v.sum::StructT).fieldsums)]
        v = pick(rng, cands)
        s = v.sum::StructT
        idxs = [i for i in eachindex(s.fieldsums) if compat(want, s.fieldsums[i])]
        i = pick(rng, idxs)
        # atomic fields must be read with @atomic (plain access is an error)
        return Ex(s.atomicmask[i] ? :aprop : :prop, s.fieldsums[i], s.fieldnames[i],
                  [Ex(:var, v.sum, v.name)])
    elseif kind === :rngint
        # rand(__RNG__, Int) or rand(__RNG__, 1:n) — the bounded form is handy as
        # a guarded index or a small loop-shaped count.
        src = rand(rng) < 0.5 ? "rand(__RNG__, Int)" : "rand(__RNG__, 1:$(rand(rng, 2:9)))"
        return Ex(:rng, IntT, src)
    elseif kind === :rngfloat
        return Ex(:rng, FloatT, rand(rng) < 0.5 ? "rand(__RNG__)" : "randn(__RNG__)")
    elseif kind === :rngbool
        return Ex(:rng, BoolT, "rand(__RNG__, Bool)")
    elseif kind === :vtime
        return Ex(:vtime, IntT, nothing)
    elseif kind === :dictget
        cands = [v for v in visiblevars(ctx) if v.sum isa DictT && compat(want, (v.sum::DictT).v)]
        isempty(cands) && return genleaf(ctx, want)
        v = pick(rng, cands)
        dt = v.sum::DictT
        # get(d, k, default) / get!(d, k, default) — total, returns the val type.
        fn = rand(rng) < 0.4 ? :get! : :get
        return Ex(:callb, dt.v, fn, [Ex(:var, dt, v.name), genex(ctx, dt.k), genex(ctx, want)])
    elseif kind === :dictlen
        cands = [v for v in visiblevars(ctx) if v.sum isa DictT || v.sum isa SetT]
        isempty(cands) && return genleaf(ctx, want)
        v = pick(rng, cands)
        return Ex(:callb, IntT, :length, [Ex(:var, v.sum, v.name)])
    elseif kind === :haskey
        cands = [v for v in visiblevars(ctx) if v.sum isa DictT]
        isempty(cands) && return genleaf(ctx, want)
        v = pick(rng, cands)
        dt = v.sum::DictT
        return Ex(:callb, BoolT, :haskey, [Ex(:var, dt, v.name), genex(ctx, dt.k)])
    elseif kind === :setin
        cands = [v for v in visiblevars(ctx) if v.sum isa SetT]
        isempty(cands) && return genleaf(ctx, want)
        v = pick(rng, cands)
        st = v.sum::SetT
        return Ex(:callb, BoolT, :in, [genex(ctx, st.elt), Ex(:var, st, v.name)])
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
    # Mutable captures must be locals: `cap = cap + p` inside a closure over a
    # *global* makes cap a closure-local instead (shadowing), and the rhs read
    # of the still-unassigned local throws UndefVarError — a degenerate path,
    # not the Box path this rule exists to exercise.
    caps = [v for v in visiblevars(ctx) if isnumeric(v.sum) && !v.isglobal]
    if !isempty(caps) && !isempty(want.psums) && rand(rng) < 0.35
        # (p, ...) -> (cap = cap <op> p′; cap)   where p′ is a param of cap's summary
        cap = pick(rng, caps)
        pushscope!(ctx)
        # A closure body is a runtime scope, so count it — this branch used to
        # only *decrement*, leaving `rtscopes` one lower than reality for the
        # rest of the program. Everything generated afterwards then believed it
        # was at module toplevel: `while` fuel decrements rendered as
        # `global fuel -= 1` for a `let`-local counter, which is a lowering
        # error, and the parse gate silently discarded ~4% of all candidates
        # (measured 17/400 at the default policy, 22/400 under :builtins).
        ctx.rtscopes += 1
        for (p, s) in zip(params, want.psums)
            declare!(ctx, VInfo(p, s))
        end
        # the update must keep cap's summary: mix cap with an expression of the same summary
        upd = Ex(:binop, cap.sum, cap.sum == IntT ? pick(rng, [:+, :-, :*]) : pick(rng, [:+, :*]),
                 [Ex(:var, cap.sum, cap.name), genex(ctx, cap.sum)])
        ctx.rtscopes -= 1
        popscope!(ctx)
        retex = Ex(:var, cap.sum, cap.name)
        return Ex(:closuremut, FnT(want.psums, cap.sum), (params, cap.name), [upd, retex])
    end
    pushscope!(ctx)
    ctx.rtscopes += 1
    for (p, s) in zip(params, want.psums)
        declare!(ctx, VInfo(p, s isa AnyT ? AnyT() : s))
    end
    retsum = want.ret isa AnyT ? pick(rng, TySum[IntT, FloatT, BoolT, StrT]) : want.ret
    body = genex(ctx, retsum)
    ctx.rtscopes -= 1
    popscope!(ctx)
    return Ex(:closure, FnT(want.psums, retsum), params, [body])
end

# ---------------------------------------------------------------------------
# Statements

const CONCRETE_MENU = TySum[IntT, IntT, IntT, FloatT, FloatT, BoolT, StrT, SymT]

# Content-hashed key types (determinism.md §4): Int/String/Symbol/Char/Bool.
# Their `hash` is content-based and identical across the two engines, so a
# Dict/Set keyed by them iterates identically on both sides and the full value
# oracle applies. Mutable/objectid-keyed containers (class X) are excluded by
# never appearing here. Value types are ordinary comparable scalars.
const DICT_KEY_MENU = TySum[IntT, StrT, SymT, CharT, BoolT]
const DICT_VAL_MENU = TySum[IntT, FloatT, StrT, SymT, BoolT]

# A content-hashed key type, occasionally a tuple of two of them (still
# content-hashed, and it exercises tuple hashing/iteration as a key).
function dictkeysum(ctx::Ctx)
    rng = ctx.rng
    rand(rng) < 0.18 &&
        return TupT(TySum[pick(rng, DICT_KEY_MENU) for _ in 1:2])
    return pick(rng, DICT_KEY_MENU)
end

# A fresh Dict or Set summary, for newvarsum and the observe menu.
dictsum(ctx::Ctx) = DictT(dictkeysum(ctx), pick(ctx.rng, DICT_VAL_MENU))
setsum(ctx::Ctx) = SetT(dictkeysum(ctx))

# Summary for a generated function's parameter or return value. Scalars stay
# dominant, but tuples/vectors/structs/functions now cross call boundaries:
# previously every parameter and return was concretized to a scalar, so an
# interpreted callee could never receive or return a container, a struct, or a
# closure — no higher-order generated functions, and no aggregate passing at
# all. Those are ordinary Julia and distinct interpreter paths (argument
# destructuring, boxed captures crossing frames, struct dispatch).
function boundarysum(ctx::Ctx)
    rng = ctx.rng
    r = rand(rng)
    r < 0.62 && return pick(rng, CONCRETE_MENU)
    r < 0.72 && return AnyT()
    if r < 0.80
        return TupT(TySum[pick(rng, CONCRETE_MENU) for _ in 1:rand(rng, 2:3)])
    end
    r < 0.88 && return VecT(pick(rng, TySum[IntT, FloatT, AnyT()]))
    if r < 0.95 && !isempty(ctx.structs)
        return pick(rng, ctx.structs)
    end
    return FnT(TySum[pick(rng, TySum[IntT, FloatT]) for _ in 1:rand(rng, 1:2)], AnyT())
end

# May a parameter of this summary carry a type annotation? Struct annotations
# are the interesting ones — they make dispatch on generated types real.
annotatable(s::TySum) = s isa ConcT || s isa StructT || s isa VecT || s isa TupT || s isa FnT

# What to pass into an `Any`-typed parameter. Scalars dominate, but a container,
# struct, closure or `nothing` reaching an Any slot is what makes the callee's
# dispatch genuinely dynamic — the localmethtable path this fuzzer targets.
function anyargsum(ctx::Ctx)
    rng = ctx.rng
    r = rand(rng)
    r < 0.70 && return pick(rng, TySum[IntT, FloatT, StrT, BoolT, SymT])
    r < 0.78 && return NothingT
    r < 0.86 && return TupT(TySum[pick(rng, CONCRETE_MENU) for _ in 1:rand(rng, 2:3)])
    r < 0.94 && return VecT(pick(rng, TySum[IntT, FloatT]))
    isempty(ctx.structs) && return pick(rng, TySum[IntT, StrT])
    return pick(rng, ctx.structs)
end
# Non-growable scalars only. Used for struct fields: a String field could be
# grown in place (x.f = string(x.f, x.f)) inside a looping/oft-called context,
# and structs have no per-field bound. Int/Float/Bool/Sym exercise field
# access, mutation, and dispatch fully without the memory risk.
const SCALAR_NONGROW = TySum[IntT, IntT, FloatT, FloatT, BoolT, SymT]

function newvarsum(ctx::Ctx)
    # Content-keyed Dict/Set bindings gate every Dict/Set rule (they all need a
    # container in scope), so the :determinism policy raises the rate of creating
    # one — boosting the op weights alone does nothing without a target. Drawn
    # first with an independent probability so it doesn't interact with the
    # struct/scalar cascade below.
    if swarmon(ctx, :dict)
        dictrate = ctx.policy === :determinism ? 0.40 : 0.10
        if rand(ctx.rng) < dictrate
            return rand(ctx.rng, Bool) ? dictsum(ctx) : setsum(ctx)
        end
    end
    r = rand(ctx.rng)
    # Struct-valued bindings gate every struct rule (field read/write, atomic
    # modify, struct aliasing), so the policies that target those rules raise
    # the rate of creating one — boosting the rule weights alone does nothing
    # when no variable of the right shape is ever in scope.
    structrate = (ctx.policy === :mutation || ctx.policy === :builtins) ? 0.35 : 0.12
    if !isempty(ctx.structs) && r < structrate
        return pick(ctx.rng, ctx.structs)
    end
    r < 0.52 && return pick(ctx.rng, CONCRETE_MENU)
    r < 0.68 && return VecT(pick(ctx.rng, TySum[IntT, FloatT, AnyT()]))
    r < 0.78 && return TupT(TySum[pick(ctx.rng, CONCRETE_MENU) for _ in 1:rand(ctx.rng, 2:3)])
    r < 0.90 && return FnT(TySum[pick(ctx.rng, TySum[IntT, FloatT, AnyT()]) for _ in 1:rand(ctx.rng, 1:2)], AnyT())
    return AnyT()
end

# Variables eligible as reassignment targets. `const` globals are never
# reassigned (an error since 1.12, a warning before). Growable globals are
# excluded inside function bodies: a function is called an unbounded number of
# times, so letting it grow a growable global — even by a bounded amount per
# call — would accumulate without bound (the reference side has no memory cap).
# Growable globals are still writable from toplevel/let, where the write count
# is bounded by program size.
reassign_targets(ctx::Ctx) =
    [v for v in visiblevars(ctx) if !v.isconst && !(ctx.infunc && v.isglobal && growablevar(v))]

atomicnumfields(s::StructT) =
    [i for i in eachindex(s.fieldnames) if s.atomicmask[i] && isnumeric(s.fieldsums[i])]

function genstmt(ctx::Ctx; allowobs::Bool=true, blockdepth::Int=0)::St
    rng = ctx.rng
    opts = Tuple{Float64,Symbol}[(4.0, :assignnew)]
    !isempty(reassign_targets(ctx)) && push!(opts, (1.5, :reassign))
    allowobs && push!(opts, (2.5, :observe))
    if blockdepth < ctx.cfg.maxblockdepth
        # Deeper nesting is reachable but progressively rarer, so raising the
        # cap doesn't blow up program size / abort rate. Depth 0 is unscaled.
        d = ctx.cfg.blockdecay ^ blockdepth
        push!(opts, (1.2d, :if), (1.0d, :for), (0.7d, :while), (0.6d, :let), (0.7d, :try))
    end
    anyvec = any(v -> v.sum isa VecT, visiblevars(ctx))
    # push! grows a vector by one element per call; a global vector pushed from
    # a function body (called an unbounded number of times) grows without
    # bound. Allow push! only to vectors that aren't global-inside-a-function.
    pushable = [v for v in visiblevars(ctx) if v.sum isa VecT && !(ctx.infunc && v.isglobal)]
    !isempty(pushable) && push!(opts, (1.0, :push))
    anyvec && push!(opts, (0.7, :setindex))
    # aliasing: vectors and mutable structs (mutation through one name observed
    # through the other — identity semantics)
    aliasable = any(v -> v.sum isa VecT || (v.sum isa StructT && (v.sum::StructT).ismutable),
                    visiblevars(ctx))
    aliasable && push!(opts, (0.5, :alias))
    anymutstruct = any(v -> v.sum isa StructT && (v.sum::StructT).ismutable, visiblevars(ctx))
    anymutstruct && push!(opts, (0.8, :setprop))
    any(v -> v.sum isa StructT && !isempty(atomicnumfields(v.sum::StructT)), visiblevars(ctx)) &&
        push!(opts, (0.5, :amodify))
    push!(opts, (0.6, :compr))
    # the undefined-variable dimension: conditionally-defined bindings observed
    # via @isdefined and guarded reads (UndefVarError as expected oracle data)
    allowobs && push!(opts, (0.55, :maybeundef))
    allowobs && blockdepth < ctx.cfg.maxblockdepth && push!(opts, (0.5, :loopundef))
    # `local x::T = v` — conversion/typeassert on every later reassignment
    inlocal(ctx) && push!(opts, (0.7, :typedlocal))
    # content-keyed Dict/Set mutation + observation (determinism.md §4)
    if swarmon(ctx, :dict)
        anydict = any(v -> v.sum isa DictT, visiblevars(ctx))
        anyset = any(v -> v.sum isa SetT, visiblevars(ctx))
        anydict && push!(opts, (0.8, :dictset), (0.5, :dictdel))
        anyset && push!(opts, (0.6, :setpush))
        allowobs && (anydict || anyset) && push!(opts, (0.7, :dictobs))
    end
    # control-flow exits; break/continue through try/finally is the :enter/:leave
    # and exception-frame-unwinding surface
    ctx.loopdepth > 0 && push!(opts, (1.0, :brk), (0.8, :cont))
    ctx.retsum !== nothing && push!(opts, (0.9, :ret))
    kind = wpickrule(ctx, opts)

    if kind === :assignnew
        sum = newvarsum(ctx)
        rhs = genex(ctx, sum)
        name = freshname(ctx, "v")
        st = St(:assign, (name, rhs.sum, true, false); exs=[rhs])
        declare!(ctx, VInfo(name, rhs.sum))
        return st
    elseif kind === :reassign
        v = pick(rng, reassign_targets(ctx))
        # Two safety hides on the rhs of a reassignment:
        #  - FnT target: hide function vars so two closures can't form a call
        #    cycle (unbounded recursion).
        #  - growable target (String/Vector/Any): hide all growable vars so the
        #    new value can't be built from growable ones — prevents exponential
        #    memory growth (g = string(g, g) and cross-referential chains),
        #    which the reference side has no bound against.
        rhs = if v.sum isa FnT
            withoutfns(ctx) do
                genex(ctx, v.sum)
            end
        elseif growablevar(v)
            withoutgrowables(ctx) do
                genex(ctx, v.sum isa AnyT ? pick(rng, TySum[IntT, FloatT, BoolT, SymT]) : v.sum)
            end
        else
            genex(ctx, v.sum)
        end
        # Writing a module global from inside local scope needs `global`.
        needsglobal = v.isglobal && inlocal(ctx)
        return St(:assign, (v.name, v.sum, false, needsglobal); exs=[rhs])
    elseif kind === :setprop
        cands = [v for v in visiblevars(ctx) if v.sum isa StructT && (v.sum::StructT).ismutable]
        v = pick(rng, cands)
        s = v.sum::StructT
        i = rand(rng, 1:length(s.fieldnames))
        return St(:setprop, (v.name, s.fieldnames[i], s.atomicmask[i]);
                  exs=[genex(ctx, s.fieldsums[i])])
    elseif kind === :amodify
        cands = [v for v in visiblevars(ctx) if v.sum isa StructT && !isempty(atomicnumfields(v.sum::StructT))]
        v = pick(rng, cands)
        s = v.sum::StructT
        i = pick(rng, atomicnumfields(s))
        op = pick(rng, [:+, :-, :*])
        return St(:amodify, (v.name, s.fieldnames[i], op); exs=[genex(ctx, s.fieldsums[i])])
    elseif kind === :compr
        # v = Type[ body for i in 1:n (if cond)? ]
        eltsum = pick(rng, TySum[IntT, FloatT])
        ivar = freshname(ctx, "c")
        n = rand(rng, 0:ctx.cfg.maxloop)
        hasfilter = rand(rng) < 0.4
        pushscope!(ctx)
        ctx.rtscopes += 1
        declare!(ctx, VInfo(ivar, IntT))
        body = genex(ctx, eltsum)
        kids = hasfilter ? [body, genex(ctx, BoolT)] : [body]
        ctx.rtscopes -= 1
        popscope!(ctx)
        name = freshname(ctx, "v")
        st = St(:assign, (name, VecT(eltsum), true, false);
                exs=[Ex(:compr, VecT(eltsum), (ivar, n, hasfilter), kids)])
        declare!(ctx, VInfo(name, VecT(eltsum)))
        return st
    elseif kind === :observe
        s = pick(rng, TySum[IntT, FloatT, BoolT, StrT, SymT, AnyT(), VecT(IntT), TupT(TySum[IntT, StrT])])
        return St(:observe; exs=[genex(ctx, s)])
    elseif kind === :if
        cond = genex(ctx, BoolT)
        haselse = rand(rng, Bool)
        thenb = genblock(ctx, blockdepth; scoping=false)
        blocks = [thenb]
        haselse && push!(blocks, genblock(ctx, blockdepth; scoping=false))
        return St(:if, haselse; exs=[cond], blocks=blocks)
    elseif kind === :for
        ivar = freshname(ctx, "i")
        hi = ctx.cfg.maxloop
        # A rand-derived trip count where a literal bound sits today — data
        # dependence without breaking termination (bounded by maxloop). Both
        # sides draw the same count from __RNG__, so iteration stays in lockstep.
        userng = rngavail(ctx) && rand(rng) < 0.35
        meta = userng ? (ivar, hi, "rand(__RNG__, 0:$hi)") : (ivar, rand(rng, 0:hi))
        ctx.loopdepth += 1
        body = genblock(ctx, blockdepth; extra=[VInfo(ivar, IntT)])
        ctx.loopdepth -= 1
        return St(:for, meta; blocks=[body])
    elseif kind === :while
        fuelvar = freshname(ctx, "fuel")
        fuel = rand(rng, 1:ctx.cfg.maxloop)
        cond = genex(ctx, BoolT)
        # The rendered fuel decrement is the first statement of the loop body,
        # so a generated `continue` cannot skip it — termination is preserved.
        # At module toplevel the fuel counter is a *global* and the loop body is
        # a soft scope, where a bare `fuel -= 1` would silently declare a new
        # local and throw UndefVarError reading it. Qualify the decrement with
        # `global` there so the counter actually decrements.
        attop = !inruntimelocal(ctx)
        ctx.loopdepth += 1
        body = genblock(ctx, blockdepth)
        ctx.loopdepth -= 1
        return St(:while, (fuelvar, fuel, attop); exs=[cond], blocks=[body])
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
        body = genblock(ctx, blockdepth; extra=[VInfo(n, s) for (n, s) in bindings])
        return St(:let, bindings; exs=rhss, blocks=[body])
    elseif kind === :try
        excvar = freshname(ctx, "err")
        hasfinally = rand(rng) < 0.3
        haselse = rand(rng) < 0.25   # try/catch/else — distinct (1.8+) lowering
        body = genblock(ctx, blockdepth)
        handler = genblock(ctx, blockdepth; n=rand(rng, 1:2), extra=[VInfo(excvar, AnyT())])
        # occasionally rethrow out of the handler (conditionally): exception
        # propagation out of an interpreted catch block
        rand(rng) < 0.25 && push!(handler, St(:rethrowif; exs=[genex(ctx, BoolT)]))
        blocks = [body, handler]
        haselse && push!(blocks, genblock(ctx, blockdepth; n=1))
        if hasfinally
            # No break/continue/return from inside finally: Julia's lowering
            # rejects some of these forms, and the rest are pathological enough
            # to drown the signal. Mask the exit context while generating it.
            saveld, saveret = ctx.loopdepth, ctx.retsum
            ctx.loopdepth = 0; ctx.retsum = nothing
            push!(blocks, genblock(ctx, blockdepth; n=1))
            ctx.loopdepth = saveld; ctx.retsum = saveret
        end
        return St(:try, (excvar, hasfinally, haselse); blocks=blocks)
    elseif kind === :push
        vs = [v for v in visiblevars(ctx) if v.sum isa VecT && !(ctx.infunc && v.isglobal)]
        v = pick(rng, vs)
        elt = (v.sum::VecT).elt
        return St(:push, v.name; exs=[genex(ctx, elt isa AnyT ? pick(rng, CONCRETE_MENU) : elt)])
    elseif kind === :setindex
        vs = [v for v in visiblevars(ctx) if v.sum isa VecT]
        v = pick(rng, vs)
        elt = (v.sum::VecT).elt
        return St(:setindex, v.name; exs=[genex(ctx, IntT), genex(ctx, elt isa AnyT ? pick(rng, CONCRETE_MENU) : elt)])
    elseif kind === :alias
        vs = [v for v in visiblevars(ctx)
              if v.sum isa VecT || (v.sum isa StructT && (v.sum::StructT).ismutable)]
        v = pick(rng, vs)
        name = freshname(ctx, "al")
        st = St(:alias, (name, v.name, v.sum))
        declare!(ctx, VInfo(name, v.sum))
        return st
    elseif kind === :brk
        return St(:brk; exs=[genex(ctx, BoolT)])
    elseif kind === :cont
        return St(:cont; exs=[genex(ctx, BoolT)])
    elseif kind === :ret
        return St(:ret; exs=[genex(ctx, BoolT), genex(ctx, ctx.retsum::TySum)])
    elseif kind === :maybeundef
        name = freshname(ctx, "u")
        cond = genex(ctx, BoolT)
        rhs = genex(ctx, pick(rng, CONCRETE_MENU))
        # deliberately NOT declared in ctx: later statements must not reference
        # a maybe-undefined binding unguarded
        return St(:maybeundef, name; exs=[cond, rhs])
    elseif kind === :loopundef
        ivar = freshname(ctx, "li")
        xname = freshname(ctx, "lx")
        n = rand(rng, 2:3)
        when = rand(rng, 2:n)
        pushscope!(ctx)
        ctx.rtscopes += 1
        declare!(ctx, VInfo(ivar, IntT))
        rhs = genex(ctx, pick(rng, TySum[IntT, FloatT]))
        ctx.rtscopes -= 1
        popscope!(ctx)
        return St(:loopundef, (ivar, xname, n, when); exs=[rhs])
    elseif kind === :typedlocal
        s = pick(rng, TySum[IntT, FloatT])
        rhs = genex(ctx, s)
        name = freshname(ctx, "t")
        st = St(:typedlocal, (name, s); exs=[rhs])
        declare!(ctx, VInfo(name, s))
        return st
    elseif kind === :dictset
        cands = [v for v in visiblevars(ctx) if v.sum isa DictT]
        v = pick(rng, cands)
        dt = v.sum::DictT
        return St(:dictset, v.name; exs=[genex(ctx, dt.k), genex(ctx, dt.v)])
    elseif kind === :dictdel
        cands = [v for v in visiblevars(ctx) if v.sum isa DictT]
        v = pick(rng, cands)
        dt = v.sum::DictT
        return St(:dictdel, v.name; exs=[genex(ctx, dt.k)])
    elseif kind === :setpush
        cands = [v for v in visiblevars(ctx) if v.sum isa SetT]
        v = pick(rng, cands)
        st = v.sum::SetT
        return St(:setpush, v.name; exs=[genex(ctx, st.elt)])
    elseif kind === :dictobs
        cands = [v for v in visiblevars(ctx) if v.sum isa DictT || v.sum isa SetT]
        v = pick(rng, cands)
        # keys/values apply only to Dicts; whole/len apply to both.
        proj = v.sum isa DictT ? pick(rng, [:whole, :keys, :values, :len]) :
                                 pick(rng, [:whole, :len])
        return St(:dictobs, (v.name, proj))
    end
    error("unreachable stmt kind $kind")
end

# A block statement count for a block whose statements sit at `childdepth`
# (1 = a block directly under a top-level statement). The ceiling is
# maxblockstmts at the top level and shrinks by one per extra nesting level
# (never below minblockstmts), so deep blocks stay small even as the depth cap
# rises — bounding total program size and abort rate.
function blockn(ctx::Ctx, childdepth::Int)
    cfg = ctx.cfg
    hi = max(cfg.minblockstmts, cfg.maxblockstmts - (childdepth - 1))
    return rand(ctx.rng, cfg.minblockstmts:hi)
end

# `scoping` says whether this block introduces a *runtime* scope. `for`, `while`,
# `let` and `try` bodies do; an `if` branch does not, so a binding made in one at
# toplevel is a module global. Generation scopes are pushed either way, because
# name visibility follows the block regardless.
function genblock(ctx::Ctx, blockdepth::Int; n::Int=blockn(ctx, blockdepth + 1),
                  extra::Vector{VInfo}=VInfo[], scoping::Bool=true)
    pushscope!(ctx)
    scoping && (ctx.rtscopes += 1)
    for v in extra
        declare!(ctx, v)
    end
    sts = St[]
    for _ in 1:n
        push!(sts, genstmt(ctx; blockdepth=blockdepth + 1))
    end
    scoping && (ctx.rtscopes -= 1)
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
        s = boundarysum(ctx)
        typed = annotatable(s) && rand(rng, Bool)
        push!(params, (freshname(ctx, "a"), s, typed))
    end
    # optional positional default on the last param (Int-valued)
    ndefaults = (nparams > 0 && rand(rng) < 0.25) ? 1 : 0
    # optional trailing vararg
    vararg = rand(rng) < 0.2
    varargname = vararg ? freshname(ctx, "va") : :_
    # optional keyword params (all Int, with defaults)
    kwparams = Tuple{Symbol,Any}[]
    if rand(rng) < 0.3
        for _ in 1:rand(rng, 1:2)
            push!(kwparams, (freshname(ctx, "kw"), rand(rng, -5:5)))
        end
    end
    retsum = boundarysum(ctx)
    pushscope!(ctx)
    # infunc goes up *before* the parameters are declared: declare! classifies a
    # binding as global or local from the context it is created in, and a
    # parameter declared while the context still says "module toplevel" would be
    # recorded as a global.
    wasinfunc, wasret, wasloop = ctx.infunc, ctx.retsum, ctx.loopdepth
    ctx.infunc = true
    for (pn, ps, _) in params
        declare!(ctx, VInfo(pn, ps))
    end
    vararg && declare!(ctx, VInfo(varargname, TupT(TySum[])))  # a Tuple; only used opaquely
    for (kn, _) in kwparams
        declare!(ctx, VInfo(kn, IntT))
    end
    ctx.retsum = retsum   # enables early `return` statements of the right summary
    ctx.loopdepth = 0     # function boundary: enclosing loops aren't break targets
    body = St[]
    # blockdepth 0: a function body nests control flow like the let body does,
    # so try/loop/if inside an *interpreted function frame* — the :enter/:leave
    # and exception-frame-unwinding surface — becomes generable.
    for _ in 1:rand(rng, 0:3)
        push!(body, genstmt(ctx; allowobs=true, blockdepth=0))
    end
    retex = genex(ctx, retsum)
    ctx.infunc, ctx.retsum, ctx.loopdepth = wasinfunc, wasret, wasloop
    popscope!(ctx)
    fi = FnInfo(name, [TySum[p[2] for p in params]], retex.sum,
                Symbol[kn for (kn, _) in kwparams], vararg)
    push!(ctx.fns, fi)
    return St(:fundef, (name, params, retex.sum, kwparams, vararg, varargname, ndefaults);
              exs=[retex], blocks=[body])
end

# A struct or mutable struct definition. Fields are concrete-summarized so
# construction and field access have well-defined summaries. Mutable structs
# occasionally declare `@atomic` fields: atomic get/set/modify lower to the
# ordering-carrying getfield/setfield!/modifyfield! builtin arities.
function genstructdef(ctx::Ctx)::St
    rng = ctx.rng
    name = freshname(ctx, "S")
    nf = rand(rng, 1:3)
    fnames = [freshname(ctx, "fld") for _ in 1:nf]
    # Mostly non-growable scalars (see SCALAR_NONGROW), but a field may also
    # hold a vector or a function. Both are safe against unbounded growth: a
    # field write *replaces* the value rather than appending to it (`push!`
    # only ever targets vector-typed variables), so the per-field bound the
    # scalar-only rule was protecting is preserved.
    fsums = TySum[rand(rng) < 0.15 ?
                  (rand(rng, Bool) ? VecT(pick(rng, TySum[IntT, FloatT])) :
                                     FnT(TySum[IntT], AnyT())) :
                  pick(rng, SCALAR_NONGROW) for _ in 1:nf]
    ismutable = rand(rng, Bool)
    # @atomic fields lower to the ordering-carrying getfield/setfield!/
    # modifyfield! arities that src/builtins.jl hand-dispatches, so the policy
    # aimed at builtins declares them more often.
    atomicrate = ctx.policy === :builtins ? 0.6 : 0.35
    mask = ismutable ? [rand(ctx.rng) < atomicrate for _ in 1:nf] : fill(false, nf)
    s = StructT(name, fnames, fsums, ismutable, mask)
    push!(ctx.structs, s)
    # register the constructor as a function so call sites can build values
    push!(ctx.fns, FnInfo(name, [copy(fsums)], s))
    return St(:structdef, s)
end

# A module-level global variable: occasionally `const` (never reassigned; the
# 1.12 binding-partition surface) or type-annotated (`global g::T = v` — every
# later write goes through convert + typeassert against the binding type).
function genglobal(ctx::Ctx)::St
    rng = ctx.rng
    s = pick(rng, CONCRETE_MENU)
    rhs = genex(ctx, s)
    name = freshname(ctx, "g")
    isconst = rand(rng) < 0.2
    typed = !isconst && isnumeric(rhs.sum) && rand(rng) < 0.35
    decl = isconst ? :const : typed ? Symbol(typename(rhs.sum::ConcT)) : :none
    v = VInfo(name, rhs.sum, true, isconst)
    push!(ctx.scopes[1], v)   # module-global scope
    return St(:assign, (name, rhs.sum, true, false, decl); exs=[rhs])
end

# A second method for an existing function: same arity, different first-param
# type — call sites then dispatch dynamically.
function genextramethod(ctx::Ctx, fi::FnInfo)::Union{St,Nothing}
    rng = ctx.rng
    sig = fi.sigs[1]
    isempty(sig) && return nothing
    first0 = sig[1]
    # Generated struct types are dispatch alternatives too, not just scalars:
    # dispatching between a struct method and a scalar method exercises the
    # interpreter's method lookup on types the program itself defined.
    cands = TySum[IntT, FloatT, StrT, BoolT]
    append!(cands, ctx.structs)
    alts = [s for s in cands if !compat_eq(s, first0)]
    isempty(alts) && return nothing
    newsig = TySum[pick(rng, alts); sig[2:end]]
    params = Tuple{Symbol,TySum,Bool}[]
    for s in newsig
        push!(params, (freshname(ctx, "a"), s, annotatable(s)))
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
    push!(fi.varargs, false)   # this method is rendered without a `va...`
    fi.ret = joinsum(fi.ret, retex.sum)
    return St(:fundef, (fi.name, params, retex.sum, Tuple{Symbol,Any}[], false, :_, 0);
              exs=[retex], blocks=[St[]])
end

# ---------------------------------------------------------------------------
# Whole programs

genprogram(rng::AbstractRNG, cfg::Cfg=Cfg())::Program = genprogram(Ctx(rng, cfg))

# Generate with one policy forced, overriding the drawn one. For measuring what
# a policy actually does to the distribution (fuzz/metrics.jl --policy NAME);
# campaigns draw the policy per program instead.
function genprogram_policy(rng::AbstractRNG, cfg::Cfg, policy::Symbol)::Program
    ctx = Ctx(rng, cfg)
    ctx.policy = policy
    return genprogram(ctx)
end

function genprogram(ctx::Ctx)::Program
    rng, cfg = ctx.rng, ctx.cfg
    # pre: structs then globals (both live in module scope, scopes[1])
    pre = St[]
    for _ in 1:rand(rng, cfg.nstructs)
        push!(pre, genstructdef(ctx))
    end
    for _ in 1:rand(rng, cfg.nglobals)
        push!(pre, genglobal(ctx))
    end
    # A mutable struct is only interesting if some *value* of it exists: field
    # writes, @atomic modify, and struct aliasing all require a binding of that
    # type in scope, and relying on newvarsum to happen to create one left the
    # whole atomics surface at ~1% of programs. Seed a module-global instance so
    # the rules that need one can fire — including from inside function bodies,
    # which is how a mutation reaches an interpreted frame.
    for s in ctx.structs
        s.ismutable || continue
        rand(rng) < 0.6 || continue
        name = freshname(ctx, "sv")
        args = Ex[genleaf(ctx, fs) for fs in s.fieldsums]
        push!(pre, St(:assign, (name, s, true, false); exs=[Ex(:call, s, s.name, args)]))
        push!(ctx.scopes[1], VInfo(name, s, true))
    end
    # fundefs
    fundefs = St[]
    for _ in 1:rand(rng, cfg.nfundefs)
        push!(fundefs, genfundef(ctx))
        if !isempty(ctx.fns) && rand(rng) < 0.3
            st = genextramethod(ctx, ctx.fns[end])
            st === nothing || push!(fundefs, st)
        end
    end
    # mid: bare toplevel statements (exercise the toplevel-frame path directly,
    # not the `let`-wrapped one). Assignments here create module globals.
    # blockdepth 1 (was a flat 2): a toplevel `for`/`if`/`try` is one
    # ExprSplitter fragment exercising loop/branch/exception handling in the
    # toplevel frame — a distinct path from the same construct inside `let`.
    mid = St[]
    for _ in 1:rand(rng, cfg.nmidstmts)
        st = genstmt(ctx; blockdepth=1)
        # a new binding created at true toplevel is a global (nested control-flow
        # statements aren't :assign, so their block-local bindings aren't marked)
        if st.kind === :assign && st.meta[3]
            last(ctx.scopes[end]).isglobal = true
        end
        push!(mid, st)
    end
    # body: the `let` block. That `let` is a real runtime scope, so bindings
    # made here are locals, not globals — without counting it, a `while` in the
    # body would emit `global fuel -= 1` for a variable that is local to the
    # `let`, which is a lowering error rather than merely wrong.
    pushscope!(ctx)
    ctx.rtscopes += 1
    body = St[]
    for _ in 1:rand(rng, cfg.nbodystmts)
        push!(body, genstmt(ctx))
    end
    # End by observing *every* live binding, so the final state of the whole
    # program is oracle data rather than just its last three variables. State
    # the interpreter got wrong in a binding nothing happened to observe was
    # previously invisible. Emitted deterministically (no RNG draw), which
    # keeps the choice sequence short for Supposition-driven generation.
    for v in reverse(visiblevars(ctx))
        if v.sum isa FnT
            # A function value normalizes to :__fn__, so identity teaches
            # nothing — but its *behavior* is comparable. Call it on inert
            # arguments, guarded so a MethodError becomes oracle data instead
            # of truncating the program.
            f = v.sum::FnT
            args = Ex[defaultex(p isa AnyT ? IntT : p) for p in f.psums]
            push!(body, St(:observe;
                           exs=[Ex(:guard, AnyT(), nothing,
                                   [Ex(:callvar, f.ret, v.name, args)])]))
        else
            push!(body, St(:observe; exs=[Ex(:var, v.sum, v.name)]))
        end
    end
    ctx.rtscopes -= 1
    popscope!(ctx)
    # Emit `const __RNG__ = Xoshiro(rngseed)` only when the explicit-RNG feature
    # is on for this program (rngavail); otherwise no rand rule could fire and
    # the declaration would be dead.
    return Program(pre, fundefs, mid, body, rngavail(ctx) ? ctx.rngseed : nothing)
end
