# Render the IR to Julia source text.
#
# Source text (not Expr trees) is the interchange format on purpose: the
# journal and repro files then contain literally the program that ran, and
# both sides parse the same text with `Meta.parseall` (file/hard-scope
# semantics, matching `include`). Every composite expression is
# parenthesized, so operator precedence can't diverge from the IR.

function render(e::Ex)::String
    k = e.kind
    if k === :lit
        v = e.meta
        v === nothing && return "nothing"
        if v isa Int && v < 0
            return "($(repr(v)))"
        end
        return repr(v)
    elseif k === :var
        return String(e.meta::Symbol)
    elseif k === :binop
        return "(" * render(e.kids[1]) * " " * String(e.meta::Symbol) * " " * render(e.kids[2]) * ")"
    elseif k === :prefix
        return "(" * String(e.meta::Symbol) * render(e.kids[1]) * ")"
    elseif k === :callb || k === :call
        return String(e.meta::Symbol) * "(" * join(map(render, e.kids), ", ") * ")"
    elseif k === :callvar
        return String(e.meta::Symbol) * "(" * join(map(render, e.kids), ", ") * ")"
    elseif k === :isa
        return "(" * render(e.kids[1]) * " isa " * (e.meta::String) * ")"
    elseif k === :andor
        return "(" * render(e.kids[1]) * " " * String(e.meta::Symbol) * " " * render(e.kids[2]) * ")"
    elseif k === :ternary
        return "(" * render(e.kids[1]) * " ? " * render(e.kids[2]) * " : " * render(e.kids[3]) * ")"
    elseif k === :tuple
        n = length(e.kids)
        inner = join(map(render, e.kids), ", ")
        return n == 1 ? "($inner,)" : "($inner)"
    elseif k === :vect
        prefix = e.sum isa VecT && (e.sum::VecT).elt isa AnyT ? "Any" : ""
        return prefix * "[" * join(map(render, e.kids), ", ") * "]"
    elseif k === :index
        return "(" * render(e.kids[1]) * ")[" * render(e.kids[2]) * "]"
    elseif k === :closure
        params = e.meta::Vector{Symbol}
        plist = join(String.(params), ", ")
        return "((" * plist * ") -> " * render(e.kids[1]) * ")"
    elseif k === :closuremut
        params, cap = e.meta
        plist = join(String.(params), ", ")
        capn = String(cap)
        return "((" * plist * ") -> (" * capn * " = " * render(e.kids[1]) * "; " * capn * "))"
    elseif k === :guard
        return "(try " * render(e.kids[1]) * " catch __e; (:__thrown, nameof(typeof(__e))) end)"
    elseif k === :src
        return e.meta::String
    elseif k === :probe
        # `spelling(args...)`. The spelling comes from the reflection
        # enumeration in probes.jl, so it is always a resolvable callee on the
        # Julia version generating the program; the caller wraps it in a :guard.
        #
        # Each argument is wrapped in `Base.compilerbarrier(:const, …)` unless
        # the slot must stay a bare literal (cast target types, atomic
        # orderings, module refs, the memoryref boundscheck — see
        # `probe_arg_mustbeliteral`). The barrier forces the compiled reference
        # to defer to the runtime builtin/intrinsic, matching the interpreter
        # and closing the constant-folding class-U false-positive window.
        spelling = e.meta::String
        parts = String[]
        for (i, kid) in enumerate(e.kids)
            s = render(kid)
            probe_arg_mustbeliteral(spelling, i, kid) ||
                (s = "Base.compilerbarrier(:const, " * s * ")")
            push!(parts, s)
        end
        return spelling * "(" * join(parts, ", ") * ")"
    elseif k === :rng
        # A draw from the program's own inline PRNG (e.g. `__randint__()`).
        # The PRNG state is seeded from a literal baked into both modules, so
        # both engines execute the same integer transitions and agree
        # bit-for-bit (see `rngheader`).
        return e.meta::String
    elseif k === :vtime
        # Monotone virtual clock (SETUP_SRC). Deterministic because both sides
        # call it the same number of times in the same order.
        return "__vtime__()"
    elseif k === :dictlit
        dt = e.sum::DictT
        ts = "Dict{" * juliatypestr(dt.k) * ", " * juliatypestr(dt.v) * "}"
        isempty(e.kids) && return ts * "()"
        pairs = String[]
        i = 1
        while i + 1 <= length(e.kids)
            push!(pairs, render(e.kids[i]) * " => " * render(e.kids[i + 1]))
            i += 2
        end
        return ts * "(" * join(pairs, ", ") * ")"
    elseif k === :setlit
        st = e.sum::SetT
        ts = "Set{" * juliatypestr(st.elt) * "}"
        isempty(e.kids) && return ts * "()"
        return ts * "([" * join(map(render, e.kids), ", ") * "])"
    elseif k === :splat
        return "(" * render(e.kids[1]) * ")..."
    elseif k === :prop
        return "(" * render(e.kids[1]) * ")." * String(e.meta::Symbol)
    elseif k === :aprop
        return "(@atomic (" * render(e.kids[1]) * ")." * String(e.meta::Symbol) * ")"
    elseif k === :kwcall
        fname, kwnames = e.meta
        npos = length(e.kids) - length(kwnames)
        posargs = [render(e.kids[i]) for i in 1:npos]
        kwargs = [String(kwnames[j]) * " = " * render(e.kids[npos + j]) for j in eachindex(kwnames)]
        allargs = isempty(kwargs) ? join(posargs, ", ") :
                  join(posargs, ", ") * (isempty(posargs) ? "" : ", ") * "; " * join(kwargs, ", ")
        return String(fname::Symbol) * "(" * allargs * ")"
    elseif k === :compr
        ivar, n, hasfilter = e.meta
        eltty = e.sum isa VecT ? typename((e.sum::VecT).elt) : "Any"
        base = eltty * "[" * render(e.kids[1]) * " for " * String(ivar) * " in 1:" * string(n)
        return hasfilter ? base * " if " * render(e.kids[2]) * "]" : base * "]"
    elseif k === :stackprobe
        # Not produced by any rule: a genuine, permanent interp/compiled
        # divergence (interpreter frames are visible in stacktrace()), used by
        # the selftest to prove the pipeline detects divergence end to end.
        return "any(fr -> occursin(\"interpret\", String(fr.file)), stacktrace())"
    end
    error("unreachable render kind $k")
