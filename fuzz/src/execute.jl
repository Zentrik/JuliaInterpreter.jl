# Differential execution: the same source text runs compiled (Core.eval, the
# reference) and interpreted (ExprSplitter + Frame, the system under test) in
# two fresh modules, and everything observable is collected for comparison.
#
# The budgeted executor is a trimmed port of `evaluate_limited!` from
# ../test/utils.jl (breakpoint plumbing and line-info reporting dropped):
# generated programs terminate by construction, so budget exhaustion on the
# interpreted side is signal, not noise.

using JuliaInterpreter
using JuliaInterpreter: Frame, Interpreter, RecursiveInterpreter, NonRecursiveInterpreter,
                        finish_and_return!, evaluate_call!, step_expr!,
                        do_assignment!, SSAValue, pc_expr, handle_err, get_return,
                        moduleof, is_return, is_methoddef3, recycle
using Base.Meta: isexpr

struct Aborted end   # statement budget exhausted

struct AbortException <: Exception end

mutable struct LimitedExec <: Interpreter
    nstmts::Int
end

function evaluate_limited!(interp::Interpreter, frame::Frame, nstmts::Int, istoplevel::Bool=false)
    limited_interp = LimitedExec(nstmts)
    pc = frame.pc
    while nstmts > 0
        istoplevel && (frame.world = Base.get_world_counter())
        stmt = pc_expr(frame, pc)
        if isa(stmt, Expr)
            if stmt.head === :call && !isa(interp, NonRecursiveInterpreter)
                limited_interp.nstmts = nstmts
                local new_pc
                try
                    rhs = evaluate_call!(limited_interp, frame, stmt)
                    isa(rhs, Aborted) && return rhs, limited_interp.nstmts
                    do_assignment!(frame, SSAValue(pc), rhs)
                    new_pc = pc + 1
                catch err
                    err isa AbortException && rethrow()
                    new_pc = handle_err(interp, frame, err)
                end
                nstmts = limited_interp.nstmts
            elseif stmt.head === :(=) && isexpr(stmt.args[2], :call) && !isa(interp, NonRecursiveInterpreter)
                limited_interp.nstmts = nstmts
                local new_pc
                try
                    rhs = evaluate_call!(limited_interp, frame, stmt.args[2])
                    isa(rhs, Aborted) && return rhs, limited_interp.nstmts
                    do_assignment!(frame, stmt.args[1], rhs)
                    new_pc = pc + 1
                catch err
                    err isa AbortException && rethrow()
                    new_pc = handle_err(interp, frame, err)
                end
                nstmts = limited_interp.nstmts
            elseif istoplevel && stmt.head === :thunk
                code = stmt.args[1]
                if length(code.code) == 1 && is_return(code.code[end]) && isexpr(code.code[end].val, :method)
                    new_pc = pc + 1
                else
                    limited_interp.nstmts = nstmts
                    newframe = Frame(moduleof(frame), stmt.args[1]::Core.CodeInfo)
                    ret = finish_and_return!(limited_interp, newframe, true)
                    isa(ret, Aborted) && return ret, limited_interp.nstmts
                    recycle(newframe)
                    frame.pc = pc + 1
                    return nothing, limited_interp.nstmts   # thunks may define methods: return to toplevel
                end
            elseif istoplevel && is_methoddef3(stmt)
                step_expr!(interp, frame, stmt, istoplevel)
                frame.pc = pc + 1
                return nothing, nstmts - 1
            else
                new_pc = step_expr!(interp, frame, stmt, istoplevel)
                nstmts -= 1
            end
        else
            new_pc = step_expr!(interp, frame, stmt, istoplevel)
            nstmts -= 1
        end
        new_pc === nothing && break
        pc = frame.pc = new_pc
    end
    stmt = pc_expr(frame, pc)
    if nstmts <= 0 && !is_return(stmt)
        return Aborted(), nstmts
    end
    return Some{Any}(get_return(frame)), nstmts
