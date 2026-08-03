# Status: UNDER TRIAGE — reproduces, likely real (wrong exception type)

Found by the `call` axis on the `-O1` local campaign (2026-08-03), on the
**fixed** code (post the PRNG-state fix 25d816e), so this is NOT the earlier
call-axis false-positive class.

- **Reproduces deterministically**: `reprocall` on `(src, callseed)` yields
  `call_value_divergence: f8/1; kw=[:kw10]: native=(:__thrown, :TypeError)
  interp=(:__thrown, :ErrorException)` every run. Passed the whole-candidate
  confirm gate, so it is stable, not nondeterminism.
- **Shape**: a callee `f8(a9; kw10, kw11)` (with a sibling method
  `f8(a12::Int64)` that takes no kwargs) is called with a synthesized `kw10`.
  The callee body internally guards `Base.checked_udiv_int(kw10, kw10)` and
  returns `(:__thrown, nameof(typeof(exc)))`. Native catches a `TypeError`;
  the interpreter catches an `ErrorException`.
- **Not `checked_udiv_int` alone**: standalone
  `checked_udiv_int(x, x)` for x ∈ {Float64, Float32, String, Symbol, Tuple,
  Vector, Nothing, Int, Bool, UInt8} does NOT reproduce the TypeError-vs-
  ErrorException split (both sides agree). So the divergence comes from the
  **kwarg-dispatch / kwsorter path** feeding `kw10` — a hand-implemented
  interpreter surface — not the intrinsic in isolation. That makes it a
  plausible real interpreter bug in the same family as the invoke fix (wrong
  exception type from a hand-reimplemented path).

## To finish

Minimize with the call-axis shrinker (or by hand): reduce to the smallest
`f8` + call that still splits TypeError vs ErrorException. Determine whether
the divergence is (a) a genuine interpreter kwsorter/dispatch exception-type
bug — fix in `src/`, add a regression test — or (b) the known
malformed-intrinsic-arg class reintroduced because the call axis synthesizes a
`kw10` whose type violates the callee's internal `checked_udiv_int` usage, in
which case constrain the call axis's argument synthesis (as the prober shapes
intrinsic args) rather than touching the interpreter. Do NOT report it as a
confirmed interpreter bug until that fork is resolved.