end

function render(st::St, io::IO, ind::Int)
    pad = " "^ind
    k = st.kind
    if k === :assign
        name = st.meta[1]
        needsglobal = length(st.meta) >= 4 && st.meta[4]::Bool
        decl = length(st.meta) >= 5 ? st.meta[5]::Symbol : :none
        if decl === :const
            println(io, pad, "const ", String(name), " = ", render(st.exs[1]))
        elseif decl !== :none   # typed global declaration, e.g. `global g::Int64 = 0`
            println(io, pad, "global ", String(name), "::", String(decl), " = ", render(st.exs[1]))
        else
            println(io, pad, needsglobal ? "global " : "", String(name), " = ", render(st.exs[1]))
        end
    elseif k === :destructure
        # `a, b = rhs` — iterated assignment (Base.indexed_iterate lowering).
        # Reassigning module globals from local scope needs `global`, which
        # applies to every name on the left (all targets share globality by
        # construction, see the :destructure rule).
        names = st.meta[1]::Vector{Symbol}
        needsglobal = st.meta[4]::Bool
        println(io, pad, needsglobal ? "global " : "", join(String.(names), ", "),
                " = ", render(st.exs[1]))
    elseif k === :gendef
        # A pure @generated function: the generator branches on the argument
        # types only and interpolates static values into a trivial body. Two
        # spelling constraints keep the whole surface steppable:
        #  - the types are taken through *static parameters* (`where {T, U}`),
        #    never by inspecting the argument slots: `get_source` invokes the
        #    generator stub with the arg *names* (placeholder Symbols) and only
        #    the `env` carries real types, so `a <: Number` would throw
        #    TypeError the moment a debugger `:sg`s in — `T <: Number` is the
        #    steppable spelling (test/debug.jl's `generatedparams` pattern);
        #  - the generated body guards with `a isa Type`: the frame `:sg`
        #    enters is the generated body with *type-valued* argument slots
        #    (the stub runs the generator inside get_source and wraps its
        #    return in a lambda), so `a + b` there would be `+(Int64, Int64)`.
        #    The guard makes that frame return the baked literal instead —
        #    total in both worlds. Real calls never pass a Type, so program
        #    semantics are unchanged. See gengendef (rules.jl).
        gname, gk, gsym = st.meta
        n = String(gname)
        println(io, pad, "@generated function ", n, "(a::T, b::U) where {T, U}")
        println(io, pad, "    if T <: Number && U <: Number")
        println(io, pad, "        return :(a isa Type ? ", gk, " : a + b + \$(Int(sizeof(T))) + ", gk, ")")
        println(io, pad, "    elseif T <: AbstractString")
        println(io, pad, "        return :(a isa Type ? ", gk, " : length(a) + ", gk, ")")
        println(io, pad, "    else")
        println(io, pad, "        return :(:", String(gsym), ")")
        println(io, pad, "    end")
        println(io, pad, "end")
    elseif k === :structdef
        s = st.meta::StructT
        println(io, pad, s.ismutable ? "mutable struct " : "struct ", String(s.name))
        for (i, (fn, fs)) in enumerate(zip(s.fieldnames, s.fieldsums))
            println(io, pad, "    ", s.atomicmask[i] ? "@atomic " : "", String(fn), "::", typename(fs))
        end
        println(io, pad, "end")
    elseif k === :setprop
        vname, fname = st.meta[1], st.meta[2]
        atomic = length(st.meta) >= 3 && st.meta[3]::Bool
        println(io, pad, atomic ? "@atomic " : "", String(vname), ".", String(fname),
                " = ", render(st.exs[1]))
    elseif k === :amodify
        vname, fname, op = st.meta
        println(io, pad, "@atomic ", String(vname), ".", String(fname), " ", String(op),
                "= ", render(st.exs[1]))
    elseif k === :observe
        println(io, pad, "__obs__(", render(st.exs[1]), ")")
    elseif k === :if
        println(io, pad, "if ", render(st.exs[1]))
        renderblock(st.blocks[1], io, ind + 4)
        if st.meta::Bool
            println(io, pad, "else")
            renderblock(st.blocks[2], io, ind + 4)
        end
        println(io, pad, "end")
    elseif k === :for
        ivar, n = st.meta[1], st.meta[2]
        # A rand-derived trip count sits where a literal bound would (meta[3]);
        # it is capped at maxloop, so termination-by-construction is preserved —
        # the loop draws its *count* from the inline PRNG, not its fuel. Both sides draw
        # the same value, so iteration counts stay in lockstep.
        boundsrc = length(st.meta) >= 3 ? st.meta[3]::String : string(n)
        println(io, pad, "for ", String(ivar), " in 1:", boundsrc)
        renderblock(st.blocks[1], io, ind + 4)
        println(io, pad, "end")
    elseif k === :while
        fuelvar, fuel = st.meta[1], st.meta[2]
        # At module toplevel the counter is a global and the body is a soft
        # scope: an unqualified decrement would declare a new local and throw
        # UndefVarError, so the loop never runs its fuel down.
        attop = length(st.meta) >= 3 && st.meta[3]::Bool
        fv = String(fuelvar)
        println(io, pad, fv, " = ", fuel)
        println(io, pad, "while ", render(st.exs[1]), " && (", fv, " > 0)")
        println(io, pad, "    ", attop ? "global " : "", fv, " -= 1")
        renderblock(st.blocks[1], io, ind + 4)
        println(io, pad, "end")
    elseif k === :let
        bindings = st.meta::Vector{Tuple{Symbol,TySum}}
        blist = join([String(n) * " = " * render(rhs) for ((n, _), rhs) in zip(bindings, st.exs)], ", ")
        println(io, pad, "let ", blist)
        renderblock(st.blocks[1], io, ind + 4)
        println(io, pad, "end")
    elseif k === :dictset
        # d[key] = val — content-keyed, so this never throws (key type is always
        # valid); unguarded, unlike the vector setindex which can be out of range.
        println(io, pad, String(st.meta::Symbol), "[", render(st.exs[1]), "] = ", render(st.exs[2]))
    elseif k === :dictdel
        println(io, pad, "delete!(", String(st.meta::Symbol), ", ", render(st.exs[1]), ")")
    elseif k === :setpush
        println(io, pad, "push!(", String(st.meta::Symbol), ", ", render(st.exs[1]), ")")
    elseif k === :dictobs
        vname, proj = st.meta
        n = String(vname)
        if proj === :keys
            println(io, pad, "__obs__(keys(", n, "))")
        elseif proj === :values
            # sorted, so the observation is order-independent and comparable even
            # if two iteration orders ever differed; the whole-container observe
            # (proj :whole) already tests iteration order via __fjnorm__.
            println(io, pad, "__obs__(sort(collect(values(", n, "))))")
        elseif proj === :len
            println(io, pad, "__obs__(length(", n, "))")
        else   # :whole
            println(io, pad, "__obs__(", n, ")")
        end
    elseif k === :push
        println(io, pad, "push!(", String(st.meta::Symbol), ", ", render(st.exs[1]), ")")
    elseif k === :setindex
        # guarded, and the failure kind is itself an observation
        println(io, pad, "try; ", String(st.meta::Symbol), "[", render(st.exs[1]), "] = ", render(st.exs[2]),
                "; catch __e; __obs__((:__setfail, nameof(typeof(__e)))); end")
    elseif k === :alias
        name, old, _ = st.meta
        println(io, pad, String(name), " = ", String(old))
    elseif k === :try
        excvar, hasfinally = st.meta[1], st.meta[2]::Bool
        haselse = length(st.meta) >= 3 && st.meta[3]::Bool
        println(io, pad, "try")
        renderblock(st.blocks[1], io, ind + 4)
        println(io, pad, "catch ", String(excvar))
        renderblock(st.blocks[2], io, ind + 4)
        bi = 3
        if haselse
            println(io, pad, "else")
            renderblock(st.blocks[bi], io, ind + 4)
            bi += 1
        end
        if hasfinally
            println(io, pad, "finally")
            renderblock(st.blocks[bi], io, ind + 4)
        end
        println(io, pad, "end")
    elseif k === :brk
        println(io, pad, "(", render(st.exs[1]), ") && break")
    elseif k === :cont
        println(io, pad, "(", render(st.exs[1]), ") && continue")
    elseif k === :ret
        println(io, pad, "(", render(st.exs[1]), ") && return ", render(st.exs[2]))
    elseif k === :rethrowif
        println(io, pad, "(", render(st.exs[1]), ") && rethrow()")
    elseif k === :maybeundef
        name = String(st.meta::Symbol)
        println(io, pad, "if ", render(st.exs[1]))
        println(io, pad, "    ", name, " = ", render(st.exs[2]))
        println(io, pad, "end")
        println(io, pad, "__obs__(@isdefined(", name, "))")
        println(io, pad, "__obs__(try; ", name, "; catch __e; (:__undef, nameof(typeof(__e))) end)")
    elseif k === :loopundef
        # Per-iteration slot reset: xname is a fresh local every iteration, so
        # at iteration `when` it must be undefined again even though iteration
        # `when - 1` assigned it. Interpreter surface: NewvarNode handling and
        # Expr(:isdefined, slot).
        ivar, xname, n, when = st.meta
        iv, xv = String(ivar), String(xname)
        println(io, pad, "for ", iv, " in 1:", n)
        println(io, pad, "    if ", iv, " == ", when)
        println(io, pad, "        __obs__(@isdefined(", xv, "))")
        println(io, pad, "        __obs__(try; (:__v, ", xv, "); catch __e; (:__undef, nameof(typeof(__e))) end)")
        println(io, pad, "    end")
        println(io, pad, "    ", xv, " = ", render(st.exs[1]))
        println(io, pad, "end")
    elseif k === :typedlocal
        name, s = st.meta
        println(io, pad, "local ", String(name), "::", typename(s), " = ", render(st.exs[1]))
    elseif k === :fundef
        name, params = st.meta[1], st.meta[2]
        kwparams = length(st.meta) >= 4 ? st.meta[4] : Tuple{Symbol,Any}[]
        vararg = length(st.meta) >= 5 ? st.meta[5]::Bool : false
        varargname = length(st.meta) >= 6 ? st.meta[6]::Symbol : :_
        ndefaults = length(st.meta) >= 7 ? st.meta[7]::Int : 0
        pparts = String[]
        for (i, (pn, ps, typed)) in enumerate(params)
            base = if pn isa Symbol
                String(pn) * (typed ? "::" * typename(ps) : "")
            else
                # destructured tuple parameter: `(a, b)` / `(a, b)::Tuple{...}`
                # (juliatypestr for the full parameterization, so the annotated
                # form dispatches on the element types)
                "(" * join(String.(pn::Vector{Symbol}), ", ") * ")" *
                    (typed ? "::" * juliatypestr(ps) : "")
            end
            # trailing `ndefaults` positional params get an Int default (never
            # emitted for a destructured param — genfundef guarantees it, and a
            # scalar default could not be iterated)
            if ndefaults > 0 && i > length(params) - ndefaults && pn isa Symbol
                base *= " = 0"
            end
            push!(pparts, base)
        end
        vararg && push!(pparts, String(varargname) * "...")
        plist = join(pparts, ", ")
        # a kw default is a literal value, or a String of source text (a default
        # referencing an earlier parameter — the keyword-sorter shape)
        kwlist = isempty(kwparams) ? "" :
                 "; " * join([String(kn) * " = " * (kv isa String ? kv : repr(kv))
                              for (kn, kv) in kwparams], ", ")
        println(io, pad, "function ", String(name), "(", plist, kwlist, ")")
        renderblock(st.blocks[1], io, ind + 4)
        println(io, pad, "    return ", render(st.exs[1]))
        println(io, pad, "end")
    elseif k === :recdef
        # The depth clamp (n > 16) keeps termination-by-construction even when a
        # call site passes a huge Int: without it, `fr(typemax(Int), 0)` would
        # hang the compiled side and overflow the interpreter's host stack
        # (interpreted frames use far more native stack than compiled ones).
        name, _ = st.meta
        n = String(name)
        println(io, pad, "function ", n, "(n::Int64, acc::Int64)")
        println(io, pad, "    (n <= 0 || n > 16) && return acc")
        println(io, pad, "    return ", n, "(n - 1, acc + ", render(st.exs[1]), ")")
        println(io, pad, "end")
    else
        error("unreachable render stmt kind $k")
    end