end

function JuliaInterpreter.finish_and_return!(interp::LimitedExec, newframe::Frame, istoplevel::Bool)
    ret, nleft = evaluate_limited!(interp, newframe, interp.nstmts, istoplevel)
    interp.nstmts = nleft
    isa(ret, Aborted) && throw(AbortException())
    return something(ret)
end

# ---------------------------------------------------------------------------

struct Outcome
    status::Symbol      # :done | :threw | :aborted
    excname::Symbol     # scrubbed exception type name (:none if :done/:aborted)
    obs::Vector{Any}
    errstr::String      # showerror output, for reports (never compared)
    btstr::String       # interpreted-side backtrace, for triage (never compared)
end

# The harness's own load state, captured at load time. A corpus fragment is real
# code and can mutate global load state (`LOAD_PATH`, the active project); the
# corpus axis's next `freshmodule` then can't resolve `using Random` in SETUP
# and the whole campaign dies with "Package Random not found". Restore the
# known-good load path before each fresh module so no fragment's damage leaks
# past the case that caused it. (Harmless for the generated axes, which never
# touch load state.)
const HARNESS_LOAD_PATH = copy(LOAD_PATH)

# Shared implementations of the SETUP_SRC helpers (NEXT.md item 8).
#
# SETUP_SRC remains the *specification* of the per-module prelude — ji.jl
# evaluates it verbatim in the JI subprocess and reprolib.jl mirrors it — but
# evaluating it into every fresh module made the compiled engines re-JIT it per
# candidate: each module got its own generic `__fjnorm__`/`__obs__`/`__vtime__`,
# so the reference paid their compilation on every case, and worse, the
# per-module `__fjnorm__` re-specialized on every *program-defined struct type*
# it observed (fresh types per candidate, fresh methods per module — nothing
# ever warm). Measured at ~35-40% of native-axis per-candidate cost.
#
# Instead the helpers are defined once here as callable structs parameterized by
# the module's own observation vector, clock and name prefix, and `freshmodule`
# binds *instances* under the same names. `@nospecialize` keeps `fjnorm` at one
# compiled method total instead of one per observed type. Subtypes of `Function`
# so `isa Function` checks (e.g. `__fjnorm__`'s own Function branch, the split
# axis's `normstate`) see what SETUP_SRC's generic functions were.
#
# Behavioral equivalence with SETUP_SRC evaluated verbatim is asserted by the
# selftest ("freshmodule prelude matches SETUP_SRC").
function fjnorm(@nospecialize(x), prefix::String)
    if x isa String
        # `string(v)` of a program-defined struct embeds its module-qualified
        # type name — strip this module's own prefix, same trick as the Type
        # branch — and `repr` of a Ptr/MemoryRef embeds the heap address,
        # which legitimately differs per run: normalize it to `@0x0`
        # (both from finding step_divergence-7e03896b).
        return replace(x, prefix => "", r"@0x[0-9a-fA-F]+" => "@0x0")
    elseif x isa Union{Number, Symbol, Char, Nothing}
        return x
    elseif x isa Tuple
        return map(el -> fjnorm(el, prefix), x)
    elseif x isa AbstractArray
        return Any[fjnorm(el, prefix) for el in x]
    elseif x isa AbstractDict
        # Content-keyed Dicts iterate identically across the two engines
        # (determinism.md §4), but sorting by the normalized key makes the
        # observation order-independent regardless — safe, and still full-content.
        return (:__dict, sort!(Any[(fjnorm(k, prefix), fjnorm(v, prefix)) for (k, v) in x]; by = p -> string(p[1])))
    elseif x isa AbstractSet
        return (:__set, sort!(Any[fjnorm(el, prefix) for el in x]; by = string))
    elseif x isa Function
        return :__fn__
    elseif x isa Type
        # `string(T)` is module-qualified, and the two sides run in differently
        # named fresh modules — strip this module's own prefix (see SETUP_SRC).
        return Symbol(replace(string(x), prefix => ""))
    elseif x isa Pair
        return (:__pair, fjnorm(first(x), prefix), fjnorm(last(x), prefix))
    elseif x isa NamedTuple
        return (:__nt, keys(x), map(el -> fjnorm(el, prefix), Tuple(x)))
    elseif x isa Core.SimpleVector
        return (:__svec, map(el -> fjnorm(el, prefix), Tuple(x)))
    else
        return Symbol(nameof(typeof(x)))
    end
