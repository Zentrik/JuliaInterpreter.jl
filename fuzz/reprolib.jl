# Minimal standalone differential runner used by findings/*/repro.jl.
# Deliberately independent of the generator: it needs only JuliaInterpreter.
# `reprorun(src)` runs `src` compiled and interpreted in fresh modules and
# prints both observation streams and outcomes.

using JuliaInterpreter

const REPRO_SETUP = raw"""
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
        # module-qualified names differ between the two fresh modules; strip
        # this module's own prefix (see SETUP_SRC in fuzz/src/render.jl)
        return Symbol(replace(string(x), string(@__MODULE__, ".") => ""))
    else
        return Symbol(nameof(typeof(x)))
    end
end
__obs__(x) = (push!(__OBS__, __fjnorm__(x)); nothing)
"""

function repro_freshmodule(tag)
    m = Module(Symbol("Repro", tag))
    for st in Meta.parseall(REPRO_SETUP).args
        st isa LineNumberNode && continue
        Core.eval(m, st)
    end
    return m
end

# `compiled=true` replays the interpreted side in Compiled mode
# (NonRecursiveInterpreter: toplevel stepped, calls execute natively) — used by
# findings tagged `cmp-`.
function reprorun(src::AbstractString; compiled::Bool=false)
    ex = Meta.parseall(String(src))

    mref = repro_freshmodule(:Ref)
    refout = try
        for st in ex.args
            st isa LineNumberNode && continue
            Core.eval(mref, st)
        end
        (:done, nothing)
    catch err
        (:threw, err)
    end
    refobs = copy(Base.invokelatest(getglobal, mref, :__OBS__))

    interp = compiled ? JuliaInterpreter.NonRecursiveInterpreter() :
                        JuliaInterpreter.RecursiveInterpreter()
    mint = repro_freshmodule(:Interp)
    intout = try
        for (mod, frag) in ExprSplitter(mint, ex)
            JuliaInterpreter.finish_and_return!(interp, Frame(mod, frag), true)
        end
        (:done, nothing)
    catch err
        (:threw, err)
    end
    intobs = copy(Base.invokelatest(getglobal, mint, :__OBS__))

    println("=== compiled (reference) ===")
    println("outcome: ", refout[1], refout[2] === nothing ? "" : " ($(sprint(showerror, refout[2])))")
    println("observations: ", refobs)
    println("=== interpreted ===")
    println("outcome: ", intout[1], intout[2] === nothing ? "" : " ($(sprint(showerror, intout[2])))")
    println("observations: ", intobs)
    agree = isequal(refobs, intobs) &&
            refout[1] === intout[1] &&
            (refout[1] !== :threw || typeof(refout[2]) === typeof(intout[2]))
    println(agree ? "NO DIVERGENCE (bug may be fixed, or is budget-dependent)" : "DIVERGENCE REPRODUCED")
    return !agree
end
