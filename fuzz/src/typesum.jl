# Type summaries ("TySum"): the generator's small type lattice.
#
# These are *summaries*, not Julia types: they tell the generator what an
# expression is likely to produce so it can pick compatible operands. They are
# deliberately imprecise — AnyT and joins exist so the generator can emit
# type-unstable code on purpose (dynamic dispatch through the interpreter's
# localmethtable is a prime divergence target).

abstract type TySum end

struct ConcT <: TySum
    t::Symbol   # :Int, :Float, :Bool, :Str, :Sym, :Char, :Nothing
end
struct TupT <: TySum
    elts::Vector{TySum}
end
struct VecT <: TySum
    elt::TySum
end
# Content-keyed associative containers (determinism.md §4). Julia's `hash` for
# the whitelisted key types (Int/String/Symbol/Char/Bool and tuples of those)
# is content-based and identical across the two engines, so iteration order is
# a deterministic function of insertion + hashes + table geometry — identical on
# both sides. That makes the *full* value oracle apply, iteration order included
# (§4). Mutable/objectid-keyed containers (class X) are deliberately unreachable:
# the key-type menus below never offer a mutable summary.
struct DictT <: TySum
    k::TySum
    v::TySum
end
struct SetT <: TySum
    elt::TySum
end
struct FnT <: TySum
    psums::Vector{TySum}   # what the callee expects positionally
    ret::TySum
end
arity(f::FnT) = length(f.psums)
struct StructT <: TySum
    name::Symbol
    fieldnames::Vector{Symbol}
    fieldsums::Vector{TySum}
    ismutable::Bool
    atomicmask::Vector{Bool}   # per-field `@atomic` (mutable structs only)
end
StructT(name::Symbol, fieldnames, fieldsums, ismutable::Bool) =
    StructT(name, fieldnames, fieldsums, ismutable, fill(false, length(fieldnames)))
struct AnyT <: TySum end

const IntT = ConcT(:Int)
const FloatT = ConcT(:Float)
const BoolT = ConcT(:Bool)
const StrT = ConcT(:Str)
const SymT = ConcT(:Sym)
const CharT = ConcT(:Char)
const NothingT = ConcT(:Nothing)

# `compat(want, have)`: may a value summarized as `have` be used where the
# generator wants `want`? Strict on concrete summaries; AnyT wants accept
# anything, but AnyT values only flow into AnyT positions (uses that could
# throw on a surprise type must be guarded or explicitly Any-typed).
compat(::AnyT, ::TySum) = true
compat(want::ConcT, have::ConcT) = want.t === have.t
compat(want::VecT, have::VecT) = compat_eq(want.elt, have.elt)
compat(want::DictT, have::DictT) = compat_eq(want.k, have.k) && compat_eq(want.v, have.v)
compat(want::SetT, have::SetT) = compat_eq(want.elt, have.elt)
compat(want::TupT, have::TupT) =
    length(want.elts) == length(have.elts) &&
    all(compat_eq(w, h) for (w, h) in zip(want.elts, have.elts))
compat(want::FnT, have::FnT) = arity(want) == arity(have)
compat(want::StructT, have::StructT) = want.name === have.name
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
    s.t === :Char && return "Char"
    s.t === :Nothing && return "Nothing"
    error("unreachable typename $(s.t)")
end
typename(s::VecT) = "Vector"
typename(s::TupT) = "Tuple"
typename(::DictT) = "Dict"
typename(::SetT) = "Set"
typename(::FnT) = "Function"
typename(s::StructT) = String(s.name)
typename(::AnyT) = "Any"

# Fully-parameterized Julia type string for *constructing* a value (e.g.
# `Dict{Int64, Float64}`), as opposed to `typename` which gives the bare head
# used for a `::T` annotation. Only the summaries that can appear as Dict/Set
# key/value/element types need to round-trip here; anything else falls back to
# `Any`, which is always a valid construction annotation.
juliatypestr(s::ConcT) = typename(s)
juliatypestr(s::VecT) = "Vector{" * juliatypestr(s.elt) * "}"
juliatypestr(s::TupT) = "Tuple{" * join(map(juliatypestr, s.elts), ", ") * "}"
juliatypestr(s::DictT) = "Dict{" * juliatypestr(s.k) * ", " * juliatypestr(s.v) * "}"
juliatypestr(s::SetT) = "Set{" * juliatypestr(s.elt) * "}"
juliatypestr(::TySum) = "Any"
