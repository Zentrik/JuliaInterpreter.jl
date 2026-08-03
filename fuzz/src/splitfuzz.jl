# The ExprSplitter axis: adversarial *toplevel forms*, fed straight at
# `construct.jl`.
#
# Why this exists. `src/construct.jl` has the densest fix history in the package
# (9 fix commits, more than any other file), and almost all of it is
# `ExprSplitter`: how a chunk of source is carved into `(module, expression)`
# pairs that can each be handed to `Frame`. Every other axis exercises it
# *incidentally* — the generated programs are one flat module with no `module`
# blocks, no `baremodule`, no toplevel macros, no docstrings — so the machinery
# that the fix history is actually about (module creation and reuse, blocks that
# cannot be split, `:toplevel`-producing macro expansions, `:global`
# declarations that do not lower, docstring rewriting) never runs.
#
# This axis therefore does not reuse the IR grammar at all. It is a template
# combinator over a seeded RNG that emits *toplevel shapes*: nested `module` and
# `baremodule` blocks, bare `begin` blocks (including the `local`-declaring kind
# that `ExprSplitter` must refuse to descend into, issue #427), `if` at toplevel
# wrapping definitions, macros defined in the program that expand to several
# statements or to an `Expr(:toplevel, ...)`, `const`/`global`/typed-global
# declarations in odd positions, definitions inside nested modules, qualified
# cross-module references, docstrings on functions/consts/structs/modules, and
# empty/comment-only sections. Programs are terminating by construction: no
# loops and no recursion are generated at all.
#
# The oracle has two halves, both differential against compiled Julia — the
# corpus axis's discipline, and for the same reason. "The backtrace mentions
# JuliaInterpreter" cannot tell an interpreter bug from a program-thrown error,
# because a program-thrown error unwinds through interpreter frames too.
#
#   1. Failure mode. Run the same source with `Core.eval` per toplevel statement
#      in a fresh module. If compiled Julia accepts the program and the
#      `ExprSplitter` + `Frame` path throws (or vice versa), that is a finding;
#      if both throw the same exception type, they agree.
#   2. Effects. Programs generated here mostly *define* things rather than
#      compute them, so the observation stream alone is a weak oracle. The
#      stronger one is the module tree itself: after both runs, walk every name
#      defined in the root module and recursively in the submodules the program
#      created, normalize the values the way `SETUP_SRC`'s `__fjnorm__` does
#      (module, function and type *identity* scrubbed; scalars compared
#      structurally), and require the two maps to be equal. A definition that
#      the interpreted path silently skipped — the historical `ExprSplitter`
#      failure mode — shows up as a name present on one side and absent on the
#      other.
#
# Budget exhaustion (statements or fragments) is a tracked discard, never a
# finding: the same rule the other axes use.

using JuliaInterpreter: ExprSplitter, Frame

# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

Base.@kwdef struct SplitCfg
    maxdepth::Int = 3                      # module nesting depth
    nrootforms::UnitRange{Int} = 3:8       # toplevel forms in the root module
    nbodyforms::UnitRange{Int} = 1:5       # forms inside a `module` body
    nblockforms::UnitRange{Int} = 1:3      # forms inside a `begin`/`if` block
    maxfrags::Int = 4000                   # ExprSplitter iteration budget
end

# One thing a generated expression can refer to, spelled as it must be written
# *from the scope holding the reference*: `f`, `M1.f`, `M1.M2.K`.
struct SRef
    path::String
    kind::Symbol    # :fn0 (zero-argument function) | :val | :type
end

# A generation scope == one module body. `hasbase` is false inside a
# `baremodule` that did not say `using Base`: there `+` does not exist, so
# expressions must stay literal — that restriction is what keeps
# baremodule programs *running* rather than dying on the first arithmetic op.
mutable struct SScope
    depth::Int                  # 0 = the harness's fresh root module
    hasbase::Bool
    hasobs::Bool                # `__obs__` reachable from here
    refs::Vector{SRef}          # everything referenceable here (own + imported)
    ownrefs::Vector{SRef}       # defined *in* this module; re-exported to the parent
    modnames::Vector{String}    # submodules defined so far, for sibling imports
end
SScope(depth::Int, hasbase::Bool, hasobs::Bool) =
    SScope(depth, hasbase, hasobs, SRef[], SRef[], String[])

mutable struct SplitGen
    rng::AbstractRNG
    cfg::SplitCfg
    counter::Int
end
SplitGen(rng::AbstractRNG, cfg::SplitCfg=SplitCfg()) = SplitGen(rng, cfg, 0)

# Unique across the whole program: two same-named modules in the same parent are
# a *documented* divergence (`ExprSplitter` reuses an existing module where
# `Core.eval` replaces it — see the `find_or_create_module` docstring), so
# generating one would report the documented behaviour as a bug on every case.
nextname!(g::SplitGen, prefix::AbstractString) = (g.counter += 1; string(prefix, g.counter))

chance(g::SplitGen, p::Float64) = rand(g.rng) < p

# A literal. Without Base only integer literals are safe (`Int` itself is a Base
# binding; `Core.Int64` exists but spelling it everywhere buys nothing).
function litexpr(g::SplitGen, hasbase::Bool)
    hasbase || return string(rand(g.rng, -9:99))
    r = rand(g.rng)
    return r < 0.45 ? string(rand(g.rng, -99:99)) :
           r < 0.60 ? string(round(rand(g.rng) * 10; digits=2)) :
           r < 0.72 ? string('"', "s", rand(g.rng, 1:99), '"') :
           r < 0.84 ? string(":sym", rand(g.rng, 1:99)) :
           r < 0.94 ? string(rand(g.rng, (true, false))) : "nothing"
end

# A value-producing expression: a literal, a call to a function defined earlier,
# a read of an earlier const/global, or a field read off a generated struct.
function valexpr(g::SplitGen, sc::SScope)
    if !isempty(sc.refs) && chance(g, 0.45)
        r = pick(g.rng, sc.refs)
        r.kind === :fn0 && return string(r.path, "()")
        r.kind === :val && return r.path
        r.kind === :type && return string(r.path, "(", rand(g.rng, 0:9), ").a")
    end
    sc.hasbase && chance(g, 0.2) &&
        return string(rand(g.rng, -9:9), " + ", rand(g.rng, -9:9))
    return litexpr(g, sc.hasbase)
