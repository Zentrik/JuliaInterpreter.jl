# Status: UNDER TRIAGE — call-axis exception-TYPE divergence (fork: real vs harness)

Found by the `call` axis on the `-O1` campaign (2026-08-03).
`reprocall(SRC, 7067809865547766385)` reproduces:
`f16/1: native=(:__thrown, :UndefVarError) interp=(:__thrown, :ArgumentError)`.

Both sides throw; the **exception type** differs. `f16`'s body:

```julia
function f16(va17...)
    v18 = S1((@atomic (sv10).fld4))          # S1, sv10 both defined at toplevel
    v20 = Float64[... for c19 in 1:2 if ...]
    return (try Core._svec_ref(Base.compilerbarrier(:const, g6)) catch __e; (:__thrown, nameof(typeof(__e))) end)
end
```

`g6` and `sv10` are both assigned at toplevel (`g6 = :c`, `sv10 = S3(...)`), so
neither is an obviously-undefined read. The native `UndefVarError` is therefore
not from a plainly-missing global — its source (a field/type resolution, `S1`
vs `S3` mismatch, or `Core._svec_ref` internals) needs to be pinned.

## The fork (do NOT report as confirmed until settled)

1. **Real interpreter bug**: the interpreter reaches a different throw site than
   native for the same call — e.g. it does not raise `UndefVarError` where
   native does and instead proceeds into `Core._svec_ref` (→ `ArgumentError`).
   That would be a genuine divergence worth a minimal repro + fix.
2. **Call-axis harness artifact**: like `700181ab`/`8a9f8dee`, the direct
   `enter_call` invocation leaves the module in a state (unreset program
   globals, world-age of `latesttargets`) where the interpreter's call sees
   different global definedness than the native call.

Decisive next step: minimize to the single throwing expression and check
whether a plain undefined-global read (or `Core._svec_ref` with a bad arg)
diverges between `@interpret` and native in isolation. If it reproduces
stand-alone → (1); if only under the call-axis harness → (2).

This is the 3rd call-axis candidate; all three so far lean harness — a data
point for the "downweight less-useful avenues" review.
