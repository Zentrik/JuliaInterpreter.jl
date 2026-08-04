# The builtins/intrinsics prober: reflection-driven, denylist-guarded.
#
# `src/builtins.jl` is *generated* by `bin/generate_builtins.jl`, which
# enumerates every `Core.Builtin` and every `Core.Intrinsics` function by
# reflection and emits one dispatch arm per callable. This file consumes the
# same enumeration from the other side: whatever the interpreter special-cases,
# the fuzzer can call — with an arity sweep and arguments drawn from the
# TySum-directed generator, so probes see generated structs, vectors, closures,
# symbols and atomic orderings instead of a hand-written string.
#
# Three tables carry the hand-curated knowledge that reflection cannot supply:
#
#   PROBE_BANS     safety. Every entry has a reason, and every reason is
#                  load-bearing: a bad probe either kills the worker (SIGILL,
#                  segfault, OOM) or poisons the oracle (unspecified results,
#                  nondeterministic scheduling, corrupted shared runtime
#                  state). `:all` means never rendered; `:arbitrary` means the
#                  callable is reachable *only* through a vetted recipe;
#                  `:fixed` means it is reachable *only* through a vetted
#                  FIXED_PROBES template (needed when safety requires an
#                  enclosing construct — e.g. GC-rooting a pointee across the
#                  call — that per-argument recipes cannot express).
#   PROBE_RECIPES  yield. Plausible argument shapes for the high-value
#                  builtins, so probes exercise success paths and not only the
#                  MethodError/TypeError arms.
#   FIXED_PROBES   migrated curated knowledge that is not a plain
#                  `callee(args...)` call (opaque closures, `Memory` basics,
#                  wrapped return values).
#
# Everything else — which callables exist, and how many arguments each takes —
# comes from `names(Core; all=true)`, `names(Core.Intrinsics; all=true)` and
# the compiler's own tfunc arity tables, so the probe set tracks the Julia
# version the harness happens to run on.

# ---------------------------------------------------------------------------
# Enumeration

struct ProbeTarget
    name::Symbol       # bare name, as it appears in Core / Core.Intrinsics
    spelling::String   # how the callee renders, e.g. "Core.Intrinsics.add_int"
    kind::Symbol       # :builtin | :intrinsic | :extra
    minarg::Int        # from the compiler's tfunc tables; (0, typemax) if unknown
    maxarg::Int
    arityknown::Bool   # false when the tfunc tables have no entry at all
    reciponly::Bool    # banned from the arbitrary-argument sweep (recipes only)
    reason::String     # why it is recipe-only ("" when it is not)
end

isbuiltinlike(f) = (supertype(typeof(f)) === Core.Builtin) || isa(f, Core.IntrinsicFunction)

# `Core.Compiler` holds (minarg, maxarg) for every builtin and intrinsic —
# exactly the table `bin/generate_builtins.jl` uses to decide how many
# per-arity clauses to emit, which makes it the right source for "what does a
# correct-looking call to this look like".
# Returns (minarg, maxarg, known). `known == false` means the tables say
# nothing about this callable, which is not the same as "it accepts zero
# arguments": `Core._call_latest()` and `Core._apply_pure()` — both absent from
# the tables — index their first argument without an arity check and
# **segfault** (measured on 1.11.9). Unknown arity therefore means a floor of
# one argument, never zero.
function tfunc_arity(f)
    try
        C = Core.Compiler
        if isa(f, Core.IntrinsicFunction)
            id = reinterpret(Int32, f) + 1
            tbl = C.T_IFUNC
            (1 <= id <= length(tbl)) || return (0, typemax(Int), false)
            e = tbl[id]
            return (Int(e[1]), Int(e[2]), true)
        end
        id = findfirst(isequal(f), C.T_FFUNC_KEY)
        id === nothing && return (0, typemax(Int), false)
        e = C.T_FFUNC_VAL[id]
        return (Int(e[1]), Int(e[2]), true)
    catch
        return (0, typemax(Int), false)
    end
end

# `===` and `<:` are builtins whose names are not identifiers; they still probe
# fine, spelled as `Core.:(===)(...)` / `(===)(...)`.
qualspelling(mod::String, n::Symbol) =
    Base.isidentifier(n) ? mod * "." * String(n) : mod * ".:(" * String(n) * ")"
barespelling(n::Symbol) = Base.isidentifier(n) ? String(n) : "(" * String(n) * ")"

# Builtins that live in Base on some versions and are ordinary functions on
# others (`invokelatest` became a builtin in 1.12). Probing them wherever they
# exist costs nothing and keeps the version-relative promise.
const EXTRA_BASE_TARGETS = Symbol[:invokelatest, :invoke_in_world, :isdefinedglobal]

# Returns (allowed, denied, fixedonly): every enumerated spelling lands in
# exactly one, so the metrics counts add up (enumerated = allowed + denylisted
# + fixed-only). Fixed-only names are kept out of `denied` on purpose: the
# selftest's "no denylisted callee is ever rendered" invariant stays exact,
# while their vetted FIXED_PROBES templates are allowed to render them.
function enumerate_probes()
    out = ProbeTarget[]
    denied = Tuple{String,Symbol,String}[]
    fixedonly = Tuple{String,Symbol,String}[]
    seen = Set{String}()
    function add!(n::Symbol, spelling::String, f, kind::Symbol)
        spelling in seen && return
        push!(seen, spelling)
        b = probeban(n)
        if b !== nothing && b.scope === :all
            push!(denied, (spelling, n, b.reason))
            return
        end
        if b !== nothing && b.scope === :fixed
            push!(fixedonly, (spelling, n, b.reason))
            return
        end
        lo, hi, known = tfunc_arity(f)
        # An intrinsic whose arity the compiler tables do not pin down cannot be
        # called safely at all (see probearity: a wrong operand count aborts the
        # process inside codegen), so withhold it rather than guess.
        if kind === :intrinsic && (!known || hi == typemax(Int) || hi < lo)
            push!(denied, (spelling, n,
                "arity is not pinned down by the compiler's tfunc tables, and a wrong operand count to an intrinsic aborts the process inside codegen — withheld rather than guessed."))
            return
        end
        # An intrinsic whose operand *kinds* we cannot name is equally
        # unprobeable: a float operation handed a same-width integer corrupts
        # the heap silently (see intrinsic_shape_known).
        if kind === :intrinsic && !intrinsic_shape_known(n)
            push!(denied, (spelling, n,
                "operand kinds are not derivable from the name, and a float intrinsic handed a same-width integer corrupts the heap without raising — withheld rather than guessed."))
            return
        end
        push!(out, ProbeTarget(n, spelling, kind, lo, hi, known,
                               b !== nothing, b === nothing ? "" : b.reason))
    end
    # Builtins: every name in Core that resolves to one. `isdefined` guards each
    # lookup so the list is version-relative (names come and go across releases).
    for n in names(Core; all=true)
        isdefined(Core, n) || continue
        f = try getfield(Core, n) catch; continue end
        isbuiltinlike(f) || continue
        isa(f, Core.IntrinsicFunction) && continue    # enumerated below, via Core.Intrinsics
        add!(n, qualspelling("Core", n), f, :builtin)
        # The bare spelling is not a duplicate: `getfield(x, 1)` lowers to a
        # direct GlobalRef while `Core.getfield(x, 1)` lowers to a
        # `getproperty` chain, so the interpreter reaches the same builtin
        # through two different paths (function position as SSA value vs. a
        # literal), which is itself worth probing.
        if isdefined(Base, n) && (try getfield(Base, n) === f catch; false end)
            add!(n, barespelling(n), f, :builtin)
        end
    end
    # Intrinsics, both spellings for the same reason. `generate_builtins.jl`
    # mirrors them through Base as well.
    for n in names(Core.Intrinsics; all=true)
        n === :Intrinsics && continue
        isdefined(Core.Intrinsics, n) || continue
        f = try getfield(Core.Intrinsics, n) catch; continue end
        isa(f, Core.IntrinsicFunction) || continue
        add!(n, "Core.Intrinsics." * String(n), f, :intrinsic)
        if isdefined(Base, n) && (try getfield(Base, n) === f catch; false end)
            add!(n, "Base." * String(n), f, :intrinsic)
        end
    end
    for n in EXTRA_BASE_TARGETS
        isdefined(Base, n) || continue
        f = try getfield(Base, n) catch; continue end
        add!(n, "Base." * String(n), f, :extra)
    end
    return out, denied, fixedonly
end

# ---------------------------------------------------------------------------
# The safety denylist
#
# Read this as the answer to one question per entry: "what does an *arbitrary*
# generated value in this argument position do?". An ordinary generated value
# (Int/Float/String/struct) hitting a runtime TypeError is fine and wanted —
# that is the dispatch arm doing its job. A raw address dereference, an
# uncatchable trap, an unspecified result, or a mutation of shared runtime
# state is not: the first two kill the worker, the last two poison the oracle.

