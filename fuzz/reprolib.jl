# Minimal standalone differential runner used by findings/*/repro.jl.
# Deliberately independent of the generator: it needs only JuliaInterpreter.
# `reprorun(src)` runs `src` compiled and interpreted in fresh modules and
# prints both observation streams and outcomes.

using JuliaInterpreter
using Random

# Mirrors SETUP_SRC in fuzz/src/render.jl (kept in sync by hand so a repro stays
# standalone). Includes the determinism-unlock prelude: `using Random` (for
# previously written findings' `const __RNG__ = Xoshiro(...)`; new programs
# carry their own inline PRNG in the rendered text), the `__vtime__` virtual
# clock, and Dict/Set normalization.
const REPRO_SETUP = raw"""
using Random
const __OBS__ = Any[]
const __VTIME__ = Ref(0)
__vtime__() = (__VTIME__[] += 1)
function __fjnorm__(x)
    if x isa Union{Number, String, Symbol, Char, Nothing}
        return x
    elseif x isa Tuple
        return map(__fjnorm__, x)
    elseif x isa AbstractArray
        return Any[__fjnorm__(el) for el in x]
    elseif x isa AbstractDict
        return (:__dict, sort!(Any[(__fjnorm__(k), __fjnorm__(v)) for (k, v) in x]; by = p -> string(p[1])))
    elseif x isa AbstractSet
        return (:__set, sort!(Any[__fjnorm__(el) for el in x]; by = string))
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

# --- corpus certified-value repro (`--engine corpus`, certified findings) ---
#
# A corpus value finding is real code that passed self-agreement certification
# (determinism.md §6): the value oracle applies because the fragment is
# observationally deterministic on a fixed sandbox seed. Reproduction therefore
# has to (1) seed the RNG, (2) run each side, and (3) observe the fragment's
# comparable top-level bindings — real code does not call `__obs__` itself.
# Standalone copies of the harness's assigned-names / comparability logic
# (fuzz/src/corpus.jl), so a repro needs nothing but JuliaInterpreter + Random.

const REPRO_CORPUS_SEED = 0x00C0FFEE

function repro_assigned_names(ex::Expr)
    names = Symbol[]; seen = Set{Symbol}()
    add(n) = (n isa Symbol && !(n in seen)) && (push!(names, n); push!(seen, n); true)
    function target(@nospecialize(t))
        if t isa Symbol
            add(t)
        elseif t isa Expr && t.head === :tuple
            foreach(target, t.args)
        elseif t isa Expr && (t.head === :(::) || t.head === :ref)
            target(t.args[1])
        end
    end
    function scan(sts)
        for st in sts
            st isa LineNumberNode && continue
            if st isa Expr && (st.head === :toplevel || st.head === :block)
                scan(st.args)
            elseif st isa Expr && st.head === :(=)
                lhs = st.args[1]
                (lhs isa Expr && (lhs.head === :call || lhs.head === :where)) && continue
                target(lhs)
            elseif st isa Expr && st.head === :const && !isempty(st.args)
                inner = st.args[1]
                (inner isa Expr && inner.head === :(=)) && target(inner.args[1])
            end
        end
    end
    scan(ex.args)
    return names
end

function repro_comparable(@nospecialize(x), depth::Int=0)
    depth > 4 && return false
    (x isa Bool || x isa Number || x isa AbstractString || x isa Symbol ||
     x isa Char || x === nothing) && return true
    try
        if x isa Tuple
            return length(x) <= 64 && all(repro_comparable(e, depth + 1) for e in x)
        elseif x isa AbstractArray
            length(x) > 64 && return false
            for i in eachindex(x)
                (isassigned(x, i) && repro_comparable(x[i], depth + 1)) || return false
            end
            return true
        elseif x isa AbstractSet
            return length(x) <= 64 && all(repro_comparable(e, depth + 1) for e in x)
        elseif x isa AbstractDict
            return length(x) <= 64 &&
                   all(repro_comparable(k, depth + 1) && repro_comparable(v, depth + 1) for (k, v) in x)
        elseif x isa Pair
            return repro_comparable(x.first, depth + 1) && repro_comparable(x.second, depth + 1)
        end
    catch
        return false
    end
    return false
end

function repro_observe!(m::Module, names::Vector{Symbol})
    obsfn = Base.invokelatest(getglobal, m, :__obs__)
    for n in names
        Base.invokelatest(isdefined, m, n) || continue
        v = try
            Base.invokelatest(getglobal, m, n)
        catch
            continue
        end
        repro_comparable(v) || continue
        try
            Base.invokelatest(obsfn, v)
        catch
        end
    end
end

function reprocorpus(src::AbstractString; seed=REPRO_CORPUS_SEED)
    top = Meta.parseall(String(src))
    stmts = (top isa Expr && top.head === :toplevel) ? top.args : Any[top]
    isimport(s) = s isa Expr && (s.head === :using || s.head === :import)
    prelude = Any[s for s in stmts if isimport(s)]
    rest = Any[s for s in stmts if !(s isa LineNumberNode) && !isimport(s)]
    ex = Expr(:toplevel, rest...)
    names = repro_assigned_names(ex)

    function loadprelude(m)
        for st in prelude
            try
                Core.eval(m, st)
            catch
            end
        end
    end

    mref = repro_freshmodule(:CorpusRef); loadprelude(mref)
    Random.seed!(seed)
    refout = try
        for st in ex.args
            st isa LineNumberNode || Core.eval(mref, st)
        end
        (:done, nothing)
    catch err
        (:threw, err)
    end
    refout[1] === :done && repro_observe!(mref, names)
    refobs = copy(Base.invokelatest(getglobal, mref, :__OBS__))

    mint = repro_freshmodule(:CorpusInterp); loadprelude(mint)
    Random.seed!(seed)
    intout = try
        for (mod, frag) in Base.invokelatest(ExprSplitter, mint, ex)
            Base.invokelatest(JuliaInterpreter.finish_and_return!,
                              Base.invokelatest(Frame, mod, frag), true)
        end
        (:done, nothing)
    catch err
        (:threw, err)
    end
    intout[1] === :done && Base.invokelatest(repro_observe!, mint, names)
    intobs = copy(Base.invokelatest(getglobal, mint, :__OBS__))

    println("=== compiled (reference), seeded + certified ===")
    println("outcome: ", refout[1], refout[2] === nothing ? "" : " ($(sprint(showerror, refout[2])))")
    println("observations: ", refobs)
    println("=== interpreted ===")
    println("outcome: ", intout[1], intout[2] === nothing ? "" : " ($(sprint(showerror, intout[2])))")
    println("observations: ", intobs)
    agree = isequal(refobs, intobs) && refout[1] === intout[1] &&
            (refout[1] !== :threw || typeof(refout[2]) === typeof(intout[2]))
    println(agree ? "NO DIVERGENCE (bug may be fixed, or is budget-dependent)" : "DIVERGENCE REPRODUCED")
    return !agree
end

# --- walk-replaying repros (call, step, evalcode, corpus failure-mode) ------
#
# These findings are (src, seed) pairs: the seed replays target selection,
# argument synthesis, and/or the debug_command walk. That logic lives in the
# harness and a standalone copy would drift from it, so these repros load
# FuzzJI from its home next to this file instead of duplicating it. (The step,
# evalcode and failure-mode corpus repros previously fell back to `reprorun`,
# which never steps — so they under-reproduced their findings by construction;
# NEXT.md handoff item 4.)

function _repro_fuzzji()
    isdefined(Main, :FuzzJI) || Base.include(Main, joinpath(@__DIR__, "src", "FuzzJI.jl"))
    return getfield(Main, :FuzzJI)
end

function reprocall(src::AbstractString, callseed::Integer)
    FJ = _repro_fuzzji()
    r = Base.invokelatest(FJ.call_program, String(src); callseed=Int(callseed))
    if r === nothing
        println("program failed the parse gate — nothing to compare")
        return false
    end
    println(r.ncalls, " certified call(s) compared, ", length(r.verdicts), " divergence(s)")
    for v in r.verdicts
        println("  ", v.class, ": ", v.detail)
    end
    println(isempty(r.verdicts) ? "NO DIVERGENCE (bug may be fixed, or is walk-dependent)" :
                                  "DIVERGENCE REPRODUCED")
    return !isempty(r.verdicts)
end

# A step finding is (src, walkseed): replay the same random `debug_command`
# walk — breakpoint actions included — against plain interpretation of the same
# program, exactly as the campaign compared them. Defaults mirror
# `step_campaign`'s.
function reprostep(src::AbstractString, walkseed::Integer;
                   nstmts::Int=300_000, maxcmds::Int=4000, usebreakpoints::Bool=true)
    FJ = _repro_fuzzji()
    ex = Base.invokelatest(FJ.parsegate, String(src))
    if ex === nothing
        println("program failed the parse gate — nothing to compare")
        return false
    end
    plain = Base.invokelatest(FJ.run_interp, ex; nstmts,
                              interp=JuliaInterpreter.RecursiveInterpreter())
    st = Base.invokelatest(FJ.step_program, String(src);
                           walkseed=Int(walkseed), maxcmds, usebreakpoints)
    if st === nothing
        println("stepping run discarded — nothing to compare")
        return false
    end
    v = Base.invokelatest(FJ.classify_step, plain, st)
    println("plain interpretation: ", plain.status,
            "  stepped: ", st.status, " after ", st.ncommands, " command(s)")
    println("verdict: ", v.class, isempty(v.detail) ? "" : string(" — ", first(v.detail, 400)))
    found = Base.invokelatest(FJ.isfinding, v)::Bool
    println(found ? "DIVERGENCE REPRODUCED" : "NO DIVERGENCE (bug may be fixed, or is walk-dependent)")
    return found
end

# An eval_code finding is (src, walkseed): the seed replays the pause walk and
# probe selection. Defaults mirror `evalcode_campaign`'s.
function reproevalcode(src::AbstractString, walkseed::Integer;
                       nstmts::Int=300_000, pausesper::Int=25)
    FJ = _repro_fuzzji()
    o = Base.invokelatest(FJ.evalcode_probe, String(src);
                          walkseed=Int(walkseed), nstmts, pausesper)
    if o === nothing
        println("program was discarded — nothing to compare")
        return false
    end
    v = Base.invokelatest(FJ.evalverdict, o)
    println("verdict: ", v.class, isempty(v.detail) ? "" : string(" — ", first(v.detail, 400)))
    found = Base.invokelatest(FJ.isfinding, v)::Bool
    println(found ? "DIVERGENCE REPRODUCED" : "NO DIVERGENCE (bug may be fixed, or is walk-dependent)")
    return found
end

# A failure-mode corpus finding (mode `corpus`, as opposed to the certified
# `corpusvalue` handled by `reprocorpus` above) is real code plus a stepping
# walkseed: replay the reference-then-interpret-then-step pipeline the campaign
# ran. Defaults mirror `corpus_campaign`'s.
function reprocorpusstep(src::AbstractString, walkseed::Integer;
                         nstmts::Int=60_000, maxcmds::Int=1500)
    FJ = _repro_fuzzji()
    sp = Base.invokelatest(FJ.corpus_split, String(src))
    if sp === nothing
        println("no non-import statements — nothing to run")
        return false
    end
    case, prelude = sp
    r = Base.invokelatest(FJ.corpus_run, case, prelude; nstmts)
    o = r.status === :ok ?
        Base.invokelatest(FJ.corpus_step, case, r.prelude, Xoshiro(Int(walkseed)); maxcmds) : r
    v = Base.invokelatest(FJ.corpusverdict, o)
    println("plain run: ", r.status, "  final: ", o.status)
    println("verdict: ", v.class, isempty(v.detail) ? "" : string(" — ", first(v.detail, 400)))
    found = Base.invokelatest(FJ.isfinding, v)::Bool
    println(found ? "DIVERGENCE REPRODUCED" : "NO DIVERGENCE (bug may be fixed, or is walk-dependent)")
    return found
end

# --- ExprSplitter-axis repro (`--engine split` findings) -------------------
#
# The split axis's main verdict class is a difference in the *module tree*, not
# in the observation stream, so its reproducer has to compare the same thing the
# oracle did. A trimmed standalone copy of `modstate`/`normstate` from
# fuzz/src/splitfuzz.jl (this file stays independent of the generator on
# purpose: a repro must run with nothing but JuliaInterpreter).

const REPRO_SKIP = Set{Symbol}([:eval, :include, :__OBS__, :__obs__, :__fjnorm__,
                                :__VTIME__, :__vtime__, :__RNG__,
                                # inline-PRNG header (render.jl `rngheader`); identical on
                                # both sides by construction (__RNG__ kept for old repros)
                                :__LCG__, :__randu__, :__randint__, :__randrange__,
                                :__randbool__, :__randfloat__])

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
