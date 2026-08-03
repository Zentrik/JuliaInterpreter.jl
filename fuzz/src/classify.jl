# The oracle: compare the two Outcomes and classify any divergence.

struct Verdict
    class::Symbol   # :agree | :aborted | :nondet_discard | :value_divergence |
                    # :exception_divergence | :interp_only_throw | :ref_only_throw
    detail::String
    refexc::Symbol
    intexc::Symbol
    dividx::Int     # first divergent observation index (0 if n/a)
    refsig::Symbol  # shape signature of the divergent observation on each side
    intsig::Symbol  # (:none if n/a) — see obssig; part of the dedup fingerprint
end
Verdict(class::Symbol, detail::String, refexc::Symbol, intexc::Symbol, dividx::Int) =
    Verdict(class, detail, refexc, intexc, dividx, :none, :none)

agree() = Verdict(:agree, "", :none, :none, 0)

# Shape signature of one observation, for fingerprinting. Guarded-operation
# observations like (:__thrown, :BoundsError) keep the exception name — a
# BoundsError-vs-MethodError divergence and a BoundsError-vs-DomainError
# divergence are different bugs. Everything else contributes its type name.
function obssig(@nospecialize(x))
    if x isa Tuple && !isempty(x) && x[1] isa Symbol && startswith(String(x[1]::Symbol), "__")
        return length(x) >= 2 && x[2] isa Symbol ? Symbol(x[1], :_, x[2]) : x[1]::Symbol
    end
    return nameof(typeof(x))
end
sigat(o::Outcome, i::Int) = i <= length(o.obs) ? obssig(o.obs[i]) : :missing

# Observation equality. `isequal` alone is too weak an oracle here: it holds
# across types (`isequal(1, 1.0)`, `isequal(true, 1)` are both true), so an
# interpreter that produced a Float64 where compiled Julia produced an Int —
# a promotion/conversion bug, and exactly the kind a hand-written interpreter
# makes — would compare *equal* and never be reported.
#
# So compare types as well as values. `isequal` still does the value work, which
# keeps the deliberate NaN/-0.0 semantics: all NaNs agree, 0.0 and -0.0 differ.
# The normalizer (SETUP_SRC) has already scrubbed identity-dependent types, so
# every type reaching here is one both sides should genuinely agree on.
obseq(@nospecialize(a), @nospecialize(b)) = typeof(a) === typeof(b) && isequal(a, b)
# Containers: the normalizer maps arrays to Vector{Any} and tuples elementwise,
# so recurse rather than compare container types (which are already uniform).
obseq(a::Tuple, b::Tuple) = length(a) == length(b) && all(obseq(x, y) for (x, y) in zip(a, b))
obseq(a::Vector{Any}, b::Vector{Any}) =
    length(a) == length(b) && all(obseq(x, y) for (x, y) in zip(a, b))

# Outcome equality for the confirm-on-divergence gate (bottom of this file):
# does a *re-run of the same side* reproduce what the first run of that side did?
# Deliberately built from the same comparison helpers the oracle uses, so
# "stable" means stable in exactly the dimensions `classify` looks at: status,
# exception name, and the observation stream (elementwise plus length —
# `firstdiff` alone would call a stream and its own prefix equal).
#
# Messages and backtraces are not compared, for the same reason `classify`
# ignores them: they drift without the semantics changing.
outcomeeq(a::Outcome, b::Outcome) =
    a.status === b.status && a.excname === b.excname &&
    length(a.obs) == length(b.obs) && firstdiff(a.obs, b.obs) == 0

# First index where the observation streams disagree; 0 if one is a prefix of
# the other.
function firstdiff(a::Vector{Any}, b::Vector{Any})
    n = min(length(a), length(b))
    for i in 1:n
        obseq(a[i], b[i]) || return i
    end
    return 0
end