struct ProbeBan
    match::Any      # Symbol (exact name) or Regex (matched against the name)
    scope::Symbol   # :all — never rendered | :arbitrary — recipe-only |
                    # :fixed — vetted FIXED_PROBES template(s) only
    reason::String
end

const PROBE_BANS = ProbeBan[
    # -- uncatchable machine traps -----------------------------------------
    # Verified on 1.11.9: inside a compiled toplevel `let` (the shape render.jl
    # emits), `Core.Intrinsics.sdiv_int(7, d)` with `d == 0` dies with SIGILL
    # ("Unreachable reached", exit 132) — codegen lowers the UB to `unreachable`
    # and no `try` can catch it. The runtime intrinsic path *does* raise
    # DivideError, so the two engines also disagree by construction.
    # `÷`/`%` (rules :intdiv, :guarddiv) stay the sanctioned division probe.
    ProbeBan(:sdiv_int, :all, "raw machine divide: a zero (or typemin/-1) divisor is uncatchable UB — SIGILL/SIGFPE kills the worker (verified 1.11.9). Use the guarded ÷/% rules for division semantics."),
    ProbeBan(:udiv_int, :all, "raw machine divide: zero divisor is uncatchable UB (SIGILL, verified 1.11.9)."),
    ProbeBan(:srem_int, :all, "raw machine remainder: zero divisor is uncatchable UB (SIGILL, verified 1.11.9)."),
    ProbeBan(:urem_int, :all, "raw machine remainder: zero divisor is uncatchable UB (SIGILL, verified 1.11.9)."),
    # NOTE: checked_sdiv_int / checked_udiv_int / checked_srem_int /
    # checked_urem_int are deliberately NOT banned — measured on 1.11.9, all
    # four raise DivideError even when compiled, so they are exactly the
    # division probe the raw intrinsics cannot be.

    # -- raw memory / addresses --------------------------------------------
    # atomic_pointermodify is the one pointer intrinsic with a cold dispatch
    # arm the interpreter special-cases (world-pinning its `op` callback), so
    # it gets the narrowest possible exception: a FIXED_PROBES template that
    # creates its own Ref, roots it with GC.@preserve across the call, keeps
    # the ordering literal, and reads the result back out. A *recipe* cannot
    # do this — arguments are evaluated one by one, so a Ref created inside
    # the pointer argument is unrooted (collectible) by the time the intrinsic
    # runs, which is exactly the wild-write class the pointer ban exists for.
    # Verified on 1.12.6: identical results compiled and interpreted (rec and
    # cmp), at toplevel and inside a compiled function body.
    ProbeBan(:atomic_pointermodify, :fixed, "raw-address atomic: an arbitrary value in the pointer slot is a wild read/write like the rest of the pointer family, and per-argument recipes cannot GC-root a pointee across the call. Exercised only by the vetted FIXED_PROBES templates (own Ref + GC.@preserve + literal ordering; verified divergence-free on 1.12.6, toplevel and function context)."),
    ProbeBan(r"pointer", :all, "interprets its argument as a raw address (pointerref/pointerset/atomic_pointer*): a generated Int in the pointer slot is an arbitrary read or write — segfault or silent heap corruption, never a finding."),
    ProbeBan(r"_ptr$", :all, "pointer arithmetic (add_ptr/sub_ptr): meaningful only on raw addresses, one dereference from unsafe, and the values are class-X (engine-dependent)."),
    # llvmcall's dispatch arm stays cold by design. Malformed literal IR aborts
    # the process inside LLVM, and the dynamic (non-constant-argument) call is
    # a measured permanent-divergence class on 1.12.6: inside an interpreted
    # function a barriered `llvmcall("ret i64 %0", Int64, Tuple{Int64}, 3)`
    # *returns 3* while the compiled reference raises ErrorException, and junk
    # operands (`llvmcall(1, 2, 3)`) throw a TypeError that escapes the
    # program's own `try` on the interpreted side only. Behavior differs by
    # engine AND by toplevel-vs-function context, so no template exists that
    # both engines agree on — not even the error arm is probeable.
    ProbeBan(:llvmcall, :all, "compiles LLVM IR supplied as an argument: malformed IR aborts the process inside LLVM, and a dynamic call is a measured permanent divergence on 1.12.6 (interpreted returns a value / throws through the guard where the compiled reference raises ErrorException, depending on context). Unprobeable; its dispatch arm is documented cold."),
    ProbeBan(:cglobal, :all, "resolves a raw symbol address: the result is a Ptr (class X) and the call needs literal syntax to lower at all."),
    ProbeBan(r"^memoryref", :arbitrary, "MemoryRef family: with an unchecked (boundscheck=false) reference an out-of-range index is a wild read/write. Reachable only via recipes, which always pass a literal `true`."),
    ProbeBan(:memorynew, :all, "allocation size comes straight from an argument; typemax(Int) is in the literal menu, so the probe becomes an OOM/abort rather than a finding."),
    ProbeBan(:_svec_len, :all, "unchecked SimpleVector length read: on a non-svec argument compiled Julia type-checks and throws (TypeError) but Compiled mode's native call reads the length field of whatever object is passed and returns a raw address-magnitude integer — a class-X divergence, and the value is nondeterministic."),

    # -- class U: the contract itself permits the engines to differ ---------
    # (determinism.md §1/§8: no infrastructure fixes these; the only handles
    # are exclusion or recipe'd in-range arguments.)
    ProbeBan(:fptosi, :arbitrary, "unspecified result for NaN/out-of-range input (LLVM poison when compiled vs. the runtime intrinsic when interpreted) — class U. Recipe'd in-range floats only."),
    ProbeBan(:fptoui, :arbitrary, "unspecified result for NaN/negative/out-of-range input — class U. Recipe'd in-range floats only."),
    ProbeBan(r"_fast$", :all, "fast-math intrinsic: the contract licenses reassociation and contraction, so compiled and interpreted results may legally differ — class U."),
    ProbeBan(:muladd_float, :all, "fma-contraction license: codegen may fuse where the runtime intrinsic does not (the interpreter substitutes fma_float when the host has FMA) — class U."),

    # -- nondeterministic by nature ----------------------------------------
    ProbeBan(:finalizer, :all, "registers a callback the GC runs at a time that depends on allocation behaviour, which differs between the two engines (determinism.md §8) — excluded from value-observed probes."),

    # -- mutation of shared runtime state ----------------------------------
    ProbeBan(:_setsuper!, :all, "re-parents a type object in place: with a real DataType argument it corrupts the shared runtime for every later candidate in the worker."),
    ProbeBan(:_typebody!, :all, "completes a type definition in place; a partially-initialized type is a process-wide, silent corruption. Ordinary generated `struct` definitions already reach this arm through lowering."),
    # _equiv_typedef is NOT like its neighbors: it is a read-only equivalence
    # *predicate* over two type definitions, and — unlike _structtype/_typebody!
    # — generated programs never actually reach it, because lowering only calls
    # it when a struct name is being REdefined and every generated struct is
    # defined once in a fresh module (its dispatch arm measured cold across
    # 4000 candidate-runs, coverage-report.md). Measured on 1.12.6, compiled
    # and interpreted, toplevel and function context: real DataTypes return a
    # Bool, junk arguments (Ints) return false rather than crashing, repeated
    # calls leave the runtime healthy. Recipe-only regardless, so the shapes
    # stay vetted Type/struct-type arguments.
    ProbeBan(:_equiv_typedef, :arbitrary, "type-definition equivalence predicate: read-only (measured 1.12.6 — junk args return false, no runtime mutation), but unreachable from generated code (lowering calls it only on struct REdefinition), so recipes are the only way its arm executes. Kept recipe-only so the argument shapes stay vetted types."),
    ProbeBan(:_structtype, :all, "creates a type inside a module; reached anyway by every generated struct definition, and a hand-built one can be left incomplete."),
    ProbeBan(:_abstracttype, :all, "creates a type inside a module (see _structtype)."),
    ProbeBan(:_primitivetype, :all, "creates a type inside a module (see _structtype)."),
    ProbeBan(:define_method, :all, "defines a method: an arbitrary target would mutate a method table shared with the harness and every later candidate."),
    ProbeBan(:_defaultctors, :all, "defines constructors on a type (see define_method)."),
    ProbeBan(:declare_const, :all, "changes a binding's kind irreversibly (1.12+); a const-declared binding poisons the module for the rest of the run."),
    ProbeBan(:declare_global, :all, "changes a binding's kind irreversibly (1.12+); see declare_const."),
    ProbeBan(:_import, :all, "mutates a module's import table globally (1.12+)."),
    ProbeBan(:_using, :all, "mutates a module's import table globally (1.12+)."),

    # -- runaway type materialization --------------------------------------
    # Verified on 1.11.9: `Core.apply_type(Array, Int, typemax(Int))` and
    # `Core.apply_type(NTuple, typemax(Int), Int)` segfault the runtime, and
    # typemax(Int) is in both the literal menu and the generated-Int menu.
    ProbeBan(:apply_type, :arbitrary, "materializes a type from its arguments: a huge Int in a dimension/count slot segfaults the runtime (verified: apply_type(Array, Int, typemax(Int))). Recipes give it vetted constructor/parameter combinations, including the wrong-arity and wrong-type ones the old dictionary carried."),

    # -- inference blows up on statically-known-bad arguments ---------------
    # Measured on 1.11.9: `modifyglobal!(Symbol, s, s, :b)` — a *type* in the
    # module slot — makes inference of the Pair-shaped return type raise
    # ErrorException("Tuple field type cannot be Union{}") internally, after
    # which codegen emits `unreachable` for the call and the process dies with
    # SIGILL (found by this prober's own soak, candidate seed 471). The module
    # slot only ever holds a real module in real code, so recipes supply one:
    # `Base`/`Core` for the reads, `(@__MODULE__)` for the writes — the
    # program's own fresh module, which both engines have their own copy of.
    ProbeBan(r"global", :arbitrary, "takes a Module: an arbitrary value there is a TypeError at best, and a statically-known Type makes inference of the Pair-shaped return type fail internally, after which codegen emits `unreachable` (SIGILL, measured). Recipes name a real module — reads on Base/Core, writes on (@__MODULE__) under names the generator never emits."),
    ProbeBan(:get_binding_type, :arbitrary, "same module slot as the global family; with a statically-known non-module the TypeError is raised while the thunk is *compiled*, so it escapes the program's own `try` and shows up as a bogus ref_only_throw."),
    ProbeBan(:set_binding_type!, :arbitrary, "same module slot as the global family, and it mutates a binding's declared type."),
    ProbeBan(:modifyfield!, :arbitrary, "its Pair-shaped return type is what inference chokes on (see the global family): `Core.modifyfield!(Symbol, :a, +, 2)` raises an internal inference error. Recipes keep the target a real mutable value."),

    # -- known, deliberate interpreter limitations --------------------------
    # Found by this prober and confirmed by hand: with a first argument that is
    # not `iterate`, compiled Julia ignores it and applies the second argument
    # (`Core._apply_iterate(+, +, (1, 2)) == 3`), while `maybe_evaluate_builtin`
    # raises ErrorException("cannot handle `_apply_iterate` with non iterate as
    # first argument"). Lowering only ever emits `iterate` in that position, so
    # the interpreter's guard is unreachable from real code — probing it would
    # manufacture the same known divergence in every campaign instead of news.
    ProbeBan(:_apply_iterate, :arbitrary, "compiled Julia ignores a non-`iterate` first argument and applies the second; the interpreter deliberately errors on it (src/builtins.jl). Unreachable from lowered code, so an arbitrary first argument is a permanent known divergence, not a finding. Recipes always pass `Base.iterate`."),
]

