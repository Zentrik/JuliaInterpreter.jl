# Semantic coverage of the interpreter (NEXT.md item 2, stage one).
#
#   julia --project=fuzz fuzz/coverage.jl [--n N] [--seed S] [--shards K]
#                                         [--modes rec,cmp|both|rec|cmp]
#                                         [--engine native,step,evalcode,corpus]
#                                         [--out PATH] [--slowdown] [--keep] [--reuse]
#                                         [--accumulate] [--big] [--budget N] [--extra FLAG]
#
# --keep leaves the .cov files and shard logs in place; --accumulate then adds a
# second campaign (use a fresh --seed) to the same picture, and --reuse
# re-reports from what is already on disk without running anything.
#
# `--engine` and `--modes` take comma lists: one shard *group* per (engine, mode)
# pair, `--shards` shards per group, `--n` candidates per shard. Every group uses
# the same seed ranges, so "hit under rec but not cmp" compares the same programs.
# The report is the union; the per-mode and per-engine tables are the differences.
#
# `metrics.jl` measures what the generator *produces* without executing it. This
# measures what a campaign actually *reaches* inside JuliaInterpreter — which is
# the question that matters, and the one that replaces guessing about grammar
# gaps with data. Same discipline as metrics.jl: measure the system, don't
# believe the generator.
#
# How it works — deliberately zero instrumentation of the interpreter:
#
#   1. spawn `julia --code-coverage=@<repo>/src --project=fuzz fuzz/run.jl ...`
#      subprocesses (one per shard, run concurrently; `@<dir>` keeps the harness's
#      own files out of it, so only JuliaInterpreter's src/ is measured — coverage
#      of the Base code the interpreter *walks through* is not the question);
#   2. julia drops one `<src>/<file>.jl.<pid>.cov` per source file at exit, one
#      count-or-`-` column per source line. Parse those directly — no Coverage.jl
#      dependency, the format is three lines of regex;
#   3. map never-executed lines back onto (a) the `f === <builtin>` dispatch arms
#      of `maybe_evaluate_builtin`, which is the headline report, and (b) the
#      enclosing function of every other source line;
#   4. write `fuzz/coverage-report.md`; delete the .cov files.
#
# Reading a count column, exactly (julia's `src/coverage.cpp`):
#
#   `-`  no counter was ever allocated for this line. Either the line is not
#        executable (blank/comment/`end`), or *no method covering it was ever
#        codegen'd* in the campaign. A whole function of `-` therefore means
#        "never compiled", which is a *stronger* never-hit signal than 0, not a
#        weaker one — but the two cannot be told apart from a comment without
#        the syntactic mapping this script does.
#   `0`  a counter exists (codegen emitted the line) and it never fired.
#   `k`  executed k times.
#
# Two traps worth knowing before reading the report:
#
#   - The count on an `elseif f === foo` *test* line is how often the test was
#     *reached*, not how often it matched — every call to `maybe_evaluate_builtin`
#     walks the chain. Whether an arm was *taken* is decided by its body lines,
#     which is what this script does.
#   - Arms compiled out by `@static` on this julia version still carry counters
#     and read as never-hit. This script evaluates each arm's `@static` guard in
#     the `JuliaInterpreter` module and reports those arms as ABSENT, so the
#     never-hit list contains only arms that exist in the running build.

const REPO    = normpath(joinpath(@__DIR__, ".."))
const SRCDIR  = joinpath(REPO, "src")
const FUZZDIR = @__DIR__
# `Libc.strftime` rather than the Dates stdlib: a timestamp is not worth a dep.
const RUNSTAMP = Libc.strftime("%Y-%m-%d %H:%M %Z", time())

# ----------------------------------------------------------------- CLI

function parseargs(args)
    o = Dict{String,Any}("n" => 200, "seed" => 1, "shards" => 1, "modes" => "both",
                         "engine" => "native", "out" => joinpath(FUZZDIR, "coverage-report.md"),
                         "keep" => false, "slowdown" => false, "big" => false,
                         "budget" => 300_000, "extra" => String[], "reuse" => false,
                         "accumulate" => false, "note" => "")
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--n"                 # candidates per shard
            o["n"] = parse(Int, args[i += 1])
        elseif a == "--seed"          # base seed; shard g of every mode uses seed + (g-1)*n
            o["seed"] = parse(Int, args[i += 1])
        elseif a == "--shards"        # concurrent subprocesses *per mode*
            o["shards"] = parse(Int, args[i += 1])
        elseif a == "--modes"         # comma list: each entry is one run.jl --modes value
            o["modes"] = args[i += 1]
        elseif a == "--engine"        # native (default) | step | evalcode | corpus | supposition
            o["engine"] = args[i += 1]
        elseif a == "--budget"
            o["budget"] = parse(Int, args[i += 1])
        elseif a == "--out"
            o["out"] = args[i += 1]
        elseif a == "--big"           # pass --big through to the generator
            o["big"] = true
        elseif a == "--keep"          # keep the .cov files and shard logs
            o["keep"] = true
        elseif a == "--slowdown"      # calibrate the coverage tax (extra ~2 min)
            o["slowdown"] = true
        elseif a == "--reuse"         # re-report from the .cov files already on disk
            o["reuse"] = true         # (needs a previous --keep run)
        elseif a == "--accumulate"    # add this campaign to the .cov already on disk
            o["accumulate"] = true    # (use a fresh --seed range) instead of replacing it
        elseif a == "--extra"         # verbatim extra flag for run.jl (repeatable)
            push!(o["extra"], args[i += 1])
        elseif a == "--note"          # free-text row in the report's campaign table
            o["note"] = args[i += 1]
        else
            error("unknown argument $a")
        end
        i += 1
    end
    return o
end

# ----------------------------------------------------------- .cov parsing

