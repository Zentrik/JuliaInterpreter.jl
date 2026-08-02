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
        ivar, n = st.meta
        println(io, pad, "for ", String(ivar), " in 1:", n)
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
            base = String(pn) * (typed ? "::" * typename(ps) : "")
            # trailing `ndefaults` positional params get an Int default
            if ndefaults > 0 && i > length(params) - ndefaults
                base *= " = 0"
            end
            push!(pparts, base)
        end
        vararg && push!(pparts, String(varargname) * "...")
        plist = join(pparts, ", ")
        kwlist = isempty(kwparams) ? "" :
                 "; " * join([String(kn) * " = " * repr(kv) for (kn, kv) in kwparams], ", ")
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

function render(prog::Program)::String
    io = IOBuffer()
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
const __OBS__ = Any[]
function __fjnorm__(x)
    if x isa Union{Number, String, Symbol, Char, Nothing}
        return x
    elseif x isa Tuple
        return map(__fjnorm__, x)
    elseif x isa AbstractArray
        return Any[__fjnorm__(el) for el in x]
    elseif x isa Function
        return :__fn__
    elseif x isa Type
        return Symbol(string(x))
    else
        return Symbol(nameof(typeof(x)))
    end
end
__obs__(x) = (push!(__OBS__, __fjnorm__(x)); nothing)
"""
