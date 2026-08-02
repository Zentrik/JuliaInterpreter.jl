# The oracle: compare the two Outcomes and classify any divergence.

struct Verdict
    class::Symbol   # :agree | :aborted | :value_divergence | :exception_divergence |
                    # :interp_only_throw | :ref_only_throw
    detail::String
    refexc::Symbol
    intexc::Symbol
    dividx::Int     # first divergent observation index (0 if n/a)
end

agree() = Verdict(:agree, "", :none, :none, 0)

# First index where the observation streams disagree; 0 if one is a prefix of
# the other.
function firstdiff(a::Vector{Any}, b::Vector{Any})
    n = min(length(a), length(b))
    for i in 1:n
        isequal(a[i], b[i]) || return i
    end
    return 0
end

function classify(ref::Outcome, int::Outcome)::Verdict
    d = firstdiff(ref.obs, int.obs)
    if int.status === :aborted
        # Budget ran out mid-program: only comparable up to the observations the
        # interpreter made. A mismatched prefix is still a real divergence.
        d != 0 && length(int.obs) >= d &&
            return Verdict(:value_divergence, divdetail(ref, int, d), :none, :none, d)
        return Verdict(:aborted, "", :none, :none, 0)
    end
    if d != 0
        return Verdict(:value_divergence, divdetail(ref, int, d), ref.excname, int.excname, d)
    end
    if ref.status === :done && int.status === :done
        length(ref.obs) == length(int.obs) && return agree()
        return Verdict(:value_divergence,
                       "observation count: ref=$(length(ref.obs)) interp=$(length(int.obs))",
                       :none, :none, min(length(ref.obs), length(int.obs)) + 1)
    end
    if ref.status === :threw && int.status === :threw
        if ref.excname === int.excname
            length(ref.obs) == length(int.obs) && return agree()
            return Verdict(:value_divergence,
                           "observation count before throw: ref=$(length(ref.obs)) interp=$(length(int.obs))",
                           ref.excname, int.excname, min(length(ref.obs), length(int.obs)) + 1)
        end
        return Verdict(:exception_divergence,
                       "ref threw $(ref.excname) ($(ref.errstr)); interp threw $(int.excname) ($(int.errstr))",
                       ref.excname, int.excname, 0)
    end
    if ref.status === :done && int.status === :threw
        return Verdict(:interp_only_throw,
                       "interp threw $(int.excname): $(int.errstr)",
                       :none, int.excname, 0)
    end
    return Verdict(:ref_only_throw,
                   "ref threw $(ref.excname): $(ref.errstr); interp completed",
                   ref.excname, :none, 0)
end

function divdetail(ref::Outcome, int::Outcome, i::Int)
    r = i <= length(ref.obs) ? repr(ref.obs[i]) : "<none>"
    t = i <= length(int.obs) ? repr(int.obs[i]) : "<none>"
    return "obs[$i]: ref=$(first(r, 200)) interp=$(first(t, 200))"
end

isfinding(v::Verdict) = v.class !== :agree && v.class !== :aborted

# Deduplication key. Deliberately excludes the divergence index (it moves
# under shrinking) and any message text (it drifts across Julia versions).
fingerprint(v::Verdict) = string(v.class, "-", string(hash((v.class, v.refexc, v.intexc)), base=16)[1:min(8, end)])
