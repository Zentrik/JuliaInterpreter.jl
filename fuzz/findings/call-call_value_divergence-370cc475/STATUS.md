# Status: RESOLVED — NOT an interpreter bug (interpreter is CORRECT; native codegen is the unstable/UB side)

Triaged + verified 2026-08-03.

## What it actually is

`f16`'s return runs `Core._svec_ref(compilerbarrier(:const, g6))` — a
`Core.Builtin` requiring 2 args `(SimpleVector, index)` called with **1**. The
divergence: `native=(:__thrown, :UndefVarError) interp=(:__thrown, :ArgumentError)`.

The **interpreter is the correct party**: it throws a clean, stable
`ArgumentError: _svec_ref: too few arguments (expected 2)` in every context.

The **native side's exception is optimization-context-dependent** for this
statically-arity-wrong builtin call. The triage bot observed native throw
`UndefVarError` / `BoundsError` / `ArgumentError` across different call sites, and
reported a corrupted exception object whose `showerror` **segfaulted** in one
compiled context (concrete-eval UB under `-O1`).

## Verification

I could NOT reproduce the corrupted-exception/segfault in simple contexts: at top
level AND inside a `@noinline` function at `-O1`, native throws a clean
`ArgumentError` and `showerror` works (subprocess exit 0), agreeing with the
interpreter. The dramatic native UB only appears in specific optimization
contexts (matching the bot's per-call-site table). Either way, the interpreter is
stable and correct; the native exception is the variable/broken side.

## Disposition

- **No `src/` change.** The interpreter already produces the right, stable error.
- **Possible upstream Julia bug** (low priority): a too-few-arguments
  `Core.Builtin` call, under compilation/concrete-eval at `-O1`, can produce a
  context-dependent or corrupted exception object (type tag ≠ message; a
  `showerror` segfault was observed by the triage bot). If a clean minimal repro
  can be pinned it is worth `findings/julia/`. Not reproducible in the simple
  contexts tried here.
- **Harness:** same gap as `8a9f8dee` — the call axis treats compiled native as
  ground truth with no three-way adjudication, so native-side compiler
  UB/instability surfaces as a "finding." Add three-way (JI-vs-C) adjudication,
  or treat a native exception that is `showerror`-unshowable / type-unstable as an
  uncertified native-UB case rather than a finding.