end

emit!(lines::Vector{String}, ind::String, s::AbstractString) = push!(lines, string(ind, s))

# `"..."` on its own line, attached to whatever definition follows. Docstrings
# lower to a `Core.@doc` macrocall, which `ExprSplitter` has dedicated handling
# for (`is_doc_expr`, and the module-docstring rewrite that re-queues the doc
# application *inside* the module after its body).
function maybedoc!(lines, g::SplitGen, sc::SScope, ind::String, what::AbstractString)
    (sc.hasbase && chance(g, 0.25)) || return false
    emit!(lines, ind, string('"', what, " doc ", g.counter, '"'))
    return true
end

function emit_fundef!(lines, g::SplitGen, sc::SScope, ind::String)
    name = nextname!(g, "f")
    maybedoc!(lines, g, sc, ind, "function")
    body = valexpr(g, sc)
    if chance(g, 0.5)
        emit!(lines, ind, "$name() = $body")
    else
        emit!(lines, ind, "function $name()")
        emit!(lines, ind, "    return $body")
        emit!(lines, ind, "end")
    end
    push!(sc.refs, SRef(name, :fn0))
    push!(sc.ownrefs, SRef(name, :fn0))
    return nothing
end

function emit_structdef!(lines, g::SplitGen, sc::SScope, ind::String)
    sc.hasbase || return emit_fundef!(lines, g, sc, ind)   # `Int` is a Base binding
    name = nextname!(g, "S")
    maybedoc!(lines, g, sc, ind, "struct")
    emit!(lines, ind, string(chance(g, 0.3) ? "mutable struct " : "struct ", name))
    emit!(lines, ind, "    a::Int")
    emit!(lines, ind, "end")
    push!(sc.refs, SRef(name, :type))
    push!(sc.ownrefs, SRef(name, :type))
    return nothing
end

function emit_const!(lines, g::SplitGen, sc::SScope, ind::String)
    name = nextname!(g, "K")
    maybedoc!(lines, g, sc, ind, "const")
    emit!(lines, ind, "const $name = $(valexpr(g, sc))")
    push!(sc.refs, SRef(name, :val))
    push!(sc.ownrefs, SRef(name, :val))
    return nothing
end

# `global` in its several spellings. The bare form is the interesting one: it
# parses to `Expr(:global, ...)`, which `ExprSplitter` returns *unwrapped*
# (there is no LineNumberNode block around it) precisely because it cannot be
# lowered to a `CodeInfo`. It is only legal at true top level, though — inside a
# `begin`/`if` Julia rejects it with 'misplaced "global" declaration', so
# `toplevel=false` restricts this to the assigning forms.
function emit_global!(lines, g::SplitGen, sc::SScope, ind::String; toplevel::Bool=true)
    name = nextname!(g, "g")
    r = toplevel ? rand(g.rng) : 0.55 + 0.45 * rand(g.rng)
    if r < 0.3
        emit!(lines, ind, "global $name")               # declared, never assigned
    elseif r < 0.55
        emit!(lines, ind, "global $name")
        emit!(lines, ind, "$name = $(litexpr(g, sc.hasbase))")
        push!(sc.refs, SRef(name, :val)); push!(sc.ownrefs, SRef(name, :val))
    elseif r < 0.8 || !sc.hasbase
        emit!(lines, ind, "global $name = $(litexpr(g, sc.hasbase))")
        push!(sc.refs, SRef(name, :val)); push!(sc.ownrefs, SRef(name, :val))
    else
        emit!(lines, ind, "global $name::Int = $(rand(g.rng, -99:99))")
        push!(sc.refs, SRef(name, :val)); push!(sc.ownrefs, SRef(name, :val))
    end
    return nothing
end

emit_obs!(lines, g::SplitGen, sc::SScope, ind::String) =
    sc.hasobs ? emit!(lines, ind, "__obs__($(valexpr(g, sc)))") :
                emit_const!(lines, g, sc, ind)

# Empty and near-empty sections: blank lines, comments, `begin end`, `module M
# end`, a stray `;`. `queuenext!` has to skip over all of these without
# yielding an empty fragment or dropping the next real one.
function emit_empty!(lines, g::SplitGen, sc::SScope, ind::String; toplevel::Bool=true)
    r = rand(g.rng)
    if r < 0.25
        emit!(lines, ind, "")
    elseif r < 0.5
        emit!(lines, ind, "# comment $(nextname!(g, "c"))")
    elseif r < 0.65
        emit!(lines, ind, "#= block comment $(nextname!(g, "b")) =#")
    elseif r < 0.8
        emit!(lines, ind, "begin end")
    elseif r < 0.9 && toplevel
        name = nextname!(g, "E")
        emit!(lines, ind, "module $name end")
        push!(sc.modnames, name)
    else
        emit!(lines, ind, ";")
    end
    return nothing
end

# A bare `begin ... end` at toplevel. Two flavours, deliberately not mixed: a
# `local`-declaring block (`ExprSplitter` must return it *whole* rather than
# descend into it — issue #427 — and must not then re-evaluate its statements)
# and a definition-carrying block, whose statements it does split.
function emit_beginblock!(lines, g::SplitGen, sc::SScope, ind::String)
    emit!(lines, ind, "begin")
    inner = ind * "    "
    if chance(g, 0.45)
        # local flavour: the unsplittable kind
        n = rand(g.rng, 1:2)
        locals = String[]
        for _ in 1:n
            lname = nextname!(g, "l")
            emit!(lines, inner, "local $lname = $(litexpr(g, sc.hasbase))")
            push!(locals, lname)
        end
        for lname in locals
            sc.hasobs && chance(g, 0.8) && emit!(lines, inner, "__obs__($lname)")
        end
    else
        for _ in 1:rand(g.rng, g.cfg.nblockforms)
            emit_form!(lines, g, sc, inner; toplevel=false, allowblock=false)
        end
    end
    emit!(lines, ind, "end")
    return nothing
end

