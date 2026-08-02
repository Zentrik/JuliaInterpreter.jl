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
        name, _, _ = st.meta
        println(io, pad, String(name), " = ", render(st.exs[1]))
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
        fuelvar, fuel = st.meta
        fv = String(fuelvar)
        println(io, pad, fv, " = ", fuel)
        println(io, pad, "while ", render(st.exs[1]), " && (", fv, " > 0)")
        println(io, pad, "    ", fv, " -= 1")
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
        excvar, hasfinally = st.meta
        println(io, pad, "try")
        renderblock(st.blocks[1], io, ind + 4)
        println(io, pad, "catch ", String(excvar))
        renderblock(st.blocks[2], io, ind + 4)
        if hasfinally
            println(io, pad, "finally")
            renderblock(st.blocks[3], io, ind + 4)
        end
        println(io, pad, "end")
    elseif k === :fundef
        name, params, _ = st.meta
        plist = join([String(pn) * (typed ? "::" * typename(ps) : "") for (pn, ps, typed) in params], ", ")
        println(io, pad, "function ", String(name), "(", plist, ")")
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
    for fd in prog.fundefs
        render(fd, io, 0)
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