# One count column per source line. `-1` stands for "no counter" (the `-` column).
function parsecov(path::String)
    counts = Int[]
    for line in eachline(path)
        m = match(r"^ *(-|[0-9]+)(?: |$)", line)
        push!(counts, m === nothing ? -1 : (m.captures[1] == "-" ? -1 : parse(Int, m.captures[1])))
    end
    return counts
end

# Merge b into a: counts add, "no counter" loses to any counter.
function mergecov!(a::Vector{Int}, b::Vector{Int})
    length(a) < length(b) && append!(a, fill(-1, length(b) - length(a)))
    for i in eachindex(b)
        b[i] < 0 && continue
        a[i] = a[i] < 0 ? b[i] : a[i] + b[i]
    end
    return a
end

mergecov!(a::Dict{String,Vector{Int}}, b::Dict{String,Vector{Int}}) =
    (for (f, c) in b; mergecov!(get!(a, f, Int[]), c); end; a)

# Collect `<src>/<file>.jl.<pid>.cov` written since the campaign started, keyed
# by source basename. `pidsel` restricts to a set of pids (per-mode attribution);
# `nothing` takes everything. Returns (coverage, pids-seen).
function harvest(pidsel::Union{Nothing,Set{Int}}=nothing)
    cov = Dict{String,Vector{Int}}()
    seen = Set{Int}()
    for f in readdir(SRCDIR)
        m = match(r"^(.*\.jl)\.([0-9]+)\.cov$", f)
        m === nothing && continue
        pid = parse(Int, m.captures[2])
        push!(seen, pid)
        (pidsel === nothing || pid in pidsel) || continue
        mergecov!(get!(cov, m.captures[1], Int[]), parsecov(joinpath(SRCDIR, f)))
    end
    return cov, seen
end

# .cov files land next to the sources; they are gitignored but not welcome.
# Only ever delete the pid-suffixed ones — `test/code_coverage/coverage_example.jl.cov`
# is a tracked test fixture with no pid, and must survive.
function sweepcov(; verbose=true, pid::Union{Nothing,Int}=nothing)
    pat = pid === nothing ? r"\.jl\.[0-9]+\.cov$" : Regex("\\.jl\\.$pid\\.cov\$")
    n = 0
    for (root, _, files) in walkdir(REPO)
        occursin(joinpath(REPO, ".git"), root) && continue
        for f in files
            if match(pat, f) !== nothing
                rm(joinpath(root, f)); n += 1
            end
        end
    end
    verbose && n > 0 && @info "removed $n .cov files"
    return n
end

# --reuse re-reports from .cov files already on disk, which is only worth doing
# if the pid→(engine, mode) map survives with them — otherwise every per-mode and
# per-engine subset silently becomes the whole set. Kept out of the repo tree.
const SHARDMAP = joinpath(tempdir(), "fuzzji-covshards.txt")

writeshardmap(rows) = open(SHARDMAP, "w") do io
    for r in rows
        println(io, r.pid, "\t", r.engine, "\t", r.mode, "\t", r.seed, "\t", r.n, "\t",
                    r.journaled, "\t", r.exitcode)
    end
end

function readshardmap()
    isfile(SHARDMAP) || return nothing
    rows = NamedTuple[]
    for l in eachline(SHARDMAP)
        f = split(l, '\t')
        length(f) == 7 || continue
        push!(rows, (pid=parse(Int, f[1]), engine=String(f[2]), mode=String(f[3]),
                     seed=parse(Int, f[4]), n=parse(Int, f[5]),
                     journaled=parse(Int, f[6]), exitcode=parse(Int, f[7])))
    end
    return isempty(rows) ? nothing : rows
end

# ------------------------------------------------------------- campaign

struct Shard
    engine::String
    mode::String      # "-" for the engines that ignore --modes (step/evalcode/corpus)
    seed::Int
    n::Int
    proc::Base.Process
    pid::Int          # captured at spawn: `getpid` throws ESRCH once it exits
    log::String
    jdir::String
end

# How many candidates a shard got through, from the harness's own journal. Worth
# reporting because a shard killed mid-campaign (the julia 1.11 codegen abort in
# `findings/julia-codegen-abort-allocopt/` does exactly that, on the *reference*
# side) writes no .cov at all: coverage is dumped at process exit, so a crashed
# shard contributes nothing and the nominal candidate count would be a lie.
function journaled(jdir::String)
    p = joinpath(jdir, "log.txt")
    return isfile(p) ? countlines(p) : 0
end

# Only these two run each candidate under a chosen interpreter configuration;
# run.jl parses --modes unconditionally but the other engines ignore it, so
# labelling their shards with a mode would fabricate a per-mode difference.
honorsmodes(engine) = engine in ("native", "supposition")

function runargs(o, engine, mode, seed, n, jdir)
    args = String[joinpath(FUZZDIR, "run.jl"),
                  "--engine", engine, "--n", string(n), "--seed", string(seed),
                  "--budget", string(o["budget"]), "--nosync", "--journaldir", jdir]
    honorsmodes(engine) && append!(args, ["--modes", mode])
    o["big"] && push!(args, "--big")
    append!(args, o["extra"])
    return args
end

function spawnshard(o, engine, mode, seed, logdir, jdir)
    args = runargs(o, engine, mode, seed, o["n"], jdir)
    log = joinpath(logdir, "shard-$engine-$(mode)-$(seed).log")
    cmd = `$(Base.julia_cmd()) --startup-file=no --code-coverage=@$SRCDIR --project=$FUZZDIR $args`
    p = run(pipeline(cmd; stdout=log, stderr=log), wait=false)
    # The .cov files are named after the child's pid, which is how per-mode and
    # per-engine attribution work — read it now, while the child is certainly alive.
    pid = try Int(getpid(p)) catch; -1 end
    return Shard(engine, mode, seed, o["n"], p, pid, log, jdir)
end