# `if` at toplevel wrapping definitions. Nothing defined inside a branch is
# registered as referenceable: the untaken branch never runs, and a later
# reference to a name it would have defined throws on both sides — agreement,
# but it truncates the program and costs coverage.
function emit_ifblock!(lines, g::SplitGen, sc::SScope, ind::String)
    cond = rand(g.rng) < 0.4 ? "true" :
           rand(g.rng) < 0.5 ? "false" :
           string(rand(g.rng, 1:5), " < ", rand(g.rng, 1:5))
    emit!(lines, ind, "if $cond")
    inner = ind * "    "
    branch = SScope(sc.depth, sc.hasbase, sc.hasobs, copy(sc.refs), SRef[], String[])
    for _ in 1:rand(g.rng, g.cfg.nblockforms)
        emit_form!(lines, g, branch, inner; toplevel=false, allowblock=false)
    end
    if chance(g, 0.6)
        emit!(lines, ind, "else")
        branch2 = SScope(sc.depth, sc.hasbase, sc.hasobs, copy(sc.refs), SRef[], String[])
        for _ in 1:rand(g.rng, g.cfg.nblockforms)
            emit_form!(lines, g, branch2, inner; toplevel=false, allowblock=false)
        end
    end
    emit!(lines, ind, "end")
    return nothing
end

# A macro defined *in the program* that expands to more than one toplevel
# statement, then invoked at toplevel. Two things are under test here: the
# expansion shapes `ExprSplitter` must cope with (a `:block` of two definitions,
# an explicit `Expr(:toplevel, ...)`, a bare `global` declaration that only
# lowers at true top level), and the world age — the macro is defined by an
# *earlier fragment of the same program*, so frame construction must expand it
# in a world that has seen the definition.
function emit_macro!(lines, g::SplitGen, sc::SScope, ind::String)
    sc.hasbase || return emit_fundef!(lines, g, sc, ind)   # `esc` is a Base binding
    mname = nextname!(g, "m")
    kind = rand(g.rng)
    if kind < 0.45
        cname, fname = nextname!(g, "K"), nextname!(g, "f")
        lit1, lit2 = litexpr(g, true), litexpr(g, true)
        emit!(lines, ind, "macro $mname()")
        emit!(lines, ind, "    return esc(quote")
        emit!(lines, ind, "        const $cname = $lit1")
        emit!(lines, ind, "        $fname() = $lit2")
        emit!(lines, ind, "    end)")
        emit!(lines, ind, "end")
        emit!(lines, ind, "@$mname")
        push!(sc.refs, SRef(cname, :val)); push!(sc.ownrefs, SRef(cname, :val))
        push!(sc.refs, SRef(fname, :fn0)); push!(sc.ownrefs, SRef(fname, :fn0))
    elseif kind < 0.8
        cname, fname = nextname!(g, "K"), nextname!(g, "f")
        lit1, lit2 = litexpr(g, true), litexpr(g, true)
        emit!(lines, ind, "macro $mname()")
        emit!(lines, ind, "    return Expr(:toplevel, esc(:(const $cname = $lit1)), " *
                          "esc(:($fname() = $lit2)))")
        emit!(lines, ind, "end")
        emit!(lines, ind, "@$mname")
        push!(sc.refs, SRef(cname, :val)); push!(sc.ownrefs, SRef(cname, :val))
        push!(sc.refs, SRef(fname, :fn0)); push!(sc.ownrefs, SRef(fname, :fn0))
    elseif kind < 0.9
        gname = nextname!(g, "g")
        emit!(lines, ind, "macro $mname()")
        emit!(lines, ind, "    return esc(:(global $gname = $(litexpr(g, true))))")
        emit!(lines, ind, "end")
        emit!(lines, ind, "@$mname")
        push!(sc.refs, SRef(gname, :val)); push!(sc.ownrefs, SRef(gname, :val))
    else
        # A macro that expands to a whole `module`. The fragment `ExprSplitter`
        # yields is the *macrocall*; `Frame` lowers it, lowering leaves the
        # `:module` intact, and the `Frame` constructor recurses on it — so this
        # reaches module creation by a completely different route than a literal
        # `module` block does. It has to be `Expr(:toplevel, ...)`: a `quote`
        # expands to a `:block`, and a module inside a block is not valid Julia.
        modname, cname = nextname!(g, "M"), nextname!(g, "K")
        lit1 = litexpr(g, true)
        emit!(lines, ind, "macro $mname()")
        emit!(lines, ind, "    return Expr(:toplevel, esc(:(module $modname; " *
                          "const $cname = $lit1; end)))")
        emit!(lines, ind, "end")
        emit!(lines, ind, "@$mname")
        push!(sc.modnames, modname)
        push!(sc.refs, SRef(string(modname, ".", cname), :val))
        push!(sc.ownrefs, SRef(string(modname, ".", cname), :val))
    end
    return nothing
end

# Several statements on one line: `a = 1; b = 2` parses to an `Expr(:toplevel,
# ...)` rather than a `:block`, which is a different arm of `push_modex!`/
# `queuenext!` than every other form here reaches. A `:toplevel` really is top
# level, so — unlike a `begin` block — a `module` may sit inside one.
function emit_semicolons!(lines, g::SplitGen, sc::SScope, ind::String; toplevel::Bool=true)
    parts = String[]
    for _ in 1:rand(g.rng, 2:3)
        name = nextname!(g, "g")
        push!(parts, "$name = $(litexpr(g, sc.hasbase))")
        push!(sc.refs, SRef(name, :val)); push!(sc.ownrefs, SRef(name, :val))
    end
    if toplevel && sc.depth < g.cfg.maxdepth && chance(g, 0.3)
        mname, cname = nextname!(g, "M"), nextname!(g, "K")
        push!(parts, "module $mname; const $cname = $(litexpr(g, true)); end")
        push!(sc.modnames, mname)
        push!(sc.refs, SRef(string(mname, ".", cname), :val))
        push!(sc.ownrefs, SRef(string(mname, ".", cname), :val))
    end
    emit!(lines, ind, join(parts, "; "))
    return nothing
end