end

struct FJNorm <: Function
    prefix::String
end
(f::FJNorm)(@nospecialize(x)) = fjnorm(x, f.prefix)

struct FJObs <: Function
    obs::Vector{Any}
    prefix::String
end
(f::FJObs)(@nospecialize(x)) = (push!(f.obs, fjnorm(x, f.prefix)); nothing)

struct FJVTime <: Function
    counter::Base.RefValue{Int}
end
(f::FJVTime)() = (f.counter[] += 1)

let counter = Ref(0)
    global function freshmodule()
        if LOAD_PATH != HARNESS_LOAD_PATH
            copy!(LOAD_PATH, HARNESS_LOAD_PATH)
        end
        m = Module(Symbol("FJ", counter[] += 1))
        # `string(m, ".")` here == `string(@__MODULE__, ".")` evaluated in m,
        # which is what SETUP_SRC's `__fjnorm__` strips from type names.
        prefix = string(m, ".")
        obs = Any[]
        vtime = Ref(0)
        Core.eval(m, :(using Random))
        Core.eval(m, :(const __OBS__ = $obs))
        Core.eval(m, :(const __VTIME__ = $vtime))
        Core.eval(m, :(const __vtime__ = $(FJVTime(vtime))))
        Core.eval(m, :(const __fjnorm__ = $(FJNorm(prefix))))
        Core.eval(m, :(const __obs__ = $(FJObs(obs, prefix))))
        return m
    end
end

# invokelatest: the binding was created by `Core.eval` after this function's
# caller world; Julia 1.12's strict binding world-age rules apply.
#
# Slots can be *unassigned*, not merely absent: `push!` grows the array and then
# stores into the new slot, so an interpretation that stops in between — budget
# exhaustion, or an exception thrown mid-`push!` — leaves a live element that
# was never written. Reading one throws UndefRefError, which took down a whole
# campaign batch from inside the comparator. Substitute a sentinel here, at the
# single point where observations enter the harness, so every consumer is safe:
# it compares equal to itself (both sides interrupted the same way agree) and
# unequal to any real value (one side producing a value where the other did not
# is a genuine difference).
const UNASSIGNED_OBS = :__fj_unassigned__

function getobs(m::Module)
    raw = Base.invokelatest(getglobal, m, :__OBS__)::Vector{Any}
    out = Vector{Any}(undef, length(raw))
    for i in eachindex(raw)
        out[i] = isassigned(raw, i) ? raw[i] : UNASSIGNED_OBS
    end
    return out
end

# An aborted run can be interrupted *mid-`push!`* of its last observation:
# `__obs__` grows `__OBS__` and then stores, and the statement budget can hit
# between the two, leaving a trailing unassigned slot. That slot is the abort
# boundary, not a real observation — but the reference (which never aborts) has
# a genuine value at that index, so comparing them reads as a `value_divergence`
# where nothing diverged. Trim trailing sentinels from an aborted stream so the
# oracle compares only completed observations. Only trailing ones, and only for
# aborted runs: a *completed* run that left a slot unassigned (the classic
# `push!`-grow-then-store interpreter bug) is a real divergence and is kept.
function trimabortedobs(obs::Vector{Any})
    n = length(obs)
    while n > 0 && obs[n] === UNASSIGNED_OBS
        n -= 1
    end
    return n == length(obs) ? obs : obs[1:n]
end

scrubexc(err) = nameof(typeof(err))