# Version-robust intrinsic-arity guard. `atomic_fence` took one argument (the
# memory ordering) on 1.11–1.13, and the prober renders exactly that. Julia
# 1.14-DEV changed the intrinsic's signature, so `atomic_fence(:seq_cst)` is now
# a wrong-arity intrinsic call — and a wrong-arity intrinsic *at toplevel* (the
# shape render.jl emits) aborts compilation with an uncatchable "Internal error
# during compilation of top-level scope" that escapes the program's guard and
# kills the worker. Rather than hardcode a version, detect at load whether the
# single-ordering call the prober emits still compiles; ban the callee outright
# if it does not, so the prober self-calibrates to whatever Julia it runs on.
# (Intrinsic signatures are internal and carry no stability guarantee, so this
# is a harness-compatibility fix, not a Julia bug to report.)
function _probe_intrinsic_callable(f, args...)
    try
        Base.invokelatest(@eval (() -> $(Expr(:call, f, map(QuoteNode, args)...))))
        return true
    catch
        return false
    end
end

const _RUNTIME_PROBE_BANS = let bans = ProbeBan[]
    if @isdefined(Core) && isdefined(Core.Intrinsics, :atomic_fence) &&
       !_probe_intrinsic_callable(GlobalRef(Core.Intrinsics, :atomic_fence), :sequentially_consistent)
        push!(bans, ProbeBan(:atomic_fence, :all,
            "atomic_fence's intrinsic arity differs on this Julia ($(VERSION)); the prober's single-ordering call is wrong-arity here and aborts toplevel compilation uncatchably. Auto-banned by load-time detection."))
    end
    bans
end

banmatches(b::ProbeBan, name::Symbol) =
    b.match isa Symbol ? b.match === name : occursin(b.match::Regex, String(name))

function probeban(name::Symbol)
    for b in PROBE_BANS
        banmatches(b, name) && return b
    end
    for b in _RUNTIME_PROBE_BANS
        banmatches(b, name) && return b
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Argument material
#
# Adversarial-but-safe literals. Deliberately absent: modules (only recipes
# hand those to the global-binding builtins, and only `(@__MODULE__)` for the
# mutating ones), `Ptr` values, `Memory`/`MemoryRef` values, and the parametric
# constructors whose Int parameter materializes storage (`Array`, `NTuple`,
# `Vararg`) — the last three so that no future rule can rebuild the
# apply_type segfault out of pool material.

const PROBE_LITERALS = String[
    "nothing", "missing", "true", "false",
    "0", "1", "(-1)", "2", "3", "typemax(Int)", "typemin(Int)",
    "0x0f", "UInt8(3)", "Int8(-3)", "Int32(7)", "UInt(4)",
    "1.5", "(-0.0)", "NaN", "Inf", "Float32(1.5)", "Float16(2.0)",
    "\"\"", "\"abc\"", "'c'",
    ":a", ":b", ":x", ":fld1", ":not_a_field_zzz",
    "()", "(1, 2)", "(1, \"a\", :b)", "(a=1, b=2)",
    "[1, 2, 3]", "Any[1, \"a\"]", "1:3",
    "Ref(1)", "Base.RefValue{Int}(3)", "Core.svec(1, 2)",
    "identity", "+", "max", "Base.iterate", "Core.tuple",
    "Expr(:call, :+, 1, 2)", "QuoteNode(:a)",
]

const PROBE_TYPE_LITERALS = String[
    "Int", "Int8", "Int32", "UInt8", "UInt64", "Bool",
    "Float64", "Float32", "Float16", "String", "Symbol", "Char",
    "Any", "Number", "Integer", "AbstractString", "Nothing", "DataType",
    "Vector{Int}", "Tuple{Int,String}", "Union{Int,String}",
    "Type{Int}", "Val{3}", "Ref{Int}",
]
# `Union{}` is deliberately absent: as an argument it turns into a
# *compile-time* TypeError ("expected UnionAll, got Type{Union{}}" from
# `Core.tuple(Union{}, 1)`), raised while the enclosing thunk is compiled and
# therefore outside the program's own `try` — a bogus ref_only_throw. It is
# still reachable where a recipe knows it is safe (see :_typevar).

# A *filled* Memory, and a MemoryRef onto it. Never `undef`: an uninitialized
# Memory{Int} reads back whatever bytes the allocator handed out, which is not
# the same in the reference module and the interpreted one.
const MEM_SRC = "Base.fill!(Memory{Int}(undef, 4), 7)"
const MEMREF_SRC = "Core.memoryrefnew(" * MEM_SRC * ")"

# Only *valid* atomic ordering symbols. An invalid ordering (e.g.
# `:bogus_ordering_zzz`) is a known false-positive class, not an interpreter
# bug: when the compiled side can constant-fold the ordering (which depends on
# surrounding context and optimization), codegen validates it and throws
# `ErrorException("invalid atomic ordering")`; when it cannot, the runtime
# intrinsic throws `ConcurrencyViolationError`. The interpreter always defers to
# the runtime intrinsic, so its exception type is stable while the compiled
# side's is optimization-dependent. Wrong-*for-the-field* orderings
# (`:not_atomic` on an atomic field, etc.) remain — those are runtime-validated
# on both sides and agree, so they still probe the ordering-dispatch arms.
const PROBE_ORDERINGS = String[
    ":not_atomic", ":unordered", ":monotonic", ":acquire", ":release",
    ":acquire_release", ":sequentially_consistent",
]