# Same campaign, no --code-coverage: the denominator for the coverage tax.
function timecampaign(o, engine, mode, seed, n, logdir, jdir; coverage::Bool)
    args = runargs(o, engine, mode, seed, n, jdir)
    covflag = coverage ? `--code-coverage=@$SRCDIR` : ``
    cmd = `$(Base.julia_cmd()) --startup-file=no $covflag --project=$FUZZDIR $args`
    log = joinpath(logdir, "calib-$(coverage ? "cov" : "raw").log")
    t = @elapsed begin
        p = run(pipeline(ignorestatus(cmd); stdout=log, stderr=log), wait=false)
        pid = try Int(getpid(p)) catch; -1 end
        wait(p)
        # Drop only this run's .cov: the campaign's files may still be wanted.
        coverage && pid > 0 && sweepcov(verbose=false, pid=pid)
    end
    return t
end

# ------------------------------------------- mapping (a): builtin arms

struct Arm
    name::String      # the builtin, as written: `Core._apply_iterate`, `getfield`, …
    guard::String     # the `@static` version guard, or ""
    live::Bool        # guard true in this build (false ⇒ the arm is not compiled in)
    first::Int        # the `if`/`elseif` line
    last::Int         # last line of the arm's body
end

# `builtins.jl` is generated by `bin/generate_builtins.jl` with a fixed shape:
# one flat `if f === … elseif f === …` chain at four-space indent inside
# `maybe_evaluate_builtin`. Parsing it as text is sturdier than pattern-matching
# the nested `Expr` an `elseif` chain lowers to, and it keeps line numbers exact.
function builtinarms(lines::Vector{String}, jimod)
    chain = Tuple{Int,String}[]      # (line, condition text)
    for (i, l) in pairs(lines)
        m = match(r"^    (?:else)?if (.*?)\s*$", l)
        m === nothing && continue
        occursin("f === ", m.captures[1]) || continue
        push!(chain, (i, m.captures[1]))
    end
    isempty(chain) && error("no `f === …` dispatch chain found in builtins.jl")
    # The chain ends at the first `    end` after the last arm.
    tail = findfirst(i -> i > chain[end][1] && lines[i] == "    end", eachindex(lines))
    arms = Arm[]
    for (k, (line, cond)) in pairs(chain)
        last = (k == length(chain) ? tail : chain[k + 1][1]) - 1
        nm = match(r"f === ([^\s&|)]+)", cond)
        # Greedy `.*` so the guard of `@static (a && b) && f === x` is `(a && b)`.
        g = match(r"^@static (.*) && f === ", cond)
        guard = g === nothing ? "" : g.captures[1]
        live = guard == "" ? true : Core.eval(jimod, Meta.parse(guard))::Bool
        push!(arms, Arm(nm === nothing ? cond : nm.captures[1], guard, live, line, last))
    end
    # The three tail blocks after the chain dispatch on `f` too, and are just as
    # much "a builtin arm" for reporting purposes; they are matched by their text
    # so a regenerated builtins.jl doesn't silently drop them.
    for (pat, name) in ((r"^    if isa\(f, Core\.IntrinsicFunction\)", "<any IntrinsicFunction>"),
                        (r"^        if f === Core\.Intrinsics\.have_fma", "Core.Intrinsics.have_fma"),
                        (r"^        if f === Core\.Intrinsics\.muladd_float", "Core.Intrinsics.muladd_float"),
                        (r"^        if f === Core\.Intrinsics\.atomic_pointermodify", "Core.Intrinsics.atomic_pointermodify"),
                        (r"^    if isa\(f, typeof\(kwinvoke\)\)", "<kwinvoke>"))
        i = findfirst(l -> match(pat, l) !== nothing, lines)
        i === nothing && continue
        indent = length(match(r"^ *", lines[i]).match)
        j = findfirst(k -> k > i && lines[k] == " "^indent * "end", eachindex(lines))
        push!(arms, Arm(name, "", true, i, (j === nothing ? i + 1 : j) - 1))
    end
    return arms
end

armhits(a::Arm, counts::Vector{Int}) = count(i -> i <= length(counts) && counts[i] > 0,
                                             (a.first + 1):a.last)
armreached(a::Arm, counts::Vector{Int}) = a.first <= length(counts) ? max(0, counts[a.first]) : 0

# ---------------------------------------- mapping (b): enclosing function

struct FnDef
    name::String
    first::Int
    last::Int
end

# Line ranges come from `Meta.parseall`'s LineNumberNodes rather than a text
# scan of `function`/`end`, so `@static if`-wrapped and macro-wrapped definitions
# are placed correctly and indentation conventions don't matter.
#
# Known limitations of the mapping, both benign for this report:
#   - a definition's range ends at the last line carrying a LineNumberNode, so a
#     trailing `end` (never instrumented anyway) falls outside it;
#   - closures and inner functions are folded into their enclosing definition,
#     which is the reporting unit we want.
isdef(ex) = ex isa Expr && (ex.head === :function ||
    (ex.head === :(=) && ex.args[1] isa Expr && ex.args[1].head in (:call, :where)))

function defname(ex)
    s = ex isa Expr ? (ex.head === :function || ex.head === :(=) ? ex.args[1] : ex) : ex
    while s isa Expr && s.head in (:where, :(::))
        s = s.args[1]
    end
    s isa Expr && s.head === :call && (s = s.args[1])
    s isa Expr && s.head === :curly && (s = s.args[1])
    return string(s)
end

function maxline(ex, m::Int=0)
    if ex isa LineNumberNode
        return max(m, ex.line)
    elseif ex isa Expr
        for a in ex.args
            m = maxline(a, m)
        end
    end
    return m
end

function scandefs!(defs::Vector{FnDef}, ex, curline::Int)
    ex isa Expr || return curline
    if isdef(ex)
        push!(defs, FnDef(defname(ex), curline, max(curline, maxline(ex))))
        return curline
    end
    for a in ex.args
        if a isa LineNumberNode
            curline = a.line
        else
            scandefs!(defs, a, curline)
        end
    end
    return curline