end

function renderblock(sts::Vector{St}, io::IO, ind::Int)
    if isempty(sts)
        println(io, " "^ind, "nothing")
    else
        for st in sts
            render(st, io, ind)
        end
    end
end

# The per-program inline PRNG (determinism.md §3): SplitMix64 state + draw
# helpers, rendered into the program text itself with the seed as a literal.
#
# Why inline instead of `const __RNG__ = Xoshiro(seed)` + Base's `rand`: under
# RecursiveInterpreter each `rand(__RNG__, ...)` call interprets Base's entire
# Random machinery — thousands of statements per draw — and measured at the
# default 300k statement budget, 100% of programs containing `__RNG__`
# exhausted it (72/72; overall abort rate 70-72% vs ~1% before the RNG grammar
# landed), so the rec axis effectively never tested the feature. These helpers
# are a handful of integer/float intrinsics per draw, cost a few interpreted
# statements, and keep every property that mattered: bit-identical values on
# both engines, data-dependent control flow, seed baked as a literal.
#
# Why in the rendered program rather than SETUP_SRC: the state is per-*program*
# (each candidate seeds its own stream), and rendering the four one-liners
# alongside the const keeps programs fully self-contained — repros run
# standalone, ji.jl and reprolib need no plumbing, and freshmodule()'s shared
# compiled helpers (4cd92be) stay untouched. `SETUP_SRC` keeps `using Random`
# so previously written findings/repros (`const __RNG__ = Xoshiro(seed)`)
# still resolve.
function rngheader(seed::Int)::String
    return """
    const __LCG__ = Ref{UInt64}($(repr(UInt64(seed))))
    __randu__() = (__LCG__[] += 0x9e3779b97f4a7c15; z = __LCG__[]; z = xor(z, z >> 30) * 0xbf58476d1ce4e5b9; z = xor(z, z >> 27) * 0x94d049bb133111eb; xor(z, z >> 31))
    __randint__() = __randu__() % Int64
    __randrange__(lo::Int64, hi::Int64) = lo + (__randu__() % UInt64(hi - lo + 1)) % Int64
    __randbool__() = __randu__() % Bool
    __randfloat__() = Float64(__randu__() >> 11) * 0x1p-53
    """
