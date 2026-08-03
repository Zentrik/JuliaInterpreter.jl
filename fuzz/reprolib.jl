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

# --- ExprSplitter-axis repro (`--engine split` findings) -------------------
#
# The split axis's main verdict class is a difference in the *module tree*, not
# in the observation stream, so its reproducer has to compare the same thing the
# oracle did. A trimmed standalone copy of `modstate`/`normstate` from
# fuzz/src/splitfuzz.jl (this file stays independent of the generator on
# purpose: a repro must run with nothing but JuliaInterpreter).

const REPRO_SKIP = Set{Symbol}([:eval, :include, :__OBS__, :__obs__, :__fjnorm__])

function repro_scrubname(@nospecialize(x))
    n = try
        String(nameof(x))
    catch
        return "__anon__"
    end
    return startswith(n, "#") ? "__anon__" : n
end

function repro_norm(@nospecialize(x), depth::Int=0)
    depth > 3 && return :__deep__
    (x isa Number || x isa AbstractString || x isa Symbol || x isa Char || x === nothing) &&
        return x isa AbstractString ? String(x) : x
    x isa Module && return Symbol("__module__:", nameof(x))
    x isa Type && return Symbol("__type__:", repro_scrubname(x))
    x isa Function && return Symbol("__fn__:", repro_scrubname(x))
    x isa Tuple && return map(el -> repro_norm(el, depth + 1), x)
    nf = try
        nfields(x)
    catch
        return Symbol("__obj__:", repro_scrubname(typeof(x)))
    end
    return Tuple(Any[Symbol("__obj__:", repro_scrubname(typeof(x)));
                     [isdefined(x, i) ? repro_norm(getfield(x, i), depth + 1) : :__undef_field__
                      for i in 1:min(nf, 8)]])
end

function repro_state!(out::Dict{String,Any}, m::Module, prefix::String, seen::Set{Module})
    m in seen && return out
    push!(seen, m)
    self = nameof(m)
    for n in sort(Base.invokelatest(names, m; all=true); by=String)
        s = String(n)
        (startswith(s, "#") || n in REPRO_SKIP || n === self) && continue
        path = isempty(prefix) ? s : string(prefix, ".", s)
        if !Base.invokelatest(isdefined, m, n)
            out[path] = :__declared_undefined__
            continue
        end
        v = Base.invokelatest(getglobal, m, n)
        if v isa Module && parentmodule(v) === m && v !== m
            out[path] = :__submodule__
            repro_state!(out, v, path, seen)
        else
            out[path] = repro_norm(v)
        end
    end
    return out
end
repro_state(m::Module) = repro_state!(Dict{String,Any}(), m, "", Set{Module}())

function reprosplit(src::AbstractString)
    ex = Meta.parseall(String(src))
    runside(m, f) = try
        f(m)
        (:done, nothing)
    catch err
        (:threw, err)
    end
    mref = repro_freshmodule(:SplitRef)
    refout = runside(mref, m -> for st in ex.args
        st isa LineNumberNode || Core.eval(m, st)
    end)
    # invokelatest: `ExprSplitter`/`Frame` expand macros at construction, and the
    # program's own macros are newer than this function's world.
    mint = repro_freshmodule(:SplitInterp)
    intout = runside(mint, m -> for (mod, frag) in Base.invokelatest(ExprSplitter, m, ex)
        Base.invokelatest(JuliaInterpreter.finish_and_return!,
                          Base.invokelatest(Frame, mod, frag), true)
    end)
    obs(m) = copy(Base.invokelatest(getglobal, m, :__OBS__))
    for (label, out, m) in (("compiled (reference)", refout, mref),
                            ("ExprSplitter + Frame", intout, mint))
        println("=== ", label, " ===")
        println("outcome: ", out[1], out[2] === nothing ? "" : " ($(sprint(showerror, out[2])))")
        println("observations: ", obs(m))
    end
    refst, intst = repro_state(mref), repro_state(mint)
    diffs = String[]
    for path in sort(collect(union(keys(refst), keys(intst))))
        hr, hi = haskey(refst, path), haskey(intst, path)
        if !hr || !hi
            push!(diffs, string(path, ": ", hr ? "eval=$(refst[path])" : "<absent on the eval side>",
                                " / ", hi ? "split=$(intst[path])" : "<absent on the split side>"))
        elseif !isequal(refst[path], intst[path]) || typeof(refst[path]) !== typeof(intst[path])
            push!(diffs, string(path, ": eval=", refst[path], " split=", intst[path]))
        end
    end
    println("=== module state (", length(refst), " names on the eval side, ",
            length(intst), " on the split side) ===")
    isempty(diffs) ? println("identical") : foreach(d -> println("  ", d), diffs)
    agree = isempty(diffs) && isequal(obs(mref), obs(mint)) && refout[1] === intout[1] &&
            (refout[1] !== :threw || typeof(refout[2]) === typeof(intout[2]))
    println(agree ? "NO DIVERGENCE (bug may be fixed, or is budget-dependent)" : "DIVERGENCE REPRODUCED")
    return !agree
end