# Scope blocks `ExprSplitter` cannot split at all: their head is neither `:block`
# nor `:toplevel`, so the whole thing comes back as one fragment and `Frame` has
# to lower it in one piece. `global` inside is how they leave anything behind —
# a bare assignment would be a soft-scope local (NEXT.md's second lesson).
function emit_scopeblock!(lines, g::SplitGen, sc::SScope, ind::String)
    inner = ind * "    "
    gname = nextname!(g, "g")
    if chance(g, 0.5)
        lname = nextname!(g, "l")
        emit!(lines, ind, "let $lname = $(litexpr(g, sc.hasbase))")
        emit!(lines, inner, "global $gname = $lname")
        sc.hasobs && chance(g, 0.6) && emit!(lines, inner, "__obs__($lname)")
        emit!(lines, ind, "end")
    else
        # try/catch/finally at toplevel, with the catch arm actually taken half
        # the time: toplevel exception handling is its own path through
        # `Frame`/`step_expr!`.
        gname2 = nextname!(g, "g")
        throws = sc.hasbase && chance(g, 0.5)
        emit!(lines, ind, "try")
        emit!(lines, inner, "global $gname = $(litexpr(g, sc.hasbase))")
        throws && emit!(lines, inner, "error(\"boom\")")
        emit!(lines, ind, "catch")
        emit!(lines, inner, "global $gname2 = $(litexpr(g, sc.hasbase))")
        if chance(g, 0.5)
            emit!(lines, ind, "finally")
            sc.hasobs && emit!(lines, inner, "__obs__(:fin)")
        end
        emit!(lines, ind, "end")
        # Only referenceable if the catch arm actually runs: otherwise a later
        # read is an UndefVarError on both sides — agreement, but it truncates
        # the program and costs coverage.
        throws && (push!(sc.refs, SRef(gname2, :val)); push!(sc.ownrefs, SRef(gname2, :val)))
    end
    push!(sc.refs, SRef(gname, :val)); push!(sc.ownrefs, SRef(gname, :val))
    return nothing
end

# `abstract type` plus a `struct` that subtypes it, sometimes across a module
# boundary (`struct S <: M1.AT`), which makes frame construction resolve the
# supertype in another module while building the type.
function emit_abstract!(lines, g::SplitGen, sc::SScope, ind::String)
    sc.hasbase || return emit_fundef!(lines, g, sc, ind)
    name = nextname!(g, "A")
    maybedoc!(lines, g, sc, ind, "abstract")
    emit!(lines, ind, "abstract type $name end")
    push!(sc.refs, SRef(name, :abstract)); push!(sc.ownrefs, SRef(name, :abstract))
    if chance(g, 0.7)
        sname = nextname!(g, "S")
        supers = [r for r in sc.refs if r.kind === :abstract]
        emit!(lines, ind, "struct $sname <: $(pick(g.rng, supers).path)")
        emit!(lines, ind, "    a::Int")
        emit!(lines, ind, "end")
        push!(sc.refs, SRef(sname, :type)); push!(sc.ownrefs, SRef(sname, :type))
    end
    return nothing
end

# `module` / `baremodule`, optionally documented, optionally importing `__obs__`
# and previously-defined siblings, optionally exporting a name the parent then
# picks up with `using .M`.
function emit_module!(lines, g::SplitGen, sc::SScope, ind::String)
    name = nextname!(g, "M")
    bare = chance(g, 0.25)
    inner = ind * "    "
    childdepth = sc.depth + 1
    usingbase = bare && chance(g, 0.45)
    hasbase = !bare || usingbase
    # A module docstring is not evaluated where it is written: `is_doc_expr`
    # rewrites it to document the module *by name* and re-queues it to run
    # inside the module *after* the body, precisely so an interpolation can
    # reference a binding the body defines. Generate exactly that shape — a doc
    # whose text interpolates a const the body has not defined yet at the point
    # the docstring appears in the source. Needs the docsystem, hence Base.
    interpname = ""
    if hasbase && chance(g, 0.18)
        interpname = nextname!(g, "K")
        emit!(lines, ind, string('"', "module ", name, " doc: \$(", interpname, ")\""))
    elseif hasbase
        maybedoc!(lines, g, sc, ind, "module")
    end
    emit!(lines, ind, string(bare ? "baremodule " : "module ", name))
    usingbase && emit!(lines, inner, "using Base")
    child = SScope(childdepth, hasbase, false)
    if !isempty(interpname)
        emit!(lines, inner, "const $interpname = $(litexpr(g, hasbase))")
        push!(child.refs, SRef(interpname, :val)); push!(child.ownrefs, SRef(interpname, :val))
    end
    # `import ..__obs__` — one dot per level up, plus one for the name itself.
    # It reaches the root module directly, so it works even when the enclosing
    # module never imported it.
    if chance(g, 0.7)
        emit!(lines, inner, string("import ", "."^(childdepth + 1), "__obs__"))
        child.hasobs = true
    end
    for mn in sc.modnames
        chance(g, 0.35) || continue
        emit!(lines, inner, "import ..$mn")
        push!(child.refs, SRef(mn, :val))
        for r in sc.refs
            startswith(r.path, string(mn, ".")) && push!(child.refs, r)
        end
    end
    # Shadowing: define, inside the child, a name the parent already defines,
    # with a different value. Nothing else in this generator reuses a name, so
    # this is the one place that asks "did the fragment get evaluated in the
    # module `ExprSplitter` said it did?" — a body evaluated in the parent by
    # mistake would clobber the parent's binding, and the state comparison sees
    # both. (Not for names the child imported: redefining an imported binding is
    # an error, not a shadow.)
    shadowable = [r for r in sc.ownrefs
                  if !occursin('.', r.path) && (r.kind === :val || r.kind === :fn0)]
    if hasbase && !isempty(shadowable) && chance(g, 0.3)
        r = pick(g.rng, shadowable)
        if r.kind === :val
            emit!(lines, inner, "const $(r.path) = $(litexpr(g, hasbase))")
        else
            emit!(lines, inner, "$(r.path)() = $(litexpr(g, hasbase))")
        end
        push!(child.refs, r); push!(child.ownrefs, r)
    end
    for _ in 1:rand(g.rng, g.cfg.nbodyforms)
        emit_form!(lines, g, child, inner)
    end
    # `export`/`public` declarations: bare-name statements that lowering is the
    # identity on, so `Frame` has to route them through a toplevel-surface frame
    # rather than a thunk.
    exported = ""
    fns = [r for r in child.ownrefs if r.kind === :fn0 && !occursin('.', r.path)]
    if !isempty(fns) && chance(g, 0.3)
        exported = pick(g.rng, fns).path
        emit!(lines, inner, "export $exported")
    elseif !isempty(fns) && VERSION >= v"1.11" && chance(g, 0.15)
        emit!(lines, inner, "public $(pick(g.rng, fns).path)")
    end
    # A `baremodule` that reaches for Base: both sides must throw the same
    # UndefVarError. Deliberately rare — it truncates the rest of the program.
    bare && !usingbase && chance(g, 0.06) &&
        emit!(lines, inner, "const bad$(nextname!(g, "x")) = 1 + 1")
    emit!(lines, ind, "end")
    push!(sc.modnames, name)
    for r in child.ownrefs
        push!(sc.refs, SRef(string(name, ".", r.path), r.kind))
        push!(sc.ownrefs, SRef(string(name, ".", r.path), r.kind))
    end
    # Pull the submodule's names into the parent by relative `using`/`import`.
    # The bare name becomes referenceable here but is deliberately *not*
    # re-exported upwards: `using` adds a resolution path, not a binding, so
    # `Parent.f` would not resolve for a grandparent.
    # ... but only for a name the parent does not already define: the shadowing
    # template above can make the child re-use a parent name, and importing it
    # back is a conflict Julia warns about and ignores (identically on both
    # sides — noise, not signal).
    taken(p) = any(r -> r.path == p, sc.ownrefs)
    if !isempty(exported) && !taken(exported) && chance(g, 0.35)
        emit!(lines, ind, "using .$name")
        push!(sc.refs, SRef(exported, :fn0))
    elseif !isempty(fns) && chance(g, 0.2)
        r = pick(g.rng, fns)
        taken(r.path) || (emit!(lines, ind, "import .$name: $(r.path)");
                          push!(sc.refs, SRef(r.path, :fn0)))
    end
    return nothing
