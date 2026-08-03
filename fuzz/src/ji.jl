# Julia's BUILT-IN interpreter as a third, independent engine — the adjudicator
# of the three-way (four-engine) oracle (DESIGN.md oracle section; determinism.md
# §2, which is why a hypervisor is *not* the tool here).
#
# `run_ji` evaluates a candidate under `julia --compile=min` in a subprocess.
# `--compile=min` runs function bodies through Julia's own C interpreter instead
# of compiling them, which DEFERS the compile-time validation and constant
# folding the reference (compiled `Core.eval`) performs — the class-U checks
# (invalid atomic orderings, mismatched intrinsic operand types, ...) that make
# compiled Julia and *any* interpreter legitimately disagree. So JI's outcome
# matches what an interpreter produces, and comparing a SUT mode against JI tells
# the oracle whether a C-vs-mode divergence is a real JuliaInterpreter bug (the
# mode matches neither C nor JI) or a compiler-vs-interpreter difference (the
# mode matches JI). Verified: `Core.Intrinsics.atomic_fence(:bogus)` inside a
# compiled function throws ErrorException compiled but ConcurrencyViolationError
# under `--compile=min`, on both 1.11 and 1.12.
#
# Cost: this is a whole subprocess (julia startup + an interpreted run), so it is
# run LAZILY — only when a SUT mode has already diverged from C, which is rare by
# construction (same spirit as confirm-on-divergence). It runs UNBUDGETED, like
# reprolib: generated programs terminate by construction, so a wall-clock timeout
# is the only bound. On timeout, a nonzero exit, a subprocess crash, or a
# missing/garbled result the outcome is "unavailable" (`nothing`), and the oracle
# falls back to reporting the C-vs-mode divergence as it would without the
# three-way — a JI failure must never HIDE a real bug.

using Serialization

const JI_TIMEOUT = 60   # seconds; wall-clock bound on one JI subprocess

# The script the JI subprocess runs. It mirrors `run_ref` exactly — a fresh
# module carrying SETUP_SRC, then `Core.eval` of each toplevel statement — so the
# only difference from the reference is the `--compile=min` flag on the julia
# invocation. The result (status, scrubbed exception name, observation stream) is
# serialized to `outpath`; the parent deserializes it. Serialization round-trips
# the normalized observation values exactly (they are all base Julia types after
# `__fjnorm__`), so the parsed-back Outcome compares under `outcomeeq`/`obseq`
# just like an in-process one.
function ji_script(progpath::String, outpath::String)
    return """
    using Serialization
    const __SETUP__ = $(repr(SETUP_SRC))
    const __UNASSIGNED__ = $(repr(UNASSIGNED_OBS))
    function __run__()
        m = Module(:JIRun)
        for st in Meta.parseall(__SETUP__).args
            st isa LineNumberNode && continue
            Core.eval(m, st)
        end
        ex = Meta.parseall(read($(repr(progpath)), String))
        status = :done
        excname = :none
        try
            for st in ex.args
                st isa LineNumberNode && continue
                Core.eval(m, st)
            end
        catch err
            status = :threw
            excname = nameof(typeof(err))
        end
        raw = Base.invokelatest(getglobal, m, :__OBS__)::Vector{Any}
        obs = Vector{Any}(undef, length(raw))
        for i in eachindex(raw)
            obs[i] = isassigned(raw, i) ? raw[i] : __UNASSIGNED__
        end
        return (status, excname, obs)
    end
    serialize($(repr(outpath)), __run__())
    """
end

"""
    run_ji(src; nstmts, timeout) -> Outcome | nothing

Evaluate `src` under Julia's built-in interpreter (`julia --compile=min`) in a
subprocess and parse the result back into an `Outcome`. Returns `nothing` when
the engine is *unavailable* — a timeout, a subprocess crash, or an unparseable
result — which the oracle treats as "cannot adjudicate", falling back to
reporting the C-vs-mode divergence rather than hiding it.

`nstmts` is accepted for interface parity with `run_interp`/`run_ref` but is not
used: JI runs unbudgeted (see the file header). `timeout` is the wall-clock cap
in seconds.
"""
function run_ji(src::AbstractString; nstmts::Int=0, timeout::Real=JI_TIMEOUT)::Union{Outcome,Nothing}
    dir = mktempdir()
    try
        progpath = joinpath(dir, "prog.jl")
        write(progpath, src)
        outpath = joinpath(dir, "out.jls")
        scriptpath = joinpath(dir, "ji.jl")
        write(scriptpath, ji_script(progpath, outpath))
        # No project: SETUP_SRC needs only `using Random` (stdlib), so JI pays no
        # JuliaInterpreter precompile — and, deliberately, never loads the package
        # it is adjudicating. Base.julia_cmd() is the same Julia running the
        # harness, so JI compares the *same* build's compiled and interpreted
        # execution.
        base = `$(Base.julia_cmd()) --startup-file=no --compile=min $scriptpath`
        cmd = Sys.which("timeout") === nothing ? base :
              `timeout $(ceil(Int, timeout)) $base`
        p = try
            run(pipeline(ignorestatus(cmd), stdout=devnull, stderr=devnull))
        catch
            return nothing        # could not even spawn — unavailable
        end
        # A nonzero exit means the run did not complete normally (timeout=124,
        # signal death=128+N, or an internal error). The program's own throws are
        # caught inside the script, so a clean run always exits 0 and writes the
        # file; treat everything else as unavailable.
        (p.exitcode == 0 && p.termsignal == 0) || return nothing
        isfile(outpath) || return nothing
        res = try
            deserialize(outpath)
        catch
            return nothing
        end
        (res isa Tuple && length(res) == 3 && res[1] isa Symbol && res[2] isa Symbol) ||
            return nothing
        status, excname, obs = res
        obs isa Vector{Any} || (obs = Vector{Any}(collect(obs)))
        return Outcome(status, excname, obs, "", "")
    finally
        rm(dir; recursive=true, force=true)
    end
end
