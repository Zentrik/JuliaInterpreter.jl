# The oracle: compare the two Outcomes and classify any divergence.

struct Verdict
    class::Symbol   # :agree | :aborted | :value_divergence | :exception_divergence |
                    # :interp_only_throw | :ref_only_throw
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

isfinding(v::Verdict) = v.class !== :agree && v.class !== :aborted

# Deduplication key. Deliberately excludes the divergence index (it moves
# under shrinking) and any message text (it drifts across Julia versions), but
# includes the divergent observations' shape signatures: without them every
# value divergence collapses into a single fingerprint, and the first one ever
# reported would mask all future, unrelated value bugs as duplicates.
fingerprint(v::Verdict) =
    string(v.class, "-",
           string(hash((v.class, v.refexc, v.intexc, v.refsig, v.intsig)), base=16)[1:min(8, end)])
