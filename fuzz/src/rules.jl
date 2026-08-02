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

# Builtins / intrinsics edge-case dictionary. Each entry renders verbatim
# source (an `:src` Ex) whose result is Any and always wrapped in a `:guard`,
# so both the value case and the exception-type case are first-class oracle
# data. These deliberately probe wrong arities, odd-but-lowerable argument
# types, and Core/reflection builtins that JuliaInterpreter special-cases —
# the historically bug-rich surface (src/builtins.jl).
const BUILTIN_PROBES = String[
    # getfield / setfield! / fieldative
    "getfield((1, 2, 3), 2)",
    "getfield((1, 2), 4)",
    "getfield(1, :x)",
    "nfields(1)",
    "nfields((1, 2, 3))",
    "fieldtype(Tuple{Int,String}, 1)",
    "fieldtype(Int, 1)",
    "isdefined(Main, :nonexistent_sym_zzz)",
    "getfield((a=1, b=2), :b)",
    "getfield((a=1, b=2), :c)",
    # type / apply_type
    "Core.apply_type(Array, Int, 1)",
    "Core.apply_type(Val)",
    "typeof(typeof(1))",
    "Core.apply_type(Tuple, Int, Vararg{Int})",
    "isa(1, Union{Int,String})",
    "1 isa DataType",
    # tuple / ntuple / splat builtins
    "ntuple(identity, 3)",
    "ntuple(identity, 0)",
    "tuple()",
    "Core.tuple(1, 2, 3)",
    "Core._apply_iterate(Base.iterate, +, (1, 2), (3, 4))",
    # arithmetic / conversion intrinsics.
    # NOTE: raw Core.Intrinsics division (sdiv_int/udiv_int/srem_int) is
    # deliberately absent — those map to a bare machine divide with no
    # DivideError check, so a zero divisor is an uncatchable CPU trap (SIGFPE)
    # that would kill the in-process worker rather than surface as a finding.
    # Both sides would trap identically anyway. Use the guarded `÷`/`%` rules
    # (:intdiv, :guarddiv) to probe division-by-zero semantics instead.
    "Core.Intrinsics.add_int(3, 4)",
    "Core.Intrinsics.checked_sadd_int(typemax(Int), 1)",
    "Core.Intrinsics.mul_int(6, 7)",
    "Core.Intrinsics.flipsign_int(3, -1)",
    "Core.Intrinsics.ctlz_int(0)",
    "Core.Intrinsics.not_int(true)",
    "Core.Intrinsics.copysign_float(1.5, -0.0)",
    "Core.Intrinsics.abs_float(-0.0)",
    "Core.bitcast(Float64, 0)",
    "Core.bitcast(Float64, Int64(4607182418800017408))",
    "reinterpret(Float64, Int64(0))",
    "Base.add_int(1, 2)",
    "Int8(300)",
    "trunc(Int8, 300.0)",
    # NOTE: in-range only — out-of-range unsafe_trunc is an *unspecified value*
    # (LLVM poison under compilation, runtime intrinsic under interpretation),
    # so an out-of-range probe would be a nondeterministic false positive.
    "unsafe_trunc(Int8, 100.0)",
    # equality / identity / ordering builtins
    "===(1, 1.0)",
    "Core.ifelse(true, 1, 2)",
    "Core.ifelse(1, 2, 3)",
    "objectid(nothing) isa UInt",
    "Core.sizeof(Int)",
    "Core.sizeof(1)",
    # arrays low-level
    "Core.arraysize([1,2,3], 1)",
    "Base.arrayref(true, [1,2,3], 4)",
    "Core.svec(1, 2, 3)",
    "getindex((1, 2, 3))",
    # Memory (1.11+; on older Julia both sides throw UndefVarError — symmetric)
    "length(Memory{Int}(undef, 3))",
    "let m = Memory{Int}(undef, 2); m[1] = 5; m[1] end",
    # atomics field family: hand-written per-arity dispatch in src/builtins.jl,
    # so probe every arity, wrong arities, and ordering violations
    "Core.swapfield!(Ref(3), :x, 7)",
    "Core.swapfield!(Ref(3), :x, 7, :sequentially_consistent)",
    "Core.swapfield!(Ref(3), :x)",
    "first(Core.modifyfield!(Ref(2), :x, +, 5))",
    "Core.modifyfield!(Ref(2), :x, +)",
    "Core.replacefield!(Ref(1), :x, 1, 9)",
    "Core.replacefield!(Ref(1), :x, 2, 9)",
    "Core.replacefield!(Ref(1), :x, 1, 9, :sequentially_consistent, :sequentially_consistent)",
    "Core.setfieldonce!(Ref(1), :x, 5)",
    "setfield!(Ref(1), :x, 2, :sequentially_consistent)",
    "getfield(Ref(1), :x, :sequentially_consistent)",
    # invoke / invokelatest: dedicated call paths in the interpreter
    "invoke(abs, Tuple{Int}, -3)",
    "invoke(+, Tuple{Int,Int}, 2, 3)",
    "invoke(abs, Tuple{Float64}, -3)",
    "Base.invokelatest(*, 6, 7)",
    # opaque closures: lower to :new_opaque_closure, a dedicated interpreter path
    "(Base.Experimental.@opaque x -> x + 1)(41)",
    "(Base.Experimental.@opaque (a, b) -> a * b)(6, 7)",
    # globals reflection
    "Core.getglobal(Base, :pi)",
    "Core.getglobal(Base, :definitely_not_a_name_xyz)",
    "isdefined(Base, :pi, :sequentially_consistent)",
    # misc barriers / asserts
    "Base.donotdelete(1)",
    "Base.inferencebarrier(3) + 1",
    "Base.compilerbarrier(:const, 1)",
    "Base.compilerbarrier(:type, 1)",
    "typeassert(1, Int)",
    "typeassert(1, String)",
]

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
        push!(opts, (2.0, :leaf), (1.5, :guardix), (1.0, :callvar), (0.8, :guarddiv), (0.6, :ternary),
              (1.4, :builtin))
        # guarded call with one deliberately wrong-typed argument: MethodError
        # construction / localmethtable miss, or an error deep inside the callee
        # propagating through interpreted frames
        !isempty(ctx.fns) && push!(opts, (0.8, :badcall))
    end
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
    kind = wpick(rng, opts)

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
        args = Ex[genex(ctx, p isa AnyT ? pick(rng, TySum[IntT, FloatT, StrT, BoolT]) : p) for p in fs.psums]
        return Ex(:callvar, fs.ret, v.name, args)
    elseif kind === :callfn
        f = pick(rng, fnsreturning(ctx, want))
        sig = pick(rng, f.sigs)
        args = Ex[genex(ctx, p isa AnyT ? pick(rng, TySum[IntT, FloatT, StrT, BoolT]) : p) for p in sig]
        # varargs method: sometimes append extra trailing args, occasionally splat a vector
        if f.vararg && rand(rng) < 0.5
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
        args = Ex[genex(ctx, p isa AnyT ? pick(rng, TySum[IntT, FloatT, StrT, BoolT]) : p) for p in sig]
        # pass a random subset of declared kwargs (all default to Int)
        chosen = [kw for kw in f.kwnames if rand(rng, Bool)]
        for kw in chosen
            push!(args, genex(ctx, IntT))
        end
        return Ex(:kwcall, f.ret, (f.name, chosen), args)
    elseif kind === :builtin
        return Ex(:guard, AnyT(), nothing, [Ex(:src, AnyT(), pick(rng, BUILTIN_PROBES))])
    elseif kind === :badcall
        f = pick(rng, ctx.fns)
        sig = pick(rng, f.sigs)
        args = Ex[genex(ctx, p isa AnyT ? pick(rng, TySum[IntT, FloatT, StrT, BoolT]) : p) for p in sig]
        idxs = [i for i in eachindex(sig) if sig[i] isa ConcT]
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
# Non-growable scalars only. Used for struct fields: a String field could be
# grown in place (x.f = string(x.f, x.f)) inside a looping/oft-called context,
# and structs have no per-field bound. Int/Float/Bool/Sym exercise field
# access, mutation, and dispatch fully without the memory risk.
const SCALAR_NONGROW = TySum[IntT, IntT, FloatT, FloatT, BoolT, SymT]