function classify(ref::Outcome, int::Outcome)::Verdict
    d = firstdiff(ref.obs, int.obs)
    if int.status === :aborted
        # Budget ran out mid-program: only comparable up to the observations the
        # interpreter made. A mismatched prefix is still a real divergence.
        d != 0 && return Verdict(:value_divergence, divdetail(ref, int, d), :none, :none, d,
                                 sigat(ref, d), sigat(int, d))
        return Verdict(:aborted, "", :none, :none, 0)
    end
    if d != 0
        return Verdict(:value_divergence, divdetail(ref, int, d), ref.excname, int.excname, d,
                       sigat(ref, d), sigat(int, d))
    end
    if ref.status === :done && int.status === :done
        length(ref.obs) == length(int.obs) && return agree()
        return Verdict(:value_divergence,
                       "observation count: ref=$(length(ref.obs)) interp=$(length(int.obs))",
                       :none, :none, min(length(ref.obs), length(int.obs)) + 1,
                       :count, :count)
    end
    if ref.status === :threw && int.status === :threw
        if ref.excname === int.excname
            length(ref.obs) == length(int.obs) && return agree()
            return Verdict(:value_divergence,
                           "observation count before throw: ref=$(length(ref.obs)) interp=$(length(int.obs))",
                           ref.excname, int.excname, min(length(ref.obs), length(int.obs)) + 1,
                           :count, :count)
        end
        return Verdict(:exception_divergence,
                       "ref threw $(ref.excname) ($(ref.errstr)); interp threw $(int.excname) ($(int.errstr))",
                       ref.excname, int.excname, 0, tailsig(ref), tailsig(int))
    end
    if ref.status === :done && int.status === :threw
        return Verdict(:interp_only_throw,
                       "interp threw $(int.excname): $(int.errstr)",
                       :none, int.excname, 0, tailsig(ref), tailsig(int))
    end
    return Verdict(:ref_only_throw,
                   "ref threw $(ref.excname): $(ref.errstr); interp completed",
                   ref.excname, :none, 0, tailsig(ref), tailsig(int))
end

# Salt for exception-class fingerprints. Without it every interp-only
# UndefVarError (say) shares one dedup bucket, so the first such finding ever
# reported permanently masks every later, unrelated one.
#
# The shape of the *last* observation before the throw is the discriminator: it
# says what the program was doing when it diverged. Deliberately not the stream
# length or the divergence index — those change on almost every statement
# removal, and the shrinker only keeps edits that preserve the fingerprint, so
# an unstable salt would reject nearly every shrink step.
function tailsig(o::Outcome)
    isempty(o.obs) && return :empty
    return obssig(o.obs[end])
end

function divdetail(ref::Outcome, int::Outcome, i::Int)
    r = i <= length(ref.obs) ? repr(ref.obs[i]) : "<none>"
    t = i <= length(int.obs) ? repr(int.obs[i]) : "<none>"
    return "obs[$i]: ref=$(first(r, 200)) interp=$(first(t, 200))"
end

# A candidate divergence that did not survive the confirm-on-divergence gate:
# one of the two sides disagreed with *itself* on a re-run, so the difference
# the oracle saw says nothing about the interpreter. Tracked like `:aborted` —
# counted in campaign stats, never deduped, shrunk or reported.
nondetverdict(side::Symbol) =
    Verdict(:nondet_discard,
            side === :ref ? "reference side disagreed with itself on re-run" :
                            "interpreted side disagreed with itself on re-run",
            :none, :none, 0)

isfinding(v::Verdict) =
    v.class !== :agree && v.class !== :aborted && v.class !== :nondet_discard

# Deduplication key. Deliberately excludes the divergence index (it moves
# under shrinking) and any message text (it drifts across Julia versions), but
# includes the divergent observations' shape signatures: without them every
# value divergence collapses into a single fingerprint, and the first one ever
# reported would mask all future, unrelated value bugs as duplicates.
fingerprint(v::Verdict) =
    string(v.class, "-",
           string(hash((v.class, v.refexc, v.intexc, v.refsig, v.intsig)), base=16)[1:min(8, end)])