# ---------------------------------------------------------------------------
# Optimizer barriers on probe arguments (DESIGN.md, prober section).
#
# `Base.compilerbarrier(:const, x)` passes `x` through unchanged but blocks
# constant propagation, so the compiled reference cannot constant-fold the call
# and must defer to the runtime builtin/intrinsic — exactly what the interpreter
# always does. Barriering a probe's arguments therefore (1) closes the class-U
# false-positive window where the reference folds constant operands to a
# *compile-time* error (a TypeError raised while the thunk is compiled, outside
# the program's own `try`) while the interpreter defers to the runtime intrinsic
# (an ErrorException), and (2) removes the reason the JI subprocess would have to
# adjudicate the divergence, since no divergence arises. `:const` is chosen over
# `:type`/`inferencebarrier` because it is *type*-preserving: a valid call stays
# valid and returns the same value, so barriers are value-preserving.
#
# The wrapping happens at render time (render.jl, the :probe branch); this
# predicate names the argument slots that must stay BARE literals instead.
# A barrier on one of these is worse than the class-U it removes — either a NEW
# compile-time error on the reference side, or a lost safety guarantee:
#
#   * CAST_INTRINSICS first arg — the target Type. Codegen reads the target
#     width from this slot; it must be a literal.
#   * atomic_fence — its sole argument is the memory ordering.
#   * atomic ordering symbols anywhere (the getfield/setfield!/swapfield!/…
#     field family, the *global family, and the memoryref* family all pass a
#     trailing ordering symbol) — kept literal so the ordering-dispatch phase is
#     the same on both sides.
#   * module references handed to the global-binding builtins (Base/Core/Main/
#     the program's own module) — left literal, there is no folding to defer and
#     no reason to perturb binding resolution.
#   * the memoryref* boundscheck flag (a literal `true`/`false`) — memory
#     safety: the recipes pass a literal `true` so an out-of-range index can
#     only ever raise BoundsError; that guarantee must not be weakened.
const PROBE_MODULE_LITERALS = Set{String}(["Base", "Core", "Main", "(@__MODULE__)"])

function probe_arg_mustbeliteral(spelling::AbstractString, slot::Int, arg::Ex)::Bool
    name = Symbol(last(split(spelling, '.')))
    name in CAST_INTRINSICS && slot == 1 && return true
    name === :atomic_fence && return true
    if arg.kind === :src
        s = strip(arg.meta::String)
        s in PROBE_ORDERINGS && return true
        s in PROBE_MODULE_LITERALS && return true
        startswith(String(name), "memoryref") && (s == "true" || s == "false") && return true
    end
    return false
end

psrc(s::AbstractString) = Ex(:src, AnyT(), String(s))
# A reference to something the *program* defines (a struct type, a generated
# function). Rendered like `psrc` would render it, but as a `:var` node, so
# shrinking can repair it: when the definition is removed, `repairex` replaces
# the reference with an inert default instead of leaving an UndefVarError.
nameref(n::Symbol) = Ex(:var, AnyT(), n)

# One probe argument: an in-scope generated value (structs, vectors, closures,
# tuples, symbols — whatever the program happens to hold), a freshly generated
# literal of a drawn summary, or an adversarial literal from the menus above.
function probearg(ctx::Ctx)::Ex
    rng = ctx.rng
    r = rand(rng)
    if r < 0.34
        vs = visiblevars(ctx)
        if !isempty(vs)
            v = pick(rng, vs)
            return Ex(:var, v.sum, v.name)
        end
    end
    if r < 0.62
        s = pick(rng, TySum[IntT, IntT, FloatT, BoolT, StrT, SymT, NothingT,
                            VecT(IntT), TupT(TySum[IntT, StrT]), FnT(TySum[IntT], AnyT())])
        return genleaf(ctx, s)
    end
    r < 0.88 && return psrc(pick(rng, PROBE_LITERALS))
    return psrc(pick(rng, PROBE_TYPE_LITERALS))
end

# Arity sweep: a correct-looking arity most of the time (the tfunc tables say
# what "correct-looking" is), an off-by-one or outright malformed one the rest.
#
# INTRINSICS ARE THE EXCEPTION, and it is a hard one: an intrinsic call site
# with the wrong operand count is not a runtime error, it is a *codegen* error.
# Measured on 1.11.9, `Core.Intrinsics.add_int(1)` inside a compiled function
# body or a compiled toplevel `let` prints "Internal error: encountered
# unexpected error during compilation ... intrinsic #2 add_int: wrong number of
# arguments" and aborts the process (exit 139) — on the *reference* side, before
# the interpreter is ever consulted. Builtins have no such problem (every wrong
# arity tested raises a catchable ArgumentError), so the malformed half of the
# sweep applies to them only.
function probearity(ctx::Ctx, t::ProbeTarget)
    rng = ctx.rng
    if t.kind === :intrinsic
        return rand(rng, t.minarg:t.maxarg)
    end
    # Floor of one argument when the tables know nothing about this builtin:
    # the untabled internal ones (`_call_latest`, `_apply_pure`) segfault on an
    # empty argument list rather than raising ArgumentError.
    floor = t.arityknown ? 0 : 1
    lo = clamp(t.minarg, floor, 4)
    hi = clamp(t.maxarg, lo, 4)
    r = rand(rng)
    r < 0.55 && return rand(rng, lo:hi)
    r < 0.80 && return clamp(rand(rng, Bool) ? hi + 1 : lo - 1, floor, 5)
    return rand(rng, floor:4)
end

# ---------------------------------------------------------------------------
# Recipes: plausible argument shapes for the builtins worth reaching a success
# path in. Each entry is `ctx -> Vector{Ex}`. Wrong arities and wrong orderings
# live here too — they are curated knowledge migrated from the old dictionary,
# not accidents of the sweep.

structvars(ctx::Ctx) = [v for v in visiblevars(ctx) if v.sum isa StructT]

# A (variable, field index) pair off some in-scope struct value, or nothing.
function pickfield(ctx::Ctx)
    vs = structvars(ctx)
    isempty(vs) && return nothing
    v = pick(ctx.rng, vs)
    s = v.sum::StructT
    i = rand(ctx.rng, 1:length(s.fieldnames))
    return (v, s, i)
end

fieldorder(s::StructT, i::Int) = s.atomicmask[i] ? ":sequentially_consistent" : ":not_atomic"