function newvarsum(ctx::Ctx)
    r = rand(ctx.rng)
    if !isempty(ctx.structs) && r < 0.12
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
    # control-flow exits; break/continue through try/finally is the :enter/:leave
    # and exception-frame-unwinding surface
    ctx.loopdepth > 0 && push!(opts, (1.0, :brk), (0.8, :cont))
    ctx.retsum !== nothing && push!(opts, (0.9, :ret))
    kind = wpick(rng, opts)

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
        declare!(ctx, VInfo(ivar, IntT))
        body = genex(ctx, eltsum)
        kids = hasfilter ? [body, genex(ctx, BoolT)] : [body]
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
        thenb = genblock(ctx, blockdepth)
        blocks = [thenb]
        haselse && push!(blocks, genblock(ctx, blockdepth))
        return St(:if, haselse; exs=[cond], blocks=blocks)
    elseif kind === :for
        ivar = freshname(ctx, "i")
        n = rand(rng, 0:ctx.cfg.maxloop)
        ctx.loopdepth += 1
        body = genblock(ctx, blockdepth; extra=[VInfo(ivar, IntT)])
        ctx.loopdepth -= 1
        return St(:for, (ivar, n); blocks=[body])
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
        attop = !inlocal(ctx)
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
        declare!(ctx, VInfo(ivar, IntT))
        rhs = genex(ctx, pick(rng, TySum[IntT, FloatT]))
        popscope!(ctx)
        return St(:loopundef, (ivar, xname, n, when); exs=[rhs])
    elseif kind === :typedlocal
        s = pick(rng, TySum[IntT, FloatT])
        rhs = genex(ctx, s)
        name = freshname(ctx, "t")
        st = St(:typedlocal, (name, s); exs=[rhs])
        declare!(ctx, VInfo(name, s))
        return st
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