end

# A qualified reference across a module boundary with no `using`: `M1.f()`,
# `M1.M2.K`. The path is written out from the referencing scope, so this is the
# `getproperty`-on-a-module path that only works if the interpreted run really
# populated the submodule.
function emit_crossref!(lines, g::SplitGen, sc::SScope, ind::String)
    qualified = [r for r in sc.refs if occursin('.', r.path)]
    isempty(qualified) && return emit_obs!(lines, g, sc, ind)
    r = pick(g.rng, qualified)
    ex = r.kind === :fn0 ? string(r.path, "()") :
         r.kind === :type ? string(r.path, "(", rand(g.rng, 0:9), ").a") : r.path
    if sc.hasobs && chance(g, 0.75)
        emit!(lines, ind, "__obs__($ex)")
    else
        name = nextname!(g, "K")
        emit!(lines, ind, "const $name = $ex")
        push!(sc.refs, SRef(name, :val)); push!(sc.ownrefs, SRef(name, :val))
    end
    return nothing
end

# Weighted form choice. `toplevel=false` means "inside a `begin`/`if` at
# toplevel", which is *not* a true top level for the parser and forbids three
# forms — each of which Julia rejects, so generating one would produce a
# difference about the generator rather than about the interpreter:
#
#   - `module`: 'syntax: "module" expression not at top level'.
#   - a bare `global x` declaration: 'syntax: misplaced "global" declaration'.
#   - defining a macro and invoking it in the *same* block: `Core.eval` expands
#     the whole block before running any of it, so the macro does not exist yet;
#     `ExprSplitter` splits the block first and the invocation expands fine.
#     Legitimate — splitting a block into separately-evaluated statements is
#     what `ExprSplitter` is *for* — but it makes the program invalid Julia.
function emit_form!(lines, g::SplitGen, sc::SScope, ind::String;
                    toplevel::Bool=true, allowblock::Bool=true)
    allowmodule = toplevel && sc.depth < g.cfg.maxdepth
    ws = Tuple{Symbol,Float64}[(:fundef, 3.0), (:structdef, 1.5), (:const, 2.0),
                               (:global, 2.0), (:obs, 2.0), (:empty, 1.5),
                               (:crossref, 1.5), (:semis, 1.0), (:abstract, 1.0)]
    toplevel && push!(ws, (:macro, 2.0))
    allowblock && (append!(ws, ((:beginblock, 2.0), (:ifblock, 2.0), (:scopeblock, 1.5))))
    allowmodule && push!(ws, (:module, 3.5))
    total = sum(w for (_, w) in ws)
    x = rand(g.rng) * total
    choice = ws[end][1]
    acc = 0.0
    for (k, w) in ws
        acc += w
        if x <= acc
            choice = k
            break
        end
    end
    choice === :fundef     ? emit_fundef!(lines, g, sc, ind) :
    choice === :structdef  ? emit_structdef!(lines, g, sc, ind) :
    choice === :const      ? emit_const!(lines, g, sc, ind) :
    choice === :global     ? emit_global!(lines, g, sc, ind; toplevel) :
    choice === :obs        ? emit_obs!(lines, g, sc, ind) :
    choice === :empty      ? emit_empty!(lines, g, sc, ind; toplevel) :
    choice === :crossref   ? emit_crossref!(lines, g, sc, ind) :
    choice === :semis      ? emit_semicolons!(lines, g, sc, ind; toplevel) :
    choice === :abstract   ? emit_abstract!(lines, g, sc, ind) :
    choice === :macro      ? emit_macro!(lines, g, sc, ind) :
    choice === :beginblock ? emit_beginblock!(lines, g, sc, ind) :
    choice === :scopeblock ? emit_scopeblock!(lines, g, sc, ind) :
    choice === :ifblock    ? emit_ifblock!(lines, g, sc, ind) :
                             emit_module!(lines, g, sc, ind)
    return nothing
end

"""
    gensplit(rng, cfg=SplitCfg()) -> String

Generate one adversarial toplevel program as source text. Deterministic in
`rng`, terminating by construction (no loops, no recursion).
"""
function gensplit(rng::AbstractRNG, cfg::SplitCfg=SplitCfg())
    g = SplitGen(rng, cfg)
    sc = SScope(0, true, true)
    lines = String[]
    for _ in 1:rand(rng, cfg.nrootforms)
        emit_form!(lines, g, sc, "")
    end
    isempty(lines) && push!(lines, "__obs__(0)")
    return join(lines, "\n") * "\n"