const PROBE_RECIPES = Dict{Symbol,Vector{Function}}(
    :getfield => Function[
        ctx -> Ex[psrc("(1, 2, 3)"), psrc(string(rand(ctx.rng, 1:4)))],
        ctx -> Ex[psrc("(a=1, b=2)"), psrc(pick(ctx.rng, [":a", ":b", ":c"]))],
        ctx -> Ex[psrc("Ref(1)"), psrc(":x")],
        ctx -> Ex[psrc("Ref(1)"), psrc(":x"), psrc(pick(ctx.rng, PROBE_ORDERINGS))],
        ctx -> Ex[probearg(ctx), psrc(":x")],
        function (ctx)
            f = pickfield(ctx)
            f === nothing && return Ex[psrc("(1, 2)"), psrc("1")]
            v, s, i = f
            return Ex[Ex(:var, v.sum, v.name), psrc(":" * String(s.fieldnames[i]))]
        end,
        function (ctx)
            f = pickfield(ctx)
            f === nothing && return Ex[psrc("(1, 2)"), psrc("2")]
            v, s, i = f
            return Ex[Ex(:var, v.sum, v.name), psrc(":" * String(s.fieldnames[i])),
                      psrc(fieldorder(s, i))]
        end,
    ],
    :setfield! => Function[
        ctx -> Ex[psrc("Ref(1)"), psrc(":x"), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("Ref(1)"), psrc(":x"), genleaf(ctx, IntT), psrc(pick(ctx.rng, PROBE_ORDERINGS))],
        ctx -> Ex[psrc("Ref(1)"), psrc(":x")],                       # wrong arity
        ctx -> Ex[psrc("(1, 2)"), psrc("1"), genleaf(ctx, IntT)],    # immutable target
        function (ctx)
            f = pickfield(ctx)
            f === nothing && return Ex[psrc("Ref(1)"), psrc(":x"), psrc("5")]
            v, s, i = f
            return Ex[Ex(:var, v.sum, v.name), psrc(":" * String(s.fieldnames[i])),
                      genleaf(ctx, s.fieldsums[i])]
        end,
    ],
    :fieldtype => Function[
        ctx -> Ex[psrc("Tuple{Int,String}"), psrc(string(rand(ctx.rng, 1:3)))],
        ctx -> Ex[psrc("Int"), psrc("1")],
        ctx -> Ex[psrc(pick(ctx.rng, PROBE_TYPE_LITERALS)), psrc("1")],
        function (ctx)
            isempty(ctx.structs) && return Ex[psrc("Tuple{Int,String}"), psrc("2")]
            s = pick(ctx.rng, ctx.structs)
            return Ex[nameref(s.name), psrc(string(rand(ctx.rng, 1:length(s.fieldnames))))]
        end,
    ],
    :isdefined => Function[
        ctx -> Ex[psrc("Ref(1)"), psrc(":x")],
        ctx -> Ex[psrc("Base"), psrc(":pi")],
        ctx -> Ex[psrc("Base"), psrc(":definitely_not_a_name_xyz")],
        ctx -> Ex[psrc("Base"), psrc(":pi"), psrc(pick(ctx.rng, PROBE_ORDERINGS))],
        function (ctx)
            f = pickfield(ctx)
            f === nothing && return Ex[psrc("Ref(1)"), psrc(":x")]
            v, s, i = f
            return Ex[Ex(:var, v.sum, v.name), psrc(":" * String(s.fieldnames[i]))]
        end,
    ],
    :tuple => Function[
        ctx -> Ex[],
        ctx -> Ex[probearg(ctx)],
        ctx -> Ex[probearg(ctx), probearg(ctx)],
        ctx -> Ex[probearg(ctx), probearg(ctx), probearg(ctx)],
    ],
    # The zero-argument form is a dedicated arm in src/builtins.jl (it splices
    # the frame's scopes). The arity sweep floors unknown-arity builtins at one
    # argument, so the empty call has to come from here.
    :current_scope => Function[
        ctx -> Ex[],
        ctx -> Ex[probearg(ctx)],
    ],
    :svec => Function[
        ctx -> Ex[psrc("1"), psrc("2"), psrc("3")],
        ctx -> Ex[probearg(ctx)],
    ],
    :_svec_ref => Function[
        ctx -> Ex[psrc("Core.svec(1, 2, 3)"), psrc(string(rand(ctx.rng, 0:5)))],
    ],
    # RECIPE-ONLY: every shape passes `Base.iterate` first — see the ban entry.
    :_apply_iterate => Function[
        ctx -> Ex[psrc("Base.iterate"), psrc(pick(ctx.rng, ["+", "Core.tuple", "max", "identity"])),
                  psrc("(1, 2)"), psrc("(3, 4)")],
        ctx -> Ex[psrc("Base.iterate"), psrc("Core.tuple"), genleaf(ctx, VecT(IntT))],
        ctx -> Ex[psrc("Base.iterate"), psrc("+")],                   # applied to nothing
        ctx -> Ex[psrc("Base.iterate"), probearg(ctx), psrc("(1, 2)")],
        function (ctx)
            vs = [v for v in visiblevars(ctx) if v.sum isa FnT && arity(v.sum::FnT) == 1]
            isempty(vs) && return Ex[psrc("Base.iterate"), psrc("identity"), psrc("(1,)")]
            v = pick(ctx.rng, vs)
            return Ex[psrc("Base.iterate"), Ex(:var, v.sum, v.name), psrc("(3,)")]
        end,
    ],
    # apply_type is recipe-only: see the PROBE_BANS entry. Every parameter that
    # can materialize storage (an Array dimension, an NTuple count) stays a
    # small literal here; generated values only reach parameters that cannot.
    :apply_type => Function[
        ctx -> Ex[psrc("Val"), psrc(string(rand(ctx.rng, 0:3)))],
        ctx -> Ex[psrc("Val")],
        ctx -> Ex[psrc("Val"), genleaf(ctx, SymT)],
        ctx -> Ex[psrc("Val"), psrc("\"x\"")],
        ctx -> Ex[psrc("Array"), psrc(pick(ctx.rng, PROBE_TYPE_LITERALS)), psrc(string(rand(ctx.rng, 1:2)))],
        ctx -> Ex[psrc("Union"), psrc("Int"), psrc("String")],
        ctx -> Ex[psrc("Tuple"), psrc("Int"), psrc("Vararg{Int}")],
        ctx -> Ex[psrc("Ref"), psrc(pick(ctx.rng, PROBE_TYPE_LITERALS))],
        ctx -> Ex[psrc("Int"), psrc("Int")],                          # not a UnionAll
        ctx -> Ex[],
        function (ctx)
            isempty(ctx.structs) && return Ex[psrc("Ref"), psrc("Int")]
            s = pick(ctx.rng, ctx.structs)
            return Ex[nameref(s.name)]
        end,
    ],
    :invoke => Function[
        ctx -> Ex[psrc("abs"), psrc("Tuple{Int}"), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("+"), psrc("Tuple{Int,Int}"), genleaf(ctx, IntT), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("abs"), psrc("Tuple{Float64}"), psrc("(-3)")],  # signature miss
        ctx -> Ex[psrc("abs"), psrc("Tuple{Int}")],                    # wrong arity
        # invoke into a *generated* method: the interpreted-callee path
        function (ctx)
            cands = [f for f in ctx.fns
                     if !isempty(f.sigs) && !isempty(f.sigs[1]) &&
                        all(s -> s isa ConcT, f.sigs[1])]
            isempty(cands) && return Ex[psrc("abs"), psrc("Tuple{Int}"), psrc("(-3)")]
            f = pick(ctx.rng, cands)
            sig = f.sigs[1]
            tt = "Tuple{" * join([typename(s::ConcT) for s in sig], ",") * "}"
            return Ex[nameref(f.name), psrc(tt), Ex[genleaf(ctx, s) for s in sig]...]
        end,
    ],
    :invokelatest => Function[
        ctx -> Ex[psrc("*"), psrc("6"), psrc("7")],
        ctx -> Ex[psrc("identity"), probearg(ctx)],
        ctx -> Ex[],
        function (ctx)
            isempty(ctx.fns) && return Ex[psrc("+"), genleaf(ctx, IntT), genleaf(ctx, IntT)]
            f = pick(ctx.rng, ctx.fns)
            sig = f.sigs[1]
            return Ex[nameref(f.name), Ex[genleaf(ctx, s isa AnyT ? IntT : s) for s in sig]...]
        end,
    ],
    # The atomics field family: hand-written per-arity dispatch in
    # src/builtins.jl, so every arity, the wrong arities, and ordering
    # violations on non-atomic fields are all worth rendering.
    :swapfield! => Function[
        ctx -> Ex[psrc("Ref(3)"), psrc(":x"), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("Ref(3)"), psrc(":x"), genleaf(ctx, IntT), psrc(pick(ctx.rng, PROBE_ORDERINGS))],
        ctx -> Ex[psrc("Ref(3)"), psrc(":x")],
        function (ctx)
            f = pickfield(ctx)
            f === nothing && return Ex[psrc("Ref(3)"), psrc(":x"), psrc("7")]
            v, s, i = f
            return Ex[Ex(:var, v.sum, v.name), psrc(":" * String(s.fieldnames[i])),
                      genleaf(ctx, s.fieldsums[i]), psrc(fieldorder(s, i))]
        end,
    ],
    :modifyfield! => Function[
        ctx -> Ex[psrc("Ref(2)"), psrc(":x"), psrc("+"), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("Ref(2)"), psrc(":x"), psrc("+"), genleaf(ctx, IntT),
                  psrc(pick(ctx.rng, PROBE_ORDERINGS))],
        ctx -> Ex[psrc("Ref(2)"), psrc(":x"), psrc("+")],
        function (ctx)
            f = pickfield(ctx)
            f === nothing && return Ex[psrc("Ref(2)"), psrc(":x"), psrc("+"), psrc("5")]
            v, s, i = f
            return Ex[Ex(:var, v.sum, v.name), psrc(":" * String(s.fieldnames[i])),
                      psrc(pick(ctx.rng, ["+", "-", "max", "identity"])),
                      genleaf(ctx, s.fieldsums[i]), psrc(fieldorder(s, i))]
        end,
    ],
    :replacefield! => Function[
        ctx -> Ex[psrc("Ref(1)"), psrc(":x"), psrc("1"), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("Ref(1)"), psrc(":x"), psrc("2"), genleaf(ctx, IntT)],   # expected mismatch
        ctx -> Ex[psrc("Ref(1)"), psrc(":x"), psrc("1"), genleaf(ctx, IntT),
                  psrc(":sequentially_consistent"), psrc(":sequentially_consistent")],
        ctx -> Ex[psrc("Ref(1)"), psrc(":x"), psrc("1")],
    ],
    :setfieldonce! => Function[
        ctx -> Ex[psrc("Ref(1)"), psrc(":x"), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("Ref(1)"), psrc(":x"), genleaf(ctx, IntT),
                  psrc(":not_atomic"), psrc(":not_atomic")],
        function (ctx)
            f = pickfield(ctx)
            f === nothing && return Ex[psrc("Ref(1)"), psrc(":x"), psrc("5")]
            v, s, i = f
            return Ex[Ex(:var, v.sum, v.name), psrc(":" * String(s.fieldnames[i])),
                      genleaf(ctx, s.fieldsums[i])]
        end,
    ],
    # Global-binding builtins. Reads may name any module; *writes* only ever
    # name the program's own module (both engines run the same source in their
    # own fresh module, so the effect is identical on both sides) and only
    # under names the generator never emits, so a probe cannot clobber a
    # program binding or the harness's own __OBS__.
    :getglobal => Function[
        ctx -> Ex[psrc("Base"), psrc(":pi")],
        ctx -> Ex[psrc("Base"), psrc(":definitely_not_a_name_xyz")],
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz")],
        ctx -> Ex[psrc("Core"), psrc(":Int"), psrc(pick(ctx.rng, PROBE_ORDERINGS))],
    ],
    :setglobal! => Function[
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz"), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz"), probearg(ctx),
                  psrc(pick(ctx.rng, PROBE_ORDERINGS))],
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz")],
    ],
    :swapglobal! => Function[
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz"), genleaf(ctx, IntT)],
    ],
    :modifyglobal! => Function[
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz"), psrc("+"), genleaf(ctx, IntT)],
    ],
    :replaceglobal! => Function[
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz"), psrc("1"), genleaf(ctx, IntT)],
    ],
    :setglobalonce! => Function[
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz"), genleaf(ctx, IntT)],
    ],
    :get_binding_type => Function[
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz")],
        ctx -> Ex[psrc("Base"), psrc(":pi")],
    ],
    :set_binding_type! => Function[
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz")],
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz"), psrc("Int")],
    ],
    :isdefinedglobal => Function[
        ctx -> Ex[psrc("Base"), psrc(":pi")],
        ctx -> Ex[psrc("(@__MODULE__)"), psrc(":__probe_g_zzz")],
    ],
    :applicable => Function[
        ctx -> Ex[psrc("+"), genleaf(ctx, IntT), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("abs"), probearg(ctx)],
        function (ctx)
            isempty(ctx.fns) && return Ex[psrc("+"), psrc("1"), psrc("2")]
            f = pick(ctx.rng, ctx.fns)
            return Ex[nameref(f.name), Ex[probearg(ctx) for _ in f.sigs[1]]...]
        end,
    ],
    # Valid settings only. An *unknown* setting is rejected by codegen but
    # accepted by the runtime builtin the interpreter calls
    # (`Core.compilerbarrier(:bogus, 1)`: ErrorException compiled, `1`
    # interpreted) — the same known, invalid-input-only divergence class as
    # `_apply_iterate`'s first argument.
    :compilerbarrier => Function[
        ctx -> Ex[psrc(pick(ctx.rng, [":const", ":type", ":conditional"])), probearg(ctx)],
    ],
    :typeassert => Function[
        ctx -> Ex[genleaf(ctx, IntT), psrc("Int")],
        ctx -> Ex[genleaf(ctx, IntT), psrc(pick(ctx.rng, PROBE_TYPE_LITERALS))],
        ctx -> Ex[probearg(ctx), psrc(pick(ctx.rng, PROBE_TYPE_LITERALS))],
    ],
    :ifelse => Function[
        ctx -> Ex[genleaf(ctx, BoolT), probearg(ctx), probearg(ctx)],
        ctx -> Ex[psrc("1"), psrc("2"), psrc("3")],
    ],
    :isa => Function[
        ctx -> Ex[probearg(ctx), psrc(pick(ctx.rng, PROBE_TYPE_LITERALS))],
    ],
    :throw => Function[
        ctx -> Ex[probearg(ctx)],
        ctx -> Ex[psrc("ArgumentError(\"probe\")")],
    ],
    :_typevar => Function[
        ctx -> Ex[psrc(":T"), psrc("Union{}"), psrc("Any")],
        ctx -> Ex[psrc(":T"), psrc("Int"), psrc("Int")],
    ],
    :_expr => Function[
        ctx -> Ex[psrc(":call"), psrc(":+"), psrc("1"), psrc("2")],
    ],
    # RECIPE-ONLY (see the ban): a pure equivalence predicate over two type
    # definitions, unreachable from generated code because lowering calls it
    # only on struct REdefinition. Vetted Type arguments only; identical Bool
    # results measured on 1.12.6 compiled and interpreted, both modes.
    :_equiv_typedef => Function[
        ctx -> Ex[psrc("Int"), psrc("Int")],
        ctx -> Ex[psrc("Int"), psrc("Float64")],
        ctx -> Ex[psrc(pick(ctx.rng, PROBE_TYPE_LITERALS)),
                  psrc(pick(ctx.rng, PROBE_TYPE_LITERALS))],
        function (ctx)
            isempty(ctx.structs) && return Ex[psrc("Base.RefValue{Int}"), psrc("Base.RefValue{Int}")]
            s = pick(ctx.rng, ctx.structs)
            return Ex[nameref(s.name), nameref(s.name)]
        end,
    ],
    # Success path for the sweep-reachable internals below: the sweep's junk
    # arguments raise a symmetric TypeError (measured 1.12.6, both engines),
    # which exercises only the error arm; these shapes return real values —
    # an (empty) sparams svec, and the applied function's result.
    :_compute_sparams => Function[
        ctx -> Ex[psrc("which(first, Tuple{Vector{Int}})"), psrc("[1, 2]")],
        ctx -> Ex[psrc("which(identity, Tuple{Any})"), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("which(zero, Tuple{Type{Int}})"), psrc("Int")],
        ctx -> Ex[probearg(ctx), probearg(ctx)],       # symmetric TypeError arm
    ],
    # The world argument is drawn at run time on each side; only the *applied
    # call's* result is observed, so both engines agree. A junk world is a
    # symmetric TypeError; the single-argument call raises a catchable
    # ArgumentError on both sides (measured 1.12.6 — unlike _call_latest/
    # _apply_pure, whose empty argument list segfaults, see probearity).
    :_call_in_world_total => Function[
        ctx -> Ex[psrc("Base.get_world_counter()"), psrc("+"),
                  genleaf(ctx, IntT), genleaf(ctx, IntT)],
        ctx -> Ex[psrc("Base.get_world_counter()"), psrc("identity"), probearg(ctx)],
        ctx -> Ex[psrc("Base.get_world_counter()"), psrc("Core.tuple")],
    ],
    # RECIPE-ONLY, class U: in-range finite values only. Out-of-range or NaN
    # input is an *unspecified* result and would be a permanent false positive.
    :fptosi => Function[
        ctx -> Ex[psrc(pick(ctx.rng, ["Int8", "Int32", "Int64"])),
                  psrc(pick(ctx.rng, ["1.0", "(-3.0)", "42.0", "100.0"]))],
    ],
    :fptoui => Function[
        ctx -> Ex[psrc(pick(ctx.rng, ["UInt8", "UInt32", "UInt64"])),
                  psrc(pick(ctx.rng, ["1.0", "3.0", "42.0", "100.0"]))],
    ],
    # RECIPE-ONLY, memory safety: the boundscheck flag is a literal `true` in
    # every shape below, and no MemoryRef ever enters the generic argument pool,
    # so an out-of-range index can only ever raise BoundsError.
    #
    # The memory is *filled* (MEM_SRC), never `undef`: reading an
    # uninitialized Memory{Int} yields whatever heap bytes were there, which
    # differs between the reference module and the interpreted one — a
    # value_divergence that is pure noise (caught in the first soak). The
    # `Memory{Any}` shapes below read a genuinely unset slot instead, which is a
    # *deterministic* UndefRefError.
    :memoryrefnew => Function[
        ctx -> Ex[psrc(MEM_SRC)],
        ctx -> Ex[psrc("Core.memoryrefnew(" * MEM_SRC * ")"),
                  psrc(string(rand(ctx.rng, 1:4))), psrc("true")],
        ctx -> Ex[psrc("Core.memoryrefnew(" * MEM_SRC * ")"), psrc("9"), psrc("true")],
    ],
    :memoryrefget => Function[
        ctx -> Ex[psrc(MEMREF_SRC), psrc(":not_atomic"), psrc("true")],
        ctx -> Ex[psrc(MEMREF_SRC), psrc(pick(ctx.rng, PROBE_ORDERINGS)), psrc("true")],
        ctx -> Ex[psrc("Core.memoryrefnew(Memory{Any}(undef, 2))"), psrc(":not_atomic"), psrc("true")],
    ],
    :memoryrefset! => Function[
        ctx -> Ex[psrc(MEMREF_SRC), genleaf(ctx, IntT), psrc(":not_atomic"), psrc("true")],
        ctx -> Ex[psrc(MEMREF_SRC), psrc("\"x\""), psrc(":not_atomic"), psrc("true")],
    ],
    :memoryrefoffset => Function[
        ctx -> Ex[psrc(MEMREF_SRC)],
    ],
    :memoryref_isassigned => Function[
        ctx -> Ex[psrc(MEMREF_SRC), psrc(":not_atomic"), psrc("true")],
        ctx -> Ex[psrc("Core.memoryrefnew(Memory{Any}(undef, 2))"), psrc(":not_atomic"), psrc("true")],
    ],
    :memoryrefswap! => Function[
        ctx -> Ex[psrc(MEMREF_SRC), genleaf(ctx, IntT), psrc(":not_atomic"), psrc("true")],
    ],
    :memoryrefmodify! => Function[
        ctx -> Ex[psrc(MEMREF_SRC), psrc("+"), genleaf(ctx, IntT), psrc(":not_atomic"), psrc("true")],
    ],
    :memoryrefreplace! => Function[
        ctx -> Ex[psrc(MEMREF_SRC), psrc("7"), genleaf(ctx, IntT),
                  psrc(":not_atomic"), psrc(":not_atomic"), psrc("true")],
    ],
    :memoryrefsetonce! => Function[
        ctx -> Ex[psrc("Core.memoryrefnew(Memory{Any}(undef, 2))"), genleaf(ctx, IntT),
                  psrc(":not_atomic"), psrc(":not_atomic"), psrc("true")],
    ],
    :memoryrefunset! => Function[
        ctx -> Ex[psrc("Core.memoryrefnew(Memory{Any}(undef, 2))"), psrc(":not_atomic"), psrc("true")],
    ],
)