end

function filedefs(path::String)
    defs = FnDef[]
    try
        ex = Meta.parseall(read(path, String); filename=path)
        scandefs!(defs, ex, 1)
    catch err
        @warn "could not parse $path for the function mapping" err
        return FnDef[]
    end
    sort!(defs, by = d -> (d.first, d.last))
    return defs
end

# ------------------------------------------------------------- analysis

struct FnCov
    def::FnDef
    hit::Int          # lines executed
    cold::Int         # lines with a counter that never fired
    none::Int         # lines with no counter (blank/comment, or never codegen'd)
    coldspans::Vector{UnitRange{Int}}
end

function fncov(d::FnDef, counts::Vector{Int})
    hit = cold = none = 0
    spans = UnitRange{Int}[]
    run0 = 0
    for i in d.first:min(d.last, length(counts))
        c = counts[i]
        if c > 0
            hit += 1
            run0 > 0 && push!(spans, run0:(i - 1)); run0 = 0
        elseif c == 0
            # The `function f(…)` header line carries a counter that only fires
            # for methods whose entry code (keyword/vararg/@nospecialize setup)
            # is attributed to it, so a 0 there is not evidence of anything.
            i == d.first && d.last > d.first && continue
            cold += 1
            run0 == 0 && (run0 = i)
        else
            none += 1
        end
    end
    run0 > 0 && push!(spans, run0:min(d.last, length(counts)))
    return FnCov(d, hit, cold, none, spans)
end

function fmtspans(spans; max=12)
    txt = [length(s) == 1 ? string(first(s)) : "$(first(s))–$(last(s))" for s in spans]
    return length(txt) <= max ? join(txt, ", ") :
           join(first(txt, max), ", ") * ", …(+$(length(txt) - max) more)"
end

# ---------------------------------------------------------------- main

o = parseargs(ARGS)
modes = String.(split(o["modes"], ','))
engines = String.(split(o["engine"], ','))
all(m -> m in ("rec", "cmp", "both"), modes) || error("--modes entries must be rec|cmp|both")

srcfiles = sort(filter(f -> endswith(f, ".jl"), readdir(SRCDIR)))
# cleanup=false: julia would otherwise delete this at exit even when --keep asked
# for the shard logs and journals to survive. Swept explicitly below instead.
logdir = mktempdir(; prefix="fuzzji-cov-", cleanup=false)

# Stale .cov from an earlier run would silently inflate everything — unless
# re-reporting from exactly those files is the point (--reuse), or adding to
# them on purpose (--accumulate, for a campaign built out of several runs).
(o["reuse"] || o["accumulate"]) || sweepcov(verbose=false)

# One shard group per (engine, mode) — except that the engines which ignore
# --modes get a single group instead of one per mode.
groups = [(e, m) for e in engines for m in (honorsmodes(e) ? modes : ["-"])]
nproc = length(groups) * o["shards"]
@info "coverage campaign" engines=join(engines, ",") modes=join(modes, ",") shards_per_group=o["shards"] n_per_shard=o["n"] processes=nproc candidates=nproc * o["n"]

t0 = time()
shards = Shard[]
if !o["reuse"]
    for (e, m) in groups, g in 1:o["shards"]
        # Shard g uses the same seed range in every group, so the per-mode
        # comparison is over the same programs rather than two different samples.
        push!(shards, spawnshard(o, e, m, o["seed"] + (g - 1) * o["n"], logdir,
                                 joinpath(logdir, "journal-$e-$m-$g")))
    end
    for s in shards
        wait(s.proc)
    end
end
wall = time() - t0
o["reuse"] || @info "campaign done" wall_s=round(wall; digits=1) rate_per_s=round(nproc * o["n"] / wall; digits=2)

# One row per shard, written to SHARDMAP so --reuse can rebuild the same tables.
# --accumulate keeps the previous runs' rows, matching the .cov files it keeps.
shardrows = o["reuse"] ? something(readshardmap(), NamedTuple[]) :
    [(pid=s.pid, engine=s.engine, mode=s.mode, seed=s.seed, n=s.n,
      journaled=journaled(s.jdir), exitcode=Int(s.proc.exitcode)) for s in shards]
if !o["reuse"]
    o["accumulate"] && prepend!(shardrows, something(readshardmap(), NamedTuple[]))
    writeshardmap(shardrows)
end

failed = String[]
for r in shardrows
    # run.jl exits 2 when it reported a *new* finding — that is news, not failure.
    r.exitcode in (0, 2) ||
        push!(failed, "`$(r.engine)`/$(r.mode)/seed $(r.seed) exited $(r.exitcode) after " *
                      "$(r.journaled) candidates — no .cov written, so it contributed nothing")
    r.exitcode == 2 && @warn "shard reported a finding" engine=r.engine mode=r.mode seed=r.seed
end
for f in failed
    @warn f
end

# Per-mode / per-engine attribution by pid: each shard's .cov files are named
# after its own pid, so concurrent shards stay separable. Under --reuse the map
# comes from the previous run's shard file; without it, the splits are dropped
# rather than reported as trivially equal.
o["reuse"] && isempty(shardrows) && @warn "no shard map at $SHARDMAP — per-mode/per-engine splits unavailable"
pidsof(pred) = isempty(shardrows) ? nothing : Set(r.pid for r in shardrows if pred(r))
covbymode = Dict(m => first(harvest(pidsof(s -> s.mode == m && honorsmodes(s.engine)))) for m in modes)
covbyengine = Dict(e => first(harvest(pidsof(s -> s.engine == e))) for e in engines)
cov, allpids = harvest(nothing)
let unknown = setdiff(allpids, Set(r.pid for r in shardrows))
    isempty(unknown) || @warn "unattributed .cov pids (counted in the total, not per-mode)" unknown
