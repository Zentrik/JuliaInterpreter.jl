# Status: KNOWN call-axis FALSE POSITIVE (unreset program global + certification masking)

Found by the `call` (enter_call) axis on the `-O1` local campaign
(2026-08-03). `reprocall(SRC, 515116876229545754)` reproduces:
`f10/1: native=-6 interp=8528227659402739553`.

## Why it is NOT an interpreter bug

This is the **program-global masking** case the call axis already documents as
accepted (`fuzz/src/callfuzz.jl:290-301`): the harness snapshots and restores
only `__LCG__`/`__VTIME__` between the three calls (native #1, native #2,
interp), **not the program's own mutable globals**. `f10` both reads and writes
the toplevel global `g8`:

```julia
function f10(a11)
    global g8 = (... * (g7 ? (g7 ? g8 : 5) : (true ? g8 : (-2))) ...) + 459  # reads incoming g8
    ...
    return (-10) + max(max((9 * (-6)), __randrange__(1, 4)), g8)             # returns f(new g8)
end
```

At snapshot time `g7 == false`, so the recomputed `g8_new` is
`112 * __randrange__(1,5) * g8_incoming + 459` — a function of the **incoming**
`g8`, which the harness does not reset. The return is
`-10 + max(max(-54, r2), g8_new)`.

- **native #1 and #2 certify (agree) by accident**: both land with `g8_new`
  far below the `max` floor `r2 == 4`, so both return `-10 + 4 = -6`. The clamp
  masks that the two runs left *different* `g8` values behind (g8 is not reset,
  so native #2 reads the g8 native #1 wrote).
- **interp is called third**, reading the further-drifted `g8`, and its
  `g8_new` lands *above* the clamp floor → the large `8528…` value. Different
  input state, not different arithmetic.

So the divergence is entirely explained by `g8` not being reset between calls,
combined with a `max(…, g8)` clamp that hid the drift during the two native
certification runs. The comment at `callfuzz.jl:290` predicted exactly this:
"certification still guards the program's own globals, where the same masking
risk remains and is accepted."

## Recommendation

Do NOT change `src/`. This is a harness-quality item, not an interpreter
defect. Options, if the call axis is kept:

1. **Reset all program globals between the three calls**, not just
   `__LCG__`/`__VTIME__` — e.g. rebuild the module (re-run the definition pass)
   per call, or snapshot every mutable binding after the definition pass and
   restore before each call. (In-place-mutated structs like `sv9` need value
   restoration, not just rebinding, so a per-call fresh module is the clean
   version — at 3× module builds per call.)
2. If the call axis proves persistently noisy (this is the 2nd call-axis
   candidate that resolves to a harness artifact — cf. `call-8a9f8dee`),
   **downweight or drop it** in `longrun.sh` rather than paying (1)'s cost.

Both call-axis candidates to date (`8a9f8dee`, `700181ab`) have resolved to
harness calibration, not interpreter bugs — a data point for the "downweight
less-useful avenues" review.