# ---------------------------------------------------------------------------
# Intrinsic argument shapes
#
# Intrinsics are typed far more narrowly than builtins: a plausible call is
# "the right number of operands, all of the right primitive kind". Deriving
# that from the name (which is how Julia names them) means the intrinsic arms
# see success paths without a per-intrinsic table.

const CAST_INTRINSICS = Set{Symbol}([
    :trunc_int, :sext_int, :zext_int, :bitcast, :fptrunc, :fpext,
    :sitofp, :uitofp, :fptosi, :fptoui,
])
const INT_TYPE_LITERALS = String["Int8", "Int16", "Int32", "Int64", "UInt8", "UInt32", "UInt64"]
const FLOAT_TYPE_LITERALS = String["Float16", "Float32", "Float64"]

intarg(ctx::Ctx) = rand(ctx.rng) < 0.5 ? genleaf(ctx, IntT) :
                   psrc(pick(ctx.rng, ["0", "1", "(-1)", "3", "7", "typemax(Int)", "typemin(Int)",
                                       "Int8(3)", "UInt(5)", "0x0f", "true"]))
floatarg(ctx::Ctx) = rand(ctx.rng) < 0.5 ? genleaf(ctx, FloatT) :
                     psrc(pick(ctx.rng, ["0.0", "(-0.0)", "1.5", "(-2.5)", "NaN", "Inf",
                                         "Float32(1.5)", "floatmax(Float64)"]))