end

function render(prog::Program)::String
    io = IOBuffer()
    # The per-program PRNG, as a literal seed baked identically into both
    # engines' source (determinism.md §3), helpers included — the program is
    # self-contained.
    prog.rngseed === nothing || print(io, rngheader(prog.rngseed))
    for st in prog.pre        # struct defs + module globals
        render(st, io, 0)
    end
    for fd in prog.fundefs
        render(fd, io, 0)
    end
    for st in prog.mid        # bare toplevel statements
        render(st, io, 0)
    end
    println(io, "let")
    renderblock(prog.body, io, 4)
    println(io, "end")
    return String(take!(io))
end

# Evaluated (compiled) into every fresh module before the program runs. The
# normalizer scrubs anything module- or identity-dependent so observations
# from the two modules are comparable with `isequal`.
const SETUP_SRC = raw"""
using Random   # kept for previously written findings/repros (`Xoshiro(seed)`);
               # new programs use the self-contained inline PRNG (`rngheader`)
const __OBS__ = Any[]
# Virtual monotone clock (determinism.md §3): deadline/elapsed-shaped control
# flow (`while __vtime__() < N`) without a real clock. Deterministic because
# both engines call it the same number of times in the same order.
const __VTIME__ = Ref(0)
__vtime__() = (__VTIME__[] += 1)
function __fjnorm__(x)
    if x isa String
        # `string(v)` of a program-defined struct embeds its module-qualified
        # type name (`Main.FJ95.S1(...)`) — the same manufactured divergence
        # the Type branch below strips, one level down, inside a String the
        # program observed. And `repr` of a Ptr/MemoryRef embeds the heap
        # address (`Ptr{Int64} @0x00007f...`), which legitimately differs
        # between the two engines' runs — normalize the address to `@0x0`
        # (both from finding step_divergence-7e03896b).
        return replace(x, string(@__MODULE__, ".") => "", r"@0x[0-9a-fA-F]+" => "@0x0")
    elseif x isa Union{Number, Symbol, Char, Nothing}
        return x
    elseif x isa Tuple
        return map(__fjnorm__, x)
    elseif x isa AbstractArray
        return Any[__fjnorm__(el) for el in x]
    elseif x isa AbstractDict
        # Content-keyed Dicts iterate identically across the two engines
        # (determinism.md §4), but sorting by the normalized key makes the
        # observation order-independent regardless — safe, and still full-content.
        return (:__dict, sort!(Any[(__fjnorm__(k), __fjnorm__(v)) for (k, v) in x]; by = p -> string(p[1])))
    elseif x isa AbstractSet
        return (:__set, sort!(Any[__fjnorm__(el) for el in x]; by = string))
    elseif x isa Function
        return :__fn__
    elseif x isa Type
        # `string(T)` is module-qualified, and the two sides run in differently
        # named fresh modules — so a type the program itself defined renders as
        # `Main.FJ95.M1.S` on one side and `Main.FJ96.M1.S` on the other, a
        # divergence manufactured entirely by the harness. Strip this module's
        # own prefix; the rest of the name (including type parameters, so
        # `Vector{Int}` and `Vector{Float64}` stay distinct) is preserved.
        return Symbol(replace(string(x), string(@__MODULE__, ".") => ""))
    elseif x isa Pair
        # Returned by modifyfield!/memoryrefmodify!; comparing the pair is
        # strictly more oracle data than comparing the type name.
        return (:__pair, __fjnorm__(first(x)), __fjnorm__(last(x)))
    elseif x isa NamedTuple
        return (:__nt, keys(x), map(__fjnorm__, Tuple(x)))
    elseif x isa Core.SimpleVector
        return (:__svec, map(__fjnorm__, Tuple(x)))
    else
        return Symbol(nameof(typeof(x)))
    end
end
__obs__(x) = (push!(__OBS__, __fjnorm__(x)); nothing)
"""
