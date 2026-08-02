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

const SETUP_EXPR = Meta.parseall(SETUP_SRC)

let counter = Ref(0)
    global function freshmodule()
        m = Module(Symbol("FJ", counter[] += 1))
        for st in SETUP_EXPR.args
            st isa LineNumberNode && continue
            Core.eval(m, st)
        end
        return m
    end
end

# invokelatest: the binding was created by `Core.eval` after this function's
# caller world; Julia 1.12's strict binding world-age rules apply.
getobs(m::Module) = copy(Base.invokelatest(getglobal, m, :__OBS__)::Vector{Any})

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

function run_interp(ex::Expr; nstmts::Int)::Outcome
    m = freshmodule()
    budget = nstmts
    try
        for (mod, frag) in ExprSplitter(m, ex)
            frame = Frame(mod, frag)
            while true
                ret, budget = evaluate_limited!(RecursiveInterpreter(), frame, budget, true)
                ret isa Aborted && return Outcome(:aborted, :none, getobs(m), "", "")
                ret isa Some && break
                @assert ret === nothing  # paused after a method definition; resume same frame
            end
        end
        return Outcome(:done, :none, getobs(m), "", "")
    catch err
        err isa AbortException && return Outcome(:aborted, :none, getobs(m), "", "")
        bt = sprint(Base.show_backtrace, catch_backtrace(); context=:limit => true)
        return Outcome(:threw, scrubexc(err), getobs(m), shortstr(err), first(bt, 3000))
    end
end

# nothing (not an Outcome pair) means the program was discarded pre-execution.
function run_both(src::String; nstmts::Int)
    ex = try
        Meta.parseall(src)
    catch
        return nothing
    end
    ex isa Expr && ex.head === :toplevel || return nothing
    lwr = try
        Meta.lower(Main, ex)
    catch
        return nothing
    end
    isexpr(lwr, :error) && return nothing
    isexpr(lwr, :incomplete) && return nothing
    ref = run_ref(ex)
    int = run_interp(ex; nstmts)
    return (ref, int)
end
