# Status: corpus artifact — lifted test asserts on a native BACKTRACE line (not an interp bug)

Found by the `corpus` axis (`-O1`, 2026-08-03), after the env_binding_mismatch
suppression was removed. `interp threw FallbackTestSetException` where the
reference completed.

## Mechanism (verified from the fragment)

The spliced fragment is a lifted stdlib test:
```julia
let bt, topline = @__LINE__()
    try
        let x = 1; y = 2x; z = 2z - 1 end   # deliberate UndefVarError (z used before def)
    catch
        bt = stacktrace(catch_backtrace())
    end
    @test (bt[1]).line == topline + 4        # asserts the FIRST backtrace frame's SOURCE LINE
end
```
The test deliberately errors, captures `stacktrace(catch_backtrace())`, and asserts
the top frame is at a specific native source line (`topline + 4`). Under compiled
Julia the backtrace's first frame is that line, so the `@test` passes and the
reference completes. Under `RecursiveInterpreter` the backtrace is the
interpreter's OWN frames (different frame set and line info), so the assertion
does not hold, the `@testset` records an error, and it raises
`FallbackTestSetException`.

This is an **inherent property of interpretation**, not a JuliaInterpreter
correctness bug: the interpreter cannot reproduce compiled Julia's exact
`catch_backtrace()` frame/line contents for arbitrary lifted code. Distinct from
the (real, fixed) module/methoddef shadowing class — this fragment tests
implementation details (native stack frames) that interpretation does not
preserve.

## Repro caveat

`reprocorpus(SRC)` shows NO divergence standalone: it does not replay the
campaign's *repaired* prelude, so `@test`/`@testset` are undefined and BOTH sides
throw the same `UndefVarError: @test`. The divergence is real only in-campaign,
where `eval_ref` had added `using Test`. (Same class of gap as the step-axis
repro not replaying the walk — a harness reproducibility follow-up.)

## Disposition

No `src/` change; genuine non-bug. Do NOT broadly suppress `FallbackTestSetException`
(some lifted-test failures could be real interpreter divergences). The durable
corpus-axis handling is to DISCARD fragments whose tests introspect
`backtrace`/`catch_backtrace`/`stacktrace` (they cannot pass under interpretation
by construction) — a targeted corpus filter, not a message suppression. Low
priority; documented so a re-occurrence is recognized, not re-triaged from scratch.
