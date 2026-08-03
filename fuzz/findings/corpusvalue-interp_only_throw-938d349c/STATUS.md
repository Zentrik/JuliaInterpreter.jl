# Status: corpus environment-equivalence FALSE POSITIVE (now suppressed)

Third distinct symptom of the same root cause: the fragment defines
`+(x::DateTime, y::Quarter)` and `DateTime(dt::TimeType)` referencing Dates
types without `using Dates`, so the argument types resolve to types on the
reference side (via import recovery) but not on the interpreted side ->
`ArgumentError: invalid type for argument x in method definition`. Not an
interpreter bug; an environment mismatch. Now caught by the broadened
`env_binding_mismatch` suppression (driver.jl). The durable fix remains the
corpus environment-equivalence gate.