shortstr(err) = first(sprint(showerror, err; context=:limit => true), 500)

function run_ref(ex::Expr)::Outcome
    m = freshmodule()
    try
        for st in ex.args
            st isa LineNumberNode && continue
            Core.eval(m, st)
        end
        return Outcome(:done, :none, getobs(m), "", "")
    catch err
        return Outcome(:threw, scrubexc(err), getobs(m), shortstr(err), "")
    end
end

function run_interp(ex::Expr; nstmts::Int, interp::Interpreter=RecursiveInterpreter())::Outcome
    m = freshmodule()
    budget = nstmts
    try
        for (mod, frag) in ExprSplitter(m, ex)
            frame = Frame(mod, frag)
            while true
                ret, budget = evaluate_limited!(interp, frame, budget, true)
                ret isa Aborted && return Outcome(:aborted, :none, trimabortedobs(getobs(m)), "", "")
                ret isa Some && break
                @assert ret === nothing  # paused after a method definition; resume same frame
            end
        end
        return Outcome(:done, :none, getobs(m), "", "")
    catch err
        err isa AbortException && return Outcome(:aborted, :none, trimabortedobs(getobs(m)), "", "")
        bt = sprint(Base.show_backtrace, catch_backtrace(); context=:limit => true)
        return Outcome(:threw, scrubexc(err), getobs(m), shortstr(err), first(bt, 3000))
    end
end

# The two interpreter configurations under test. :rec interprets everything
# reachable (RecursiveInterpreter); :cmp is Compiled mode
# (NonRecursiveInterpreter) — toplevel statements are stepped by the
# interpreter but calls execute natively, a materially different path through
# evaluate_call!/builtin dispatch.
modeinterp(mode::Symbol) =
    mode === :rec ? RecursiveInterpreter() :
    mode === :cmp ? NonRecursiveInterpreter() :
    error("unknown interp mode $mode (expected :rec | :cmp)")

# Parse + lowering validity gate; returns the toplevel Expr or nothing.
function parsegate(src::String)
    ex = try
        Meta.parseall(src)
    catch
        return nothing
    end
    ex isa Expr && ex.head === :toplevel || return nothing
    # Lower each toplevel statement separately, because that is how both sides
    # actually evaluate the program: `Core.eval` per statement on the reference
    # side, one ExprSplitter fragment at a time on the interpreted side.
    # Lowering the whole `:toplevel` in one go does not surface a scope error
    # inside an individual statement, so a program that cannot lower would slip
    # through the gate and then fail on both sides — with *different* exception
    # types (ErrorException from Core.eval, ArgumentError from ExprSplitter),
    # which the comparator then reports as an exception divergence. Observed
    # producing 32 such reports in one run.
    for st in ex.args
        st isa LineNumberNode && continue
        lwr = try
            Meta.lower(Main, st)
        catch
            return nothing
        end
        (isexpr(lwr, :error) || isexpr(lwr, :incomplete)) && return nothing
    end
    return ex
end

# nothing (not an Outcome pair) means the program was discarded pre-execution.
function run_both(src::String; nstmts::Int, interp::Interpreter=RecursiveInterpreter())
    ex = parsegate(src)
    ex === nothing && return nothing
    ref = run_ref(ex)
    int = run_interp(ex; nstmts, interp)
    return (ref, int)
end

# Run the reference once and the interpreted side once per mode.
# Returns nothing (discarded) or (ref, [(mode, Outcome), ...]).
#
# One run of each side is what the *oracle* consumes; it is not what a *finding*
# is allowed to rest on. The confirm-on-divergence gate (`confirm`/`confirmed`,
# classify.jl) re-runs each side before any divergence is reported.
function run_all(src::String; nstmts::Int, modes::Tuple=(:rec, :cmp))
    ex = parsegate(src)
    ex === nothing && return nothing
    ref = run_ref(ex)
    return (ref, [(m, run_interp(ex; nstmts, interp=modeinterp(m))) for m in modes])
end