end

isempty(cov) && error("no .cov files produced — did the shards die? logs in $logdir")

# Optional calibration of the coverage tax, run alone (not against the shards).
slow = nothing
if o["slowdown"]
    ncal = min(o["n"], 40)
    @info "calibrating coverage slowdown" n=ncal
    cal(c) = timecampaign(o, engines[1], modes[1], o["seed"] + 10^6, ncal, logdir,
                          joinpath(logdir, "jcal"); coverage=c)
    traw = cal(false)
    tcov = cal(true)
    slow = (ncal, traw, tcov)
end

# --- builtin arms -------------------------------------------------------
using JuliaInterpreter          # only to evaluate the arms' `@static` guards
blines = readlines(joinpath(SRCDIR, "builtins.jl"))
arms = builtinarms(blines, JuliaInterpreter)
bcounts = get(cov, "builtins.jl", Int[])
# Per-arm state. `Core.arrayset` has two arms in the file, so state is per arm
# index; the by-name view used by the gap table takes hit > never > absent.
state(a::Arm) = !a.live ? :absent : armhits(a, bcounts) > 0 ? :hit : :never
armstates = Symbol[state(a) for a in arms]
armstate = Dict{String,Symbol}()
for (a, st) in zip(arms, armstates)
    prev = get(armstate, a.name, :absent)
    armstate[a.name] = (prev === :hit || st === :hit) ? :hit :
                       (prev === :never || st === :never) ? :never : :absent
end
armhitin(c) = Set(a.name for a in arms if a.live && armhits(a, get(c, "builtins.jl", Int[])) > 0)
armhitbymode = Dict(m => armhitin(covbymode[m]) for m in modes)
armhitbyengine = Dict(e => armhitin(covbyengine[e]) for e in engines)
# Without a pid→shard map every subset is the whole set, and a "hit only under
# X" table would be a lie of omission — drop those sections instead.
splitok = !isempty(shardrows)

# --- functions ----------------------------------------------------------
fns = Dict{String,Vector{FnCov}}()
for f in srcfiles
    counts = get(cov, f, Int[])
    isempty(counts) && continue
    path = joinpath(SRCDIR, f)
    nsrc = countlines(path)
    # A .cov file has one column per source line; a mismatch means the source
    # moved under the campaign and every line number below is off.
    length(counts) == nsrc ||
        @warn "cov/source line count mismatch — was src/$f edited mid-campaign?" cov=length(counts) src=nsrc
    fns[f] = [fncov(d, counts) for d in filedefs(path)]
end

filetotals = map(srcfiles) do f
    c = get(cov, f, Int[])
    (file=f, lines=length(c), hit=count(>(0), c), cold=count(==(0), c), none=count(<(0), c))
end
filter!(t -> t.lines > 0, filetotals)

tothit = sum(t.hit for t in filetotals; init=0)
totcold = sum(t.cold for t in filetotals; init=0)

# --- which of NEXT.md's still-open grammar gaps does this implicate? -----
#
# Curated: each entry is (grammar gap, evidence predicate). Only entries whose
# evidence is actually cold are printed, so the section is data-driven — but the
# gap→symbol association is hand-authored and must be maintained by hand.
#
# Only *small, specific* functions belong here: the verdict is "no line of this
# definition ran", so a 200-line function that is 90% cold still counts as live
# evidence and would flatten the signal.
const GAPS = [
    ("destructuring / iterated assignment",
     ["maybe_step_through_arg_destructuring!", "is_indexed_iterate_call"],
     ["Core._apply_iterate", "Core._svec_ref", "Core.svec"]),
    ("`do` blocks (closure passed as first argument)",
     String[], String[]),
    ("`@generated` functions",
     ["get_source"], String[]),
    ("parametric structs / inner constructors",
     ["evaluate_overlayed_methoddef"],
     ["Core._structtype", "Core._typebody!", "Core._typevar", "Core.apply_type",
      "Core._setsuper!", "Core._equiv_typedef", "Core._primitivetype", "Core._abstracttype"]),
    ("defaults referencing earlier parameters (keyword/optional sorters)",
     ["maybe_step_through_kwprep!", "is_kwcall_stmt", "find_kwcall", "advance_to_kwcall!",
      "is_empty_namedtuple", "is_merge_call", "maybe_step_through_nkw_meta!"], String[]),
    ("`invoke` with keyword arguments", String[], ["<kwinvoke>"]),
    ("`ccall` / `@ccall` (the foreigncall conversion path)",
     ["evaluate_foreigncall", "resolvefc", "build_compiled_llvmcall!"],
     ["Base.cglobal", "Core.Intrinsics.llvmcall"]),
    ("`invoke` / world-age and latest-world calls",
     String[], ["invoke", "Core.invokelatest", "Core._call_latest", "Core._call_in_world",
                "Core._call_in_world_total", "Core.invoke_in_world"]),
    ("global mutation through the `*global` builtins",
     String[], ["getglobal", "setglobal!", "swapglobal!", "modifyglobal!", "replaceglobal!",
                "setglobalonce!", "isdefinedglobal", "Core.get_binding_type"]),
    ("`Memory`/`MemoryRef` primitives (array internals below `Array`)",
     String[], ["Core.memorynew", "Core.memoryref", "Core.memoryrefnew", "Core.memoryrefget",
                "Core.memoryrefset!", "Core.memoryrefoffset", "Core.memoryref_isassigned",
                "Core.memoryrefmodify!", "Core.memoryrefswap!", "Core.memoryrefreplace!",
                "Core.memoryrefsetonce!", "Core.memoryrefunset!"]),
    ("finalizers", String[], ["Core.finalizer"]),
    ("opaque closures", ["eval_new_opaque_closure"], String[]),
    ("reflection on the running program (`applicable`, `fieldtype`, `nfields`, `sizeof`)",
     String[], ["applicable", "fieldtype", "nfields", "Core.sizeof", "Core.ifelse", "Core._expr"]),
    ("atomics on fields and globals",
     String[], ["modifyfield!", "replacefield!", "swapfield!", "setfieldonce!",
                "Core.Intrinsics.atomic_pointermodify"]),
]