# ---------------------------------------------------------------------------
# Confirm-on-divergence (determinism.md §6)
#
# A finding used to be reported after exactly one reference run and one
# interpreted run, which makes any nondeterminism anywhere — a grammar rule
# that reaches an address-derived value, a prelude oversight, a corpus fragment
# consuming a process counter — indistinguishable from an interpreter bug.
#
# So before a divergence is allowed to become a finding, each side is asked to
# reproduce *itself*: rerun the reference and compare against the reference
# outcome the verdict was built from; if that is stable, rerun the interpreted
# side in the same mode and compare likewise. A side that disagrees with itself
# means the candidate is nondeterministic and the verdict is not about the
# interpreter — `nondet_discard`, tracked next to `aborted`, never reported.
#
# The reference goes first because it is the cheap side and because it is the
# more common source of the problem (the interpreted side runs the same
# generated code, just slower). Cost lands only on divergences, so the
# agreement path — every candidate but a handful — pays nothing.

"""
    confirm(src, ref, int; nstmts, interp) -> Symbol

Re-run each side of a candidate divergence, in order, and report the first one
that fails to reproduce its own outcome: `:nondet_ref`, `:nondet_interp`, or
`:stable` if both agree with themselves.
"""
function confirm(src::String, ref::Outcome, int::Outcome; nstmts::Int,
                 interp::Interpreter=RecursiveInterpreter())::Symbol
    ex = parsegate(src)
    # Unreachable in practice (the caller only has outcomes because the same
    # source passed the gate), but "cannot re-run it" must mean "cannot confirm
    # it", never "report it unconfirmed".
    ex === nothing && return :nondet_ref
    outcomeeq(ref, run_ref(ex)) || return :nondet_ref
    outcomeeq(int, run_interp(ex; nstmts, interp)) || return :nondet_interp
    return :stable
end

"""
    confirmed(v, src, ref, int; nstmts, interp) -> Verdict

The gate as a verdict transformer: findings that survive confirmation are
returned unchanged, findings that do not become `:nondet_discard`, and
non-findings (`:agree`/`:aborted`) pass through without paying for a re-run.
"""
function confirmed(v::Verdict, src::String, ref::Outcome, int::Outcome; nstmts::Int,
                   interp::Interpreter=RecursiveInterpreter())::Verdict
    isfinding(v) || return v
    st = confirm(src, ref, int; nstmts, interp)
    st === :stable && return v
    return nondetverdict(st === :nondet_ref ? :ref : :interp)
end

"""
    confirmsrc(src, fp; nstmts, interp) -> Bool

Confirmation from source alone: run both sides, require a finding with
fingerprint `fp`, then require both sides to reproduce themselves. Used after
shrinking, where the outcomes the verdict was built from belong to a *different*
program than the one about to be written to `findings/`.
"""
function confirmsrc(src::String, fp::String; nstmts::Int,
                    interp::Interpreter=RecursiveInterpreter())::Bool
    r = run_both(src; nstmts, interp)
    r === nothing && return false
    ref, int = r
    v = classify(ref, int)
    (isfinding(v) && fingerprint(v) == fp) || return false
    return confirm(src, ref, int; nstmts, interp) === :stable
end

"""
    confirmreport(origsrc, shrunksrc, fp; nstmts, interp) -> String | nothing

Last gate before `writefinding`. Prefers the shrunk program; falls back to the
pre-shrink one if shrinking landed on something that no longer confirms (the
shrinker only checks the fingerprint once per edit, so it can walk into a
flaky neighbour); returns `nothing` when neither confirms, which is a
`nondet_discard` — the finding is not written.
"""
function confirmreport(origsrc::String, shrunksrc::String, fp::String; nstmts::Int,
                       interp::Interpreter=RecursiveInterpreter())
    confirmsrc(shrunksrc, fp; nstmts, interp) && return shrunksrc
    origsrc == shrunksrc && return nothing
    confirmsrc(origsrc, fp; nstmts, interp) && return origsrc
    return nothing
end