end

# ---------------------------------------------------------------------------
# Module-state comparison
# ---------------------------------------------------------------------------

# Names every module gets for free, plus the harness's own prelude. Everything
# starting with '#' is compiler/docsystem internal (`#f` type names, the
# docsystem's gensym'd META binding) and is excluded wholesale.
const SPLIT_SKIP_NAMES = Set{Symbol}([:eval, :include, :__OBS__, :__obs__, :__fjnorm__,
                                      # determinism-unlock prelude bindings (SETUP_SRC);
                                      # identical on both sides, so never a divergence, but
                                      # excluded to keep modstate focused on program state.
                                      :__VTIME__, :__vtime__, :__RNG__])

# Identity-scrubbed name of a function or type. Anonymous functions and closure
# types are named `#3#4` with counters that depend on how many were created in
# the process, so they cannot be compared across two runs.
function scrubname(@nospecialize(x))
    n = try
        String(nameof(x))
    catch
        return "__anon__"
    end
    return startswith(n, "#") ? "__anon__" : n
end

# The `__fjnorm__` treatment, extended to what module *bindings* can hold:
# identity is scrubbed (modules, functions and types keep only their name),
# scalars survive structurally, aggregates recurse.
function normstate(@nospecialize(x), depth::Int=0)
    depth > 3 && return :__deep__
    (x isa Number || x isa AbstractString || x isa Symbol || x isa Char || x === nothing) &&
        return x isa AbstractString ? String(x) : x
    x isa Module && return Symbol("__module__:", nameof(x))
    x isa Type && return Symbol("__type__:", scrubname(x))
    x isa Function && return Symbol("__fn__:", scrubname(x))
    x isa Tuple && return map(el -> normstate(el, depth + 1), x)
    if x isa AbstractArray
        out = Any[]
        try
            for i in eachindex(x)
                push!(out, isassigned(x, i) ? normstate(x[i], depth + 1) : UNASSIGNED_OBS)
            end
        catch
            return Symbol("__array__:", scrubname(typeof(x)))
        end
        return out
    end
    # A struct instance: type identity scrubbed to the type's name, fields
    # compared structurally — the generated structs hold plain Ints, and a
    # divergent field value is exactly the kind of missed effect this is for.
    nf = try
        nfields(x)
    catch
        return Symbol("__obj__:", scrubname(typeof(x)))
    end
    flds = Any[Symbol("__obj__:", scrubname(typeof(x)))]
    for i in 1:min(nf, 8)
        push!(flds, isdefined(x, i) ? normstate(getfield(x, i), depth + 1) : :__undef_field__)
    end
    return Tuple(flds)
end

"""
    modstate(m::Module) -> Dict{String,Any}

Every name defined in `m` and, recursively, in the submodules the program
created under it, mapped to its identity-scrubbed value. Dotted paths are the
keys, so a name that exists on one side and not the other shows up as a key
difference rather than being buried in a value.
"""
modstate(m::Module) = modstate!(Dict{String,Any}(), m, "", Set{Module}(), 0)

function modstate!(out::Dict{String,Any}, m::Module, prefix::String,
                   seen::Set{Module}, depth::Int)
    (depth > 8 || m in seen) && return out
    push!(seen, m)
    ns = try
        # invokelatest: these bindings were created by `Core.eval`/the interpreter
        # after this function's caller world.
        Base.invokelatest(names, m; all=true)
    catch
        return out
    end
    selfname = nameof(m)
    for n in sort(ns; by=String)
        s = String(n)
        (startswith(s, "#") || n in SPLIT_SKIP_NAMES || n === selfname) && continue
        path = isempty(prefix) ? s : string(prefix, ".", s)
        isdef = try
            Base.invokelatest(isdefined, m, n)
        catch
            false
        end
        if !isdef
            # A `global x` with no assignment: the *binding* exists on both sides
            # and holds nothing on both sides. That is a comparable state.
            out[path] = :__declared_undefined__
            continue
        end
        v = try
            Base.invokelatest(getglobal, m, n)
        catch err
            out[path] = Symbol("__getfailed__:", nameof(typeof(err)))
            continue
        end
        if v isa Module && parentmodule(v) === m && v !== m
            out[path] = :__submodule__
            modstate!(out, v, path, seen, depth + 1)
        else
            out[path] = normstate(v)
        end
    end
    return out
end

# Fingerprint salt for a state value: enough to keep unrelated divergences in
# different dedup buckets ("a submodule is missing" vs "an Int differs"),
# deliberately not the value itself (which would make every case its own
# bucket).
function statesig(@nospecialize(x))
    if x isa Symbol
        s = String(x)
        startswith(s, "__") && return Symbol(first(split(s, ':')))
        return :Symbol
    end
    if x isa Tuple && !isempty(x) && x[1] isa Symbol && startswith(String(x[1]::Symbol), "__")
        return Symbol(first(split(String(x[1]::Symbol), ':')))
    end
    return nameof(typeof(x))
end

const STATE_MISSING = :__absent__

"""
    statediff(ref, int) -> nothing | (kind, path, refval, intval)

First divergence between two module-state maps, in sorted-path order so the
answer is stable. `kind` is `:missing` (a name one side defined and the other
did not) or `:value`.
"""
function statediff(ref::Dict{String,Any}, int::Dict{String,Any})
    for path in sort(collect(union(keys(ref), keys(int))))
        hr, hi = haskey(ref, path), haskey(int, path)
        if hr != hi
            return (:missing, path, hr ? ref[path] : STATE_MISSING,
                    hi ? int[path] : STATE_MISSING)
        end
        obseq(ref[path], int[path]) || return (:value, path, ref[path], int[path])
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

struct SplitOutcome
    status::Symbol              # :done | :threw | :aborted
    excname::Symbol
    obs::Vector{Any}
    state::Dict{String,Any}
    detail::String
    site::Symbol                # innermost JuliaInterpreter function, fingerprint salt only
    nfrags::Int