coldfn(name) = any(fc.def.name == name && fc.hit == 0 for fcs in values(fns) for fc in fcs)
fnknown(name) = any(fc.def.name == name for fcs in values(fns) for fc in fcs)

# ---------------------------------------------------------------- report

open(o["out"], "w") do io
    println(io, "# Interpreter coverage report")
    println(io)
    println(io, "Generated by `fuzz/coverage.jl` — NEXT.md item 2, stage one. ",
                "This is a *measurement of the interpreter*, not of the generator: ",
                "`metrics.jl` says what is produced, this says what is reached.")
    println(io)
    println(io, "## Campaign")
    println(io)
    println(io, "| parameter | value |")
    println(io, "|---|---|")
    println(io, "| date | ", RUNSTAMP, " |")
    println(io, "| julia | ", VERSION, " |")
    println(io, "| engines | ", join(("`" * e * "`" for e in engines), ", "), " |")
    println(io, "| modes | ", join(modes, ", "), " (`native`/`supposition` only; the other engines ignore them) |")
    println(io, "| shard groups | ", length(groups), " — ",
                join(("$e/$m" for (e, m) in groups), ", "), " |")
    println(io, "| shards per group | ", o["shards"], " |")
    println(io, "| candidates per shard | ", o["n"], " |")
    println(io, "| candidate-runs requested | ", nproc * o["n"], " (this invocation) |")
    if !isempty(shardrows)
        println(io, "| candidate-runs measured | ",
                    sum(r.journaled for r in shardrows if r.exitcode in (0, 2); init=0),
                    " — every shard below that exited cleanly; a crashed shard writes no .cov |")
        println(io, "| distinct programs | ",
                    sum(r.n for r in shardrows if r.exitcode in (0, 2) && r.engine == engines[1] &&
                                                  r.mode in (modes[1], "-"); init=0),
                    " per group |")
    end
    println(io, "| base seed | ", o["seed"], " (shard g of every group: seed + (g-1)·n) |")
    println(io, "| statement budget | ", o["budget"], " |")
    println(io, "| generator profile | ", o["big"] ? "--big" : "default",
                isempty(o["extra"]) ? "" : " " * join(o["extra"], " "), " |")
    if o["reuse"]
        println(io, "| note | `--reuse`: re-reported from .cov files already on disk; ",
                    "the parameters above describe the run that produced them |")
    else
        println(io, "| wall clock | ", round(wall; digits=1), " s (", nproc, " concurrent processes) |")
        println(io, "| throughput | ", round(nproc * o["n"] / wall; digits=2), " candidate-runs/s aggregate |")
    end
    isempty(o["note"]) || println(io, "| note | ", o["note"], " |")
    if slow !== nothing
        ncal, traw, tcov = slow
        println(io, "| coverage tax | ", round(tcov / traw; digits=2), "× wall (",
                    round(traw; digits=1), " s → ", round(tcov; digits=1), " s on ", ncal,
                    " candidates, single process) |")
    end
    println(io)
    if !isempty(shardrows)
        println(io, "### Shards")
        println(io)
        println(io, "| engine | mode | seeds | candidates journaled | exit | coverage counted |")
        println(io, "|---|---|---|---|---|---|")
        for r in shardrows
            println(io, "| `", r.engine, "` | ", r.mode, " | ", r.seed, "–", r.seed + r.n - 1,
                        " | ", r.journaled, " | ", r.exitcode, " | ",
                        r.exitcode in (0, 2) ? "yes" : "**no**", " |")
        end
        println(io)
        if !isempty(failed)
            println(io, "Shard failures:")
            println(io)
            for f in failed
                println(io, "- ", f)
            end
            println(io)
        end
    end

    # ---- headline: builtin dispatch arms
    nlive = count(a -> a.live, arms)
    nhit = count(==(:hit), armstates)
    nnever = count(==(:never), armstates)
    nabsent = count(a -> !a.live, arms)
    println(io, "## Headline: `builtins.jl` dispatch arms")
    println(io)
    println(io, "`maybe_evaluate_builtin` special-cases each builtin in one flat ",
                "`f === …` chain. An arm counts as **hit** when a line of its *body* ran; ",
                "the count on the `elseif` line itself only says the chain was walked past it.")
    println(io)
    println(io, "- arms in the file: **", length(arms), "**")
    println(io, "- compiled out on julia ", VERSION, " (`@static` guard false): **", nabsent, "**")
    println(io, "- live arms: **", nlive, "** → **", nhit, " hit**, **", nnever, " never hit** (",
                round(100nhit / max(1, nlive); digits=1), "% of live arms reached)")
    println(io)
    println(io, "### Never-hit live arms")
    println(io)
    println(io, "| builtin | lines | chain reached | note |")
    println(io, "|---|---|---|---|")
    for (a, st) in zip(arms, armstates)
        st === :never || continue
        println(io, "| `", a.name, "` | ", a.first, "–", a.last, " | ",
                    armreached(a, bcounts), " | ", a.guard == "" ? "" : "guard `" * a.guard * "`", " |")
    end
    println(io)
    println(io, "### Hit arms")
    println(io)
    println(io, join(("`" * a.name * "`" for (a, st) in zip(arms, armstates) if st === :hit), ", "))
    println(io)
    if nabsent > 0
        println(io, "### Absent on this build (`@static` guard false)")
        println(io)
        println(io, "Not a grammar gap and not dead code — these arms do not exist in this ",
                    "julia version's build of the file. They read as never-hit in the raw .cov ",
                    "because the counters are still allocated.")
        println(io)
        println(io, join(("`" * a.name * "`" for a in arms if !a.live), ", "))
        println(io)
    end

    # ---- per-mode and per-engine splits
    if splitok && length(modes) > 1 && any(honorsmodes, engines)
        println(io, "## Dispatch arms by interpreter mode")
        println(io)
        println(io, "Same programs, same seeds, different interpreter configuration — ",
                    "`rec` interprets everything, `cmp` runs calls natively and only steps ",
                    "the toplevel frame, so an arm reached only under one of them is a path ",
                    "the other configuration cannot get to.")
        println(io)
        for m in modes
            println(io, "- `", m, "` reached ", length(armhitbymode[m]), " of ", nlive, " live arms")
        end
        for m in modes, m2 in modes
            m == m2 && continue
            onlym = sort(collect(setdiff(armhitbymode[m], armhitbymode[m2])))
            println(io, "- hit under `", m, "` but not `", m2, "` (", length(onlym), "): ",
                        isempty(onlym) ? "—" : join(("`" * x * "`" for x in onlym), ", "))
        end
        println(io)
    end
    if splitok && length(engines) > 1
        println(io, "## Reach by engine")
        println(io)
        println(io, "Each axis is a different entry point into the package, so ",
                    "\"never hit\" always means \"never hit *by these engines*\".")
        println(io)
        println(io, "| engine | live arms hit | ", join(("`" * f * "` lines hit" for f in srcfiles), " | "), " |")
        println(io, "|---", "|---"^(1 + length(srcfiles)), "|")
        for e in engines
            print(io, "| `", e, "` | ", length(armhitbyengine[e]))
            for f in srcfiles
                print(io, " | ", count(>(0), get(covbyengine[e], f, Int[])))
            end
            println(io, " |")
        end
        println(io)
        for e in engines
            others = union(Set{String}(), (armhitbyengine[e2] for e2 in engines if e2 != e)...)
            onlye = sort(collect(setdiff(armhitbyengine[e], others)))
            isempty(onlye) && continue
            println(io, "- arms only `", e, "` reaches: ", join(("`" * x * "`" for x in onlye), ", "))
        end
        println(io)
    end

    # ---- the big never-hit definitions, across all files
    biggest = [(f, fc) for f in srcfiles if haskey(fns, f)
                       for fc in fns[f] if fc.hit == 0 && fc.cold + fc.none > 0]
    sort!(biggest, by = t -> -(t[2].def.last - t[2].def.first))
    println(io, "## Biggest never-hit definitions")
    println(io)
    println(io, "The whole never-hit set is below, per file; this is the top of it by span, ",
                "which is where the untested *volume* is.")
    println(io)
    println(io, "| definition | file | lines | span | flavour |")
    println(io, "|---|---|---|---|---|")
    for (f, fc) in first(biggest, 20)
        println(io, "| `", fc.def.name, "` | `src/", f, "` | ", fc.def.first, "–", fc.def.last,
                    " | ", fc.def.last - fc.def.first + 1, " | ", fc.cold > 0 ? "cold" : "uncompiled", " |")
    end
    println(io)

    # ---- never-hit functions
    println(io, "## Never-hit functions")
    println(io)
    println(io, "A definition is never-hit when no line inside it executed. Two flavours, ",
                "and the distinction matters:")
    println(io)
    println(io, "- **cold** — the enclosing method was codegen'd (counters exist) and no line fired;")
    println(io, "- **uncompiled** — no line of the definition ever got a counter, i.e. the method ",
                "was never compiled at all. Reported separately because a definition that is ",
                "*only* comments would look the same; every entry below has at least one ",
                "statement, so treat it as never-called.")
    println(io)
    for f in srcfiles
        haskey(fns, f) || continue
        cold = [fc for fc in fns[f] if fc.hit == 0 && fc.cold + fc.none > 0]
        isempty(cold) && continue
        sort!(cold, by = fc -> -(fc.cold + fc.none))
        println(io, "### `src/", f, "` — ", length(cold), " of ", length(fns[f]), " definitions never hit")
        println(io)
        println(io, "| definition | lines | flavour |")
        println(io, "|---|---|---|")
        for fc in cold
            println(io, "| `", fc.def.name, "` | ", fc.def.first, "–", fc.def.last, " | ",
                        fc.cold > 0 ? "cold" : "uncompiled", " |")
        end
        println(io)
    end

    # ---- partially-hit functions
    println(io, "## Partially-hit functions (never-hit line spans)")
    println(io)
    println(io, "The top of this list is where a *reached* code path has an unreached branch — ",
                "usually a grammar gap one construct away from something already generated. ",
                "`maybe_evaluate_builtin` is omitted: its cold lines are the dispatch-arm ",
                "table above, in a more useful form.")
    println(io)
    for f in srcfiles
        haskey(fns, f) || continue
        part = [fc for fc in fns[f] if fc.hit > 0 && fc.cold > 0 &&
                                       fc.def.name != "maybe_evaluate_builtin"]
        isempty(part) && continue
        sort!(part, by = fc -> -fc.cold)
        println(io, "### `src/", f, "`")
        println(io)
        println(io, "| definition | hit | cold | cold spans |")
        println(io, "|---|---|---|---|")
        for fc in first(part, 25)
            println(io, "| `", fc.def.name, "` (", fc.def.first, ") | ", fc.hit, " | ", fc.cold,
                        " | ", fmtspans(fc.coldspans), " |")
        end
        length(part) > 25 && println(io, "\n…and ", length(part) - 25, " more definitions with cold lines.")
        println(io)
    end

    # ---- per-file totals
    println(io, "## Per-file totals")
    println(io)
    println(io, "`instrumented` = lines that got a counter (executable and codegen'd). ",
                "`no counter` mixes blank/comment lines with code in never-compiled methods, ",
                "so it is not a coverage denominator — the function tables above split those apart.")
    println(io)
    println(io, "| file | source lines | instrumented | hit | cold | % of instrumented hit | no counter | defs | defs never hit |")
    println(io, "|---|---|---|---|---|---|---|---|---|")
    ndefs = ncolddefs = 0
    for t in filetotals
        inst = t.hit + t.cold
        d = get(fns, t.file, FnCov[])
        dc = count(fc -> fc.hit == 0 && fc.cold + fc.none > 0, d)
        ndefs += length(d); ncolddefs += dc
        println(io, "| `src/", t.file, "` | ", t.lines, " | ", inst, " | ", t.hit, " | ", t.cold,
                    " | ", inst == 0 ? "—" : string(round(100t.hit / inst; digits=1), "%"),
                    " | ", t.none, " | ", length(d), " | ", dc, " |")
    end
    let inst = tothit + totcold
        println(io, "| **total** | ", sum(t.lines for t in filetotals), " | ", inst, " | ", tothit,
                    " | ", totcold, " | ", round(100tothit / max(1, inst); digits=1), "% | ",
                    sum(t.none for t in filetotals), " | ", ndefs, " | ", ncolddefs, " |")
    end
    println(io)

    # ---- grammar gaps
    println(io, "## Which of NEXT.md's still-open grammar gaps does this implicate?")
    println(io)
    println(io, "NEXT.md lists, never closed: *destructuring, `do` blocks, `@generated` functions, ",
                "parametric structs, inner constructors, defaults referencing earlier parameters*. ",
                "The table below is the mechanical part of the answer: for each gap, the ",
                "interpreter symbols it would have to reach, and whether they are cold. ",
                "The gap→symbol association is hand-authored in `fuzz/coverage.jl` (`GAPS`) and ",
                "must be maintained alongside it; the cold/hit verdicts are measured.")
    println(io)
    println(io, "| grammar gap | cold evidence | live evidence |")
    println(io, "|---|---|---|")
    for (gap, fnames, armnames) in GAPS
        coldev = String[]
        hitev = String[]
        for n in fnames
            fnknown(n) || continue
            push!(coldfn(n) ? coldev : hitev, "`" * n * "`")
        end
        for n in armnames
            st = get(armstate, n, :unknown)
            st === :never && push!(coldev, "`" * n * "`")
            st === :hit && push!(hitev, "`" * n * "`")
        end
        if isempty(coldev) && isempty(hitev)
            # Printed rather than skipped: "this construct has no distinct
            # interpreter surface" is itself an answer about the gap.
            println(io, "| ", gap, " | *no mapped surface* | *no mapped surface* |")
        else
            println(io, "| ", gap, " | ", isempty(coldev) ? "—" : join(coldev, ", "),
                        " | ", isempty(hitev) ? "—" : join(hitev, ", "), " |")
        end
    end
    println(io)
    println(io, """
    A gap with **no cold evidence** is not urgent: whatever the generator is missing,
    the interpreter code that would serve it is already being reached by some other
    construct, so closing that gap buys new *inputs* but not new *interpreter paths*.
    A gap whose evidence is entirely cold is the opposite — it is the only thing
    keeping a whole region of `src/` untested, and it is the one to close first.

    Read this table with the never-hit-function tables above, not instead of them:
    the tables are the primary data, and a cold function that no gap in the list
    explains is worth more than a gap the list happens to name.
    """)

    println(io, "## Method and limitations")
    println(io)
    println(io, """
    - **No interpreter instrumentation.** Coverage comes from julia's own
      `--code-coverage=@<repo>/src`, gathered from subprocess campaigns. Nothing in
      `src/` is modified, and the `CoverageInterp <: Interpreter` NEXT.md sketches
      is not needed for stage one. What that costs: coverage is per *line*, not per
      statement-head × context, so "which `evaluate_call!` path" is answered by line
      spans rather than by a labelled hit-set.
    - **Base code interpreted *by* the interpreter is not measured, deliberately.**
      Only `<repo>/src` is tracked; the millions of Base lines that rec mode walks
      through are irrelevant to the question "what part of JuliaInterpreter is
      untested".
    - **`-` (no counter) is ambiguous** between "not executable" and "never
      codegen'd". The function-level mapping resolves it: a definition whose lines
      are all `-` is a never-compiled method, reported as *uncompiled*.
    - **Module top level never runs.** The package is loaded from its precompile
      cache, so `const`/`include`/`using` statements at module scope are not
      executed in the campaign process and read as unreached. That is why
      `JuliaInterpreter.jl` and `precompile.jl` show ~0 hit lines; ignore those
      two rows in the per-file table. Function bodies are unaffected — coverage
      is disabled for the *native-code* cache, so every method is recompiled from
      IR on first call and instrumented normally.
    - **Function line ranges come from `Meta.parseall`** (LineNumberNodes), so a
      definition's range stops at its last statement — trailing `end` lines fall
      outside every range and land in no bucket. Closures are folded into their
      enclosing definition.
    - **The `function f(…)` header line is ignored when zero.** Its counter only
      fires for methods whose entry code is attributed to the header, so a 0 there
      means nothing either way.
    - **Cold ≠ dead.** An arm or a function can be cold because the campaign's
      grammar cannot reach it, because it is only reachable from a *different*
      entry point (`step`/`evalcode`/`corpus` engines exercise `commands.jl`,
      `breakpoints.jl` and `utils.jl`, which the `native` engine barely touches),
      or because it is genuinely dead on this julia version. The engine and modes
      used are in the campaign table above; re-run with a different `--engine`
      before calling anything dead.
    """)
end

keepcov = o["keep"] || o["reuse"] || o["accumulate"]
keepcov || sweepcov()
keepcov || rm(logdir; recursive=true, force=true)
keepcov && @info "kept .cov files and shard logs" logdir

@info "report written" out=o["out"] arms_never_hit=count(==(:never), armstates) live_arms=count(a -> a.live, arms) lines_hit=tothit lines_cold=totcold