function genblock(ctx::Ctx, blockdepth::Int; n::Int=blockn(ctx, blockdepth + 1),
                  extra::Vector{VInfo}=VInfo[])
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
    retsum = pick(rng, CONCRETE_MENU)
    pushscope!(ctx)
    for (pn, ps, _) in params
        declare!(ctx, VInfo(pn, ps))
    end
    vararg && declare!(ctx, VInfo(varargname, TupT(TySum[])))  # a Tuple; only used opaquely
    for (kn, _) in kwparams
        declare!(ctx, VInfo(kn, IntT))
    end
    wasinfunc, wasret, wasloop = ctx.infunc, ctx.retsum, ctx.loopdepth
    ctx.infunc = true
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
    fsums = TySum[pick(rng, SCALAR_NONGROW) for _ in 1:nf]
    ismutable = rand(rng, Bool)
    mask = ismutable ? [rand(ctx.rng) < 0.3 for _ in 1:nf] : fill(false, nf)
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
    return St(:fundef, (fi.name, params, retex.sum, Tuple{Symbol,Any}[], false, :_, 0);
              exs=[retex], blocks=[St[]])
end

# ---------------------------------------------------------------------------
# Whole programs

function genprogram(rng::AbstractRNG, cfg::Cfg=Cfg())::Program
    ctx = Ctx(rng, cfg)
    # pre: structs then globals (both live in module scope, scopes[1])
    pre = St[]
    for _ in 1:rand(rng, cfg.nstructs)
        push!(pre, genstructdef(ctx))
    end
    for _ in 1:rand(rng, cfg.nglobals)
        push!(pre, genglobal(ctx))
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
    # body: the `let` block
    pushscope!(ctx)
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
    popscope!(ctx)
    return Program(pre, fundefs, mid, body)
end
