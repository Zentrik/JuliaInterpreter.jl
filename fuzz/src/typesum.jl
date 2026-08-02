# Type summaries ("TySum"): the generator's small type lattice.
#
# These are *summaries*, not Julia types: they tell the generator what an
# expression is likely to produce so it can pick compatible operands. They are
# deliberately imprecise — AnyT and joins exist so the generator can emit
# type-unstable code on purpose (dynamic dispatch through the interpreter's
# localmethtable is a prime divergence target).

abstract type TySum end

struct ConcT <: TySum
    t::Symbol   # :Int, :Float, :Bool, :Str, :Sym, :Nothing
end
struct TupT <: TySum
    elts::Vector{TySum}
end
struct VecT <: TySum
    elt::TySum
end
struct FnT <: TySum
    psums::Vector{TySum}   # what the callee expects positionally
    ret::TySum
end
arity(f::FnT) = length(f.psums)
struct AnyT <: TySum end

const IntT = ConcT(:Int)
const FloatT = ConcT(:Float)
const BoolT = ConcT(:Bool)
const StrT = ConcT(:Str)
const SymT = ConcT(:Sym)
const NothingT = ConcT(:Nothing)

# `compat(want, have)`: may a value summarized as `have` be used where the
# generator wants `want`? Strict on concrete summaries; AnyT wants accept
# anything, but AnyT values only flow into AnyT positions (uses that could
# throw on a surprise type must be guarded or explicitly Any-typed).
compat(::AnyT, ::TySum) = true
compat(want::ConcT, have::ConcT) = want.t === have.t
compat(want::VecT, have::VecT) = compat_eq(want.elt, have.elt)
compat(want::TupT, have::TupT) =
    length(want.elts) == length(have.elts) &&
    all(compat_eq(w, h) for (w, h) in zip(want.elts, have.elts))
compat(want::FnT, have::FnT) = arity(want) == arity(have)
compat(::TySum, ::TySum) = false

compat_eq(a::TySum, b::TySum) = compat(a, b) && compat(b, a)
compat_eq(a::AnyT, b::TySum) = b isa AnyT
compat_eq(a::TySum, b::AnyT) = a isa AnyT
compat_eq(::AnyT, ::AnyT) = true

# join: least common summary; collapses to AnyT quickly on purpose.
joinsum(a::TySum, b::TySum) = compat_eq(a, b) ? a : AnyT()

isnumeric(s::TySum) = s isa ConcT && (s.t === :Int || s.t === :Float)

# Julia source name for a summary used as a method-parameter annotation.
function typename(s::ConcT)
    s.t === :Int && return "Int64"
    s.t === :Float && return "Float64"
    s.t === :Bool && return "Bool"
    s.t === :Str && return "String"
    s.t === :Sym && return "Symbol"
    s.t === :Nothing && return "Nothing"
    error("unreachable typename $(s.t)")
end
typename(s::VecT) = "Vector"
typename(s::TupT) = "Tuple"
typename(::FnT) = "Function"
typename(::AnyT) = "Any"