# Width-pinned variants. The five bitsize-relational casts below check their
# operand widths *during compilation* when the types are statically known, and
# that error is raised while the enclosing thunk is being compiled — outside
# the program's own `try`, so it escapes the guard and kills the reference run
# (measured: `fptrunc(Float32, Float32(1.5))` exits 1 with "output bitsize must
# be < input bitsize"). Every shape emitted here satisfies the relation.
int64arg(ctx::Ctx) = rand(ctx.rng) < 0.5 ? genleaf(ctx, IntT) :
                     psrc(pick(ctx.rng, ["0", "1", "(-1)", "3", "typemax(Int)", "typemin(Int)",
                                         "Int64(4607182418800017408)"]))
float64arg(ctx::Ctx) = rand(ctx.rng) < 0.5 ? genleaf(ctx, FloatT) :
                       psrc(pick(ctx.rng, ["0.0", "(-0.0)", "1.5", "(-2.5)", "NaN", "Inf",
                                           "floatmax(Float64)"]))

# `nothing` means "no shape known" — the caller falls back to the generic sweep.
function intrinsic_args(ctx::Ctx, t::ProbeTarget)
    rng = ctx.rng
    n = String(t.name)
    # Exact arity, never clamped: see probearity — an intrinsic call site with
    # the wrong operand count aborts the process inside codegen.
    lo, hi = t.minarg, t.maxarg
    nargs = lo == hi ? lo : rand(rng, lo:hi)
    if t.name in CAST_INTRINSICS
        # (target type, value). Width relations are respected by construction —
        # see the int64arg/float64arg comment: violating one is a *compile-time*
        # error on the reference side, which no `try` in the program can catch.
        if t.name === :bitcast          # equal widths (mismatch is catchable)
            return rand(rng) < 0.5 ? Ex[psrc("Float64"), int64arg(ctx)] :
                                     Ex[psrc("Int64"), float64arg(ctx)]
        elseif t.name === :fptrunc      # output width < input width
            return Ex[psrc(pick(rng, ["Float32", "Float16"])), float64arg(ctx)]
        elseif t.name === :fpext        # output width >= input width
            return rand(rng) < 0.5 ? Ex[psrc("Float64"), float64arg(ctx)] :
                Ex[psrc("Float64"), psrc(pick(rng, ["Float32(1.5)", "Float16(2.0)", "Float32(NaN)"]))]
        elseif t.name === :trunc_int    # output width < input width
            return Ex[psrc(pick(rng, ["Int8", "Int16", "Int32", "UInt8", "UInt32"])), int64arg(ctx)]
        elseif t.name === :sext_int || t.name === :zext_int   # output width > input width
            return Ex[psrc(pick(rng, ["Int64", "UInt64"])),
                      psrc(pick(rng, ["Int8(3)", "Int8(-3)", "UInt8(200)", "Int32(70000)",
                                      "UInt32(5)", "true"]))]
        elseif t.name === :sitofp || t.name === :uitofp
            return Ex[psrc(pick(rng, FLOAT_TYPE_LITERALS)), intarg(ctx)]
        end
        return Ex[psrc(pick(rng, INT_TYPE_LITERALS)), intarg(ctx)]
    end
    if t.name === :have_fma
        return Ex[psrc(pick(rng, FLOAT_TYPE_LITERALS))]
    end
    if t.name === :atomic_fence
        return Ex[psrc(pick(rng, PROBE_ORDERINGS))]
    end
    if endswith(n, "_int")
        return sametype_intargs(ctx, nargs)
    end
    if endswith(n, "_float") || endswith(n, "_llvm") || n == "fpiseq"
        return sametype_floatargs(ctx, nargs)
    end
    return nothing
end

# A binary/n-ary numeric intrinsic requires *all* operands to share one type.
# Drawing each operand independently (an Int64 leaf here, an Int8(3) there) makes
# a mismatched call. Without barriers a mismatch was a class-U false positive,
# not an interpreter bug: when the reference could constant-fold the operands it
# validated the type mismatch at *compile time* and raised a TypeError from
# inside the thunk (outside the program's `try`), while the interpreter deferred
# to the runtime intrinsic and raised an ErrorException — and which happened
# depended on optimization. That fold requires constant *values*; the probe
# argument barrier (`Base.compilerbarrier(:const, …)`, render.jl) blocks
# constant propagation, so the reference can no longer fold and both engines
# raise the same runtime ErrorException. RE-ENABLED under barriers: a fraction of
# calls now draw mixed operand types on purpose, exercising the mismatched-type
# dispatch arm the same-type-only fix had to exclude. Verified: 286 barriered
# mismatched numeric-intrinsic calls through run_both, 0 divergences. The
# majority stays same-typed so the arms still see success paths (real arithmetic,
# not only the error arm).
intmixarg(ctx::Ctx) = psrc(pick(ctx.rng,
    ["1", "Int8(1)", "Int16(2)", "Int32(3)", "Int64(4)", "UInt8(5)", "UInt32(6)"]))
floatmixarg(ctx::Ctx) = psrc(pick(ctx.rng,
    ["1.5", "1.0f0", "Float16(2.0)", "2.0", "Float32(3.0)"]))
function sametype_intargs(ctx::Ctx, nargs::Int)
    rng = ctx.rng
    # mixed widths/signs — safe only because every operand is barriered
    nargs >= 2 && rand(rng) < 0.3 && return Ex[intmixarg(ctx) for _ in 1:nargs]
    rand(rng) < 0.5 && return Ex[genleaf(ctx, IntT) for _ in 1:nargs]   # all Int64
    T = pick(rng, INT_TYPE_LITERALS)
    return Ex[psrc(string(T, "(", pick(rng, ("0", "1", "2", "3", "7")), ")")) for _ in 1:nargs]
end
function sametype_floatargs(ctx::Ctx, nargs::Int)
    rng = ctx.rng
    nargs >= 2 && rand(rng) < 0.3 && return Ex[floatmixarg(ctx) for _ in 1:nargs]
    rand(rng) < 0.5 && return Ex[genleaf(ctx, FloatT) for _ in 1:nargs]  # all Float64
    T = pick(rng, FLOAT_TYPE_LITERALS)
    return Ex[psrc(string(T, "(", pick(rng, ("0.0", "1.5", "2.0", "NaN", "Inf")), ")")) for _ in 1:nargs]
end

