mutable struct S
    @atomic x::Int
end
f() = (s = S(0); @atomic s.x += 1)
f()