end
SplitOutcome(status::Symbol) = SplitOutcome(status, :none, Any[], Dict{String,Any}(), "", :none, 0)

# The reference: compiled Julia, one `Core.eval` per toplevel statement — which
# is exactly what `include` does, and what the interpreted side does one
# `ExprSplitter` fragment at a time.
function split_ref(ex::Expr)::SplitOutcome
    m = freshmodule()
    try
        for st in ex.args
            st isa LineNumberNode && continue
            Core.eval(m, st)
        end
        return SplitOutcome(:done, :none, getobs(m), modstate(m), "", :none, 0)
    catch err
        return SplitOutcome(:threw, scrubexc(err), getobs(m), modstate(m),
                            shortstr(err), :none, 0)
    end
end

"""
    split_interp(ex; nstmts, maxfrags, interp) -> SplitOutcome

Drive `ex` through the production toplevel path — `ExprSplitter`, then `Frame`
per fragment, then the budgeted executor.
"""
function split_interp(ex::Expr; nstmts::Int, maxfrags::Int,
                      interp::Interpreter=RecursiveInterpreter())::SplitOutcome
    m = freshmodule()
    budget = nstmts
    nfrags = 0
    try
        # invokelatest, twice, for the reason NEXT.md's lessons list first:
        # `ExprSplitter` and `Frame` *expand macros* while constructing, and the
        # program's own macros — plus the prelude's `__obs__` — were defined by
        # `Core.eval` after this function's world. Without it the axis reports
        # "compiled Julia ran this, the interpreter threw UndefVarError: @m3",
        # a difference manufactured entirely by the harness.
        for (mod, frag) in Base.invokelatest(ExprSplitter, m, ex)
            nfrags += 1
            nfrags > maxfrags &&
                return SplitOutcome(:aborted, :none, getobs(m), Dict{String,Any}(),
                                    "fragment budget", :none, nfrags)
            frame = Base.invokelatest(Frame, mod, frag)
            while true
                ret, budget = evaluate_limited!(interp, frame, budget, true)
                ret isa Aborted &&
                    return SplitOutcome(:aborted, :none, getobs(m), Dict{String,Any}(),
                                        "statement budget", :none, nfrags)
                ret isa Some && break
                @assert ret === nothing   # paused after a method definition; resume
            end
        end
        return SplitOutcome(:done, :none, getobs(m), modstate(m), "", :none, nfrags)
    catch err
        err isa AbortException &&
            return SplitOutcome(:aborted, :none, getobs(m), Dict{String,Any}(),
                                "statement budget", :none, nfrags)
        # Where it surfaced is recorded as *fingerprint salt and a label only*.
        # Whether it is a finding is decided by the differential above, never by
        # the backtrace: a program-thrown exception unwinds through interpreter
        # frames too.
        site = internalframe(stacktrace(catch_backtrace()))
        sitename = site === nothing ? :none : Symbol(site[1])
        loc = site === nothing ? "" : string(" in ", site[1], " (", site[2], ")")
        return SplitOutcome(:threw, scrubexc(err), getobs(m), modstate(m),
                            string(nameof(typeof(err)), loc, ": ", shortstr(err)),
                            sitename, nfrags)
    end
end

# ---------------------------------------------------------------------------
# Oracle
# ---------------------------------------------------------------------------

# Comparing module state after a *throw* would compare two partial programs, and
# on that path the two sides legitimately differ. Measured (1500 seeds, 27
# both-threw cases): `ExprSplitter` creates modules **one fragment ahead**.
# `Base.iterate` calls `queuenext!` *before* returning the current pair, and
# queueing a `module` means running `find_or_create_module` — so when fragment k
# throws, the module opened by fragment k+1 already exists on the interpreted
# side and does not on the compiled one. That is inherent to the iterator
# protocol (the iterator has to resolve the next module to know what to yield
# next), and Revise depends on it, so it is not a bug — but it makes
# after-a-throw state incomparable. The observation stream is still compared:
# it is ordered and only appended to by statements that actually ran.
const SPLIT_COMPARE_STATE_AFTER_THROW = false

function classify_split(ref::SplitOutcome, spl::SplitOutcome)::Verdict
    # Budget exhaustion on either side: nothing sound to compare. Tracked, never
    # reported (the same rule the other axes use).
    (spl.status === :aborted || ref.status === :aborted) &&
        return Verdict(:aborted, spl.detail, :none, :none, 0, :none, :none)

    if ref.status === :done && spl.status === :threw
        # Split into two classes purely so the reports read usefully and land in
        # separate dedup buckets; both are findings either way.
        cls = spl.site === :none ? :split_only_throw : :split_internal_error
        return Verdict(cls,
                       "compiled Julia ran this program; the ExprSplitter path threw " *
                       "$(spl.excname)\n$(spl.detail)",
                       :none, spl.excname, 0, spl.site, tailsigobs(spl.obs))
    end
    if ref.status === :threw && spl.status === :done
        return Verdict(:eval_only_throw,
                       "Core.eval threw $(ref.excname) ($(ref.detail)); the ExprSplitter " *
                       "path ran the program to completion",
                       ref.excname, :none, 0, tailsigobs(ref.obs), tailsigobs(spl.obs))
    end
    if ref.status === :threw && spl.status === :threw && ref.excname !== spl.excname
        return Verdict(:split_exception_divergence,
                       "Core.eval threw $(ref.excname) ($(ref.detail)); the ExprSplitter " *
                       "path threw $(spl.excname) ($(spl.detail))",
                       ref.excname, spl.excname, 0, tailsigobs(ref.obs), tailsigobs(spl.obs))
    end

    # Same failure mode on both sides. Now the effects.
    d = firstdiff(ref.obs, spl.obs)
    if d != 0
        return Verdict(:split_missing_effect,
                       "observation stream: obs[$d] eval=$(first(repr(get(ref.obs, d, nothing)), 200)) " *
                       "split=$(first(repr(get(spl.obs, d, nothing)), 200))",
                       ref.excname, spl.excname, d,
                       obssig(get(ref.obs, d, nothing)), obssig(get(spl.obs, d, nothing)))
    end
    if length(ref.obs) != length(spl.obs)
        return Verdict(:split_missing_effect,
                       "observation count: eval=$(length(ref.obs)) split=$(length(spl.obs))",
                       ref.excname, spl.excname, min(length(ref.obs), length(spl.obs)) + 1,
                       :count, :count)
    end
    if ref.status === :done || SPLIT_COMPARE_STATE_AFTER_THROW
        sd = statediff(ref.state, spl.state)
        if sd !== nothing
            kind, path, rv, iv = sd
            what = kind === :missing ?
                (rv === STATE_MISSING ?
                 "`$path` was defined by the ExprSplitter path but not by Core.eval" :
                 "`$path` was defined by Core.eval but not by the ExprSplitter path") :
                "`$path`: eval=$(first(repr(rv), 200)) split=$(first(repr(iv), 200))"
            return Verdict(:split_missing_effect, string("module state: ", what),
                           ref.excname, spl.excname, 0, statesig(rv), statesig(iv))
        end
    end
    return agree()