# Does `intrinsic_args` know what this intrinsic's operands look like? An
# intrinsic whose operand kinds we cannot name must not be probed at all: the
# generic argument pool would eventually hand a float operation an integer of
# the same width, which the runtime does not check and which corrupts the heap
# (see probeargs). Kept in sync with the branches of `intrinsic_args`.
function intrinsic_shape_known(name::Symbol)
    name in CAST_INTRINSICS && return true
    (name === :have_fma || name === :atomic_fence) && return true
    n = String(name)
    return endswith(n, "_int") || endswith(n, "_float") || endswith(n, "_llvm") ||
           n == "fpiseq"
end

# ---------------------------------------------------------------------------
# Fixed templates: curated probes that are not a plain `callee(args...)` call,
# migrated verbatim from the old BUILTIN_PROBES dictionary.

const FIXED_PROBES = String[
    # opaque closures lower to :new_opaque_closure, a dedicated interpreter path
    "(Base.Experimental.@opaque x -> x + 1)(41)",
    "(Base.Experimental.@opaque (a, b) -> a * b)(6, 7)",
    # Memory basics (1.11+; on older Julia both sides throw UndefVarError — symmetric)
    "length(Memory{Int}(undef, 3))",
    "let m = Memory{Int}(undef, 2); m[1] = 5; m[1] end",
    # the atomics family's Pair/NamedTuple returns, projected to a value
    "first(Core.modifyfield!(Ref(2), :x, +, 5))",
    "Core.replacefield!(Ref(1), :x, 1, 9).success",
    # world-age / dispatch entry points
    "Base.invokelatest(*, 6, 7)",
    # conversion and reinterpretation. unsafe_trunc is IN RANGE on purpose: an
    # out-of-range result is *unspecified* (LLVM poison when compiled vs. the
    # runtime intrinsic when interpreted), i.e. a nondeterministic false positive.
    "reinterpret(Float64, Int64(0))",
    "Int8(300)",
    "trunc(Int8, 300.0)",
    "unsafe_trunc(Int8, 100.0)",
    "ntuple(identity, 3)",
    "ntuple(identity, 0)",
    "objectid(nothing) isa UInt",
    "Base.arrayref(true, [1,2,3], 4)",
    "Base.inferencebarrier(3) + 1",
    "Base.donotdelete(1)",
    "typeof(typeof(1))",
    "1 isa DataType",
    "getindex((1, 2, 3))",
    # atomic_pointermodify (a cold dispatch arm; the interpreter world-pins its
    # `op` callback) on a pointer the probe itself creates AND roots: the Ref
    # is held live by GC.@preserve across the call, the ordering stays a
    # literal, and the pointee/Pair is read back as the observed value. This is
    # the `:fixed` ban scope in action — a per-argument recipe cannot root the
    # pointee, so this template is the only sanctioned spelling. Verified on
    # 1.12.6: identical results compiled and interpreted (rec and cmp),
    # toplevel and inside a compiled function body.
    "let r = Ref(7); GC.@preserve r begin p = Base.unsafe_convert(Ptr{Int}, r); Core.Intrinsics.atomic_pointermodify(Base.compilerbarrier(:const, p), Base.compilerbarrier(:const, +), Base.compilerbarrier(:const, 1), :monotonic) end; r[] end",
    "let r = Ref(3); GC.@preserve r Core.Intrinsics.atomic_pointermodify(Base.compilerbarrier(:const, Base.unsafe_convert(Ptr{Int}, r)), Base.compilerbarrier(:const, max), Base.compilerbarrier(:const, 11), :sequentially_consistent) end",
]

# ---------------------------------------------------------------------------
# The prober

const _PROBE_ENUMERATION = enumerate_probes()
const PROBE_TARGETS = _PROBE_ENUMERATION[1]
const PROBE_DENIED = _PROBE_ENUMERATION[2]
# `:fixed`-scope names: never swept, never recipe'd, exercised only by their
# vetted FIXED_PROBES templates. Kept separate from PROBE_DENIED so the
# "no denylisted callee is ever rendered" invariant stays exact.
const PROBE_FIXEDONLY = _PROBE_ENUMERATION[3]
const PROBE_BUILTIN_TARGETS = [t for t in PROBE_TARGETS if t.kind !== :intrinsic]
const PROBE_INTRINSIC_TARGETS = [t for t in PROBE_TARGETS if t.kind === :intrinsic]
# The recipe-carrying targets are the curated set: everything recipe-only
# (the field/global atomics, the memoryref family, apply_type, the type
# internals) plus the sweep-reachable builtins that earned a success-path
# recipe (`_compute_sparams`, `_call_in_world_total`, getfield, invoke, …) —
# exactly the arms the `builtins` policy exists to keep warm.
# They get a dedicated draw share in `genprobe`: under the uniform draw each
# of ~150 builtin spellings expects only ~2-3 draws per few-hundred-candidate
# probe-heavy batch, so individual arms go cold by sampling noise (measured
# across consecutive 300-candidate batches: memoryrefsetonce! missed one,
# _compute_sparams/_call_in_world_total missed another).
const PROBE_CURATED_TARGETS =
    [t for t in PROBE_TARGETS if t.reciponly || haskey(PROBE_RECIPES, t.name)]

nprobe_enumerated() = length(PROBE_TARGETS) + length(PROBE_DENIED) + length(PROBE_FIXEDONLY)
nprobe_denied() = length(PROBE_DENIED)
nprobe_fixedonly() = length(PROBE_FIXEDONLY)
nprobe_reciponly() = count(t -> t.reciponly, PROBE_TARGETS)

function probetarget(spelling::AbstractString)
    i = findfirst(t -> t.spelling == spelling, PROBE_TARGETS)
    return i === nothing ? nothing : PROBE_TARGETS[i]
end
# Every enumerated spelling of one callable (`getfield` and `Core.getfield`).
probetargets(name::Symbol) = [t for t in PROBE_TARGETS if t.name === name]

# Arguments for one probe call: a recipe when the target has one, an intrinsic
# shape when the name says what the operands look like, otherwise the sweep.
function probeargs(ctx::Ctx, t::ProbeTarget; forcerecipe::Bool=false)::Vector{Ex}
    rng = ctx.rng
    recipes = get(PROBE_RECIPES, t.name, nothing)
    if recipes !== nothing && (t.reciponly || forcerecipe || rand(rng) < 0.6)
        return pick(rng, recipes)(ctx)::Vector{Ex}
    end
    # A recipe-only target with no recipe registered must not be rendered with
    # arbitrary arguments — that is the whole point of the ban.
    t.reciponly && return Ex[]
    if t.kind === :intrinsic
        # Intrinsics *always* take a shaped argument list — never the generic
        # pool. Two independent reasons, both measured:
        #   - a width-relation violation in a cast is a compile-time error on
        #     the reference side, outside the program's own `try`;
        #   - a float intrinsic handed a same-width *integer* silently corrupts
        #     the heap (`Core.Intrinsics.ceil_llvm(3)` runs, returns, and the
        #     process dies at the next GC with "GC error (probable
        #     corruption)"). Mismatched *widths* are checked and raise; a
        #     mismatched *kind* of the same width is not.
        # Enumeration withholds any intrinsic without a known shape, so this
        # never falls through for an allowed target.
        a = intrinsic_args(ctx, t)
        a === nothing || return a
        return Ex[]
    end
    return Ex[probearg(ctx) for _ in 1:probearity(ctx, t)]
end

"""
    genprobe(ctx) -> Ex

One guarded builtin/intrinsic probe. Always wrapped in a `:guard`, so the
exception *type* is oracle data exactly like a returned value is.
"""
function genprobe(ctx::Ctx)::Ex
    rng = ctx.rng
    if isempty(PROBE_TARGETS) || rand(rng) < 0.15
        return Ex(:guard, AnyT(), nothing, [psrc(pick(rng, FIXED_PROBES))])
    end
    # A dedicated share for the curated (recipe-carrying) targets, so every
    # hand-curated arm is expected several times per few-hundred-candidate
    # probe-heavy batch instead of hoping the uniform draw below lands on it
    # (see PROBE_CURATED_TARGETS).
    if !isempty(PROBE_CURATED_TARGETS) && rand(rng) < 0.25
        return genprobe_target(ctx, pick(rng, PROBE_CURATED_TARGETS))
    end
    # Builtins carry the 44 hand-written dispatch arms in src/builtins.jl;
    # intrinsics all funnel through one arm, so they are worth less per draw.
    pool = (isempty(PROBE_INTRINSIC_TARGETS) || rand(rng) < 0.7) ?
           PROBE_BUILTIN_TARGETS : PROBE_INTRINSIC_TARGETS
    isempty(pool) && (pool = PROBE_TARGETS)
    return genprobe_target(ctx, pick(rng, pool))
end

function genprobe_target(ctx::Ctx, t::ProbeTarget; forcerecipe::Bool=false)::Ex
    args = probeargs(ctx, t; forcerecipe)
    return Ex(:guard, AnyT(), nothing, [Ex(:probe, AnyT(), t.spelling, args)])
end