end

# Tail-of-stream salt, same idea as classify.jl's `tailsig` but over a raw
# observation vector.
tailsigobs(obs::Vector{Any}) = isempty(obs) ? :empty : obssig(obs[end])

# Known-legitimate divergences, each with the reason it is legitimate. Kept as
# Verdict predicates like `SUPPRESSIONS`, and empty on purpose: the two
# divergences this axis is known to be able to produce are designed out of the
# generator instead, because suppressing them would also suppress a real bug of
# the same shape.
#
#   1. Two `module M` blocks with the same name in the same parent.
#      `find_or_create_module` deliberately *reuses* an existing module (it
#      exists to re-interpret code, so re-entering a module is the point),
#      while `Core.eval` replaces it — so the first module's bindings survive on
#      the interpreted side and vanish on the compiled one. Documented in the
#      `ExprSplitter` docstring. The generator gives every module a unique name.
#   2. `module` inside `begin`/`if`. Julia rejects it at lowering
#      ("\"module\" expression not at top level"), so it is not a valid program;
#      `ExprSplitter` splits the block first and never sees the restriction.
#      The generator only emits `module` at true top level, and
#      `split_case` discards any program whose *reference* run reports a syntax
#      error, so a future template mistake shows up as a discard rather than a
#      finding.
const SPLIT_SUPPRESSIONS = Function[]

split_suppressed(v::Verdict) = suppressed(v) || any(p -> p(v)::Bool, SPLIT_SUPPRESSIONS)

# A reference-side syntax/lowering error means the *program* is invalid, not
# that either side is wrong — there is nothing to compare. Tracked as a discard.
function ref_syntax_error(o::SplitOutcome)
    o.status === :threw || return false
    o.excname === :ErrorException || return false
    return occursin("syntax:", o.detail) || occursin("not at top level", o.detail)
end

"""
    split_case(src; nstmts, maxfrags, interp) -> (Verdict, SplitOutcome, SplitOutcome)

Run one program both ways and classify. Returns `nothing` if the program was
discarded before comparison (unparseable, or invalid Julia).
"""
function split_case(src::String; nstmts::Int=300_000, maxfrags::Int=4000,
                    interp::Interpreter=RecursiveInterpreter())
    ex = try
        Meta.parseall(src)
    catch
        return nothing
    end
    (ex isa Expr && ex.head === :toplevel) || return nothing
    ref = split_ref(ex)
    ref_syntax_error(ref) && return nothing
    spl = split_interp(ex; nstmts, maxfrags, interp)
    return (classify_split(ref, spl), ref, spl)
end

"""
    split_campaign(; n, baseseed, ...) -> Stats

Generate adversarial toplevel programs, run each through `Core.eval` and through
`ExprSplitter` + `Frame`, and report any divergence in failure mode, observation
stream, or resulting module tree.
"""
function split_campaign(; n::Int=500, baseseed::Int=1, nstmts::Int=300_000,
                        outdir::String=joinpath(@__DIR__, "..", "findings"),
                        journaldir::String=joinpath(@__DIR__, "..", "journal"),
                        cfg::SplitCfg=SplitCfg(), progress::Int=100,
                        seeddisk::Bool=true, journalsync::Bool=true,
                        doshrink::Bool=true, shrinkruns::Int=80, shrinksecs::Real=240.0)
    j = Journal(journaldir; sync=journalsync)
    stats = Stats()
    seen = Set{String}()
    seeddisk && isdir(outdir) && for d in readdir(outdir)
        push!(seen, d)
    end
    t0 = time()
    try
        for i in 1:n
            seed = baseseed + i - 1
            src = gensplit(Xoshiro(seed), cfg)
            journal_case!(j, seed, src)
            stats.cases += 1
            r = split_case(src; nstmts, maxfrags=cfg.maxfrags)
            if r === nothing
                stats.discarded += 1
                continue
            end
            v, _ref, spl = r
            if v.class === :agree
                stats.agreed += 1
            elseif v.class === :aborted
                stats.aborted += 1
            elseif split_suppressed(v)
                stats.suppressed += 1
            else
                fp = tagfp(:split, fingerprint(v))
                if fp in seen
                    stats.duplicates += 1
                else
                    push!(seen, fp)
                    stats.findings += 1
                    @info "SPLIT FINDING $(v.class)" seed fp nfrags = spl.nfrags detail = first(v.detail, 400)
                    # This axis generates source text, not Program IR, so
                    # minimization is the statement-level delta debugger with
                    # "same fingerprint" as the property.
                    shrunksrc = if doshrink
                        keep = s -> begin
                            r2 = split_case(s; nstmts, maxfrags=cfg.maxfrags)
                            r2 !== nothing && tagfp(:split, fingerprint(r2[1])) == fp
                        end
                        ddmin_source(src, keep;
                                     budget=ShrinkBudget(; maxruns=shrinkruns, seconds=shrinksecs))
                    else
                        src
                    end
                    writefinding(outdir, fp, v, seed, src, shrunksrc; mode=:split)
                end
            end
            if progress > 0 && i % progress == 0
                @info "split progress" i rate_per_s = round(stats.cases / (time() - t0); digits=2) stats.agreed stats.aborted stats.discarded stats.findings stats.duplicates
            end
        end
    finally
        close(j)
    end
    return stats
end
