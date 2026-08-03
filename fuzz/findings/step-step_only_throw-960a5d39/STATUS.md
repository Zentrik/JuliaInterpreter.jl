# Status: UNDER TRIAGE — reproduces, breakpoint-specific, likely real

Found by the `step` axis on the `-O1` local campaign (2026-08-03), via the new
real-breakpoint driver.

- **Reproduces deterministically** by replaying `step_program(SRC;
  walkseed=5311061205655927257)`:
  `AssertionError: is_leaf(frame)` at `src/interpret.jl:779` inside
  `step_expr!`, reached through `debug_command` (`commands.jl:660`).
- **Breakpoint-specific**: with `usebreakpoints=true` it throws (after 6
  breakpoint actions, `nbp=6`); with `usebreakpoints=false` the same walk on
  the same seed completes cleanly (`status=done`). So it is the
  breakpoints × stepping interaction, not plain stepping.
- **Public-API, standard usage**: the walk passes the frame returned by the
  previous `debug_command` back into the next one — the same loop pattern
  `test/debug.jl` uses (e.g. `cframe,_ = debug_command(frame,:s);
  debug_command(cframe,:c)`) and the one Debugger.jl uses. So the sequence is
  legitimate; `debug_command` returning a frame it then rejects with an
  internal assertion is the shape of a real debugger bug.

## Mechanism (hypothesis)

`step_expr!` asserts `is_leaf(frame)` — it must run only on the innermost
frame. Some `debug_command` in the walk invokes `step_expr!` on a **non-leaf**
frame. The trigger is a breakpoint interaction: the driver sets/enables/
disables/removes breakpoints between commands, and a breakpoint that pauses in
a callee (or is removed/toggled while a callee frame is active) appears to
leave the walk stepping a parent frame while a callee is still on the stack.

## The fork to resolve (do NOT report as a confirmed bug until settled)

1. **Real JuliaInterpreter bug**: a legitimate set-breakpoint → pause → step
   sequence can drive `debug_command` to step a non-leaf frame. Fix in
   `src/` (commands.jl/interpret.jl — ensure the stepped frame is always the
   leaf, or handle the paused-callee case), add a regression test in
   `test/debug.jl` or `test/breakpoints.jl`.
2. **Harness misuse**: the driver removes/disables a breakpoint *while paused
   inside the frame it belongs to*, leaving stale state a real session would
   not create. If so, constrain the driver (don't mutate the breakpoint the
   walk is currently paused on) rather than touching `src/`.

Decisive next step: instrument the driver to log the 6 breakpoint actions and
commands leading to the throw; if a `remove`/`toggle`/`disable` of the
currently-paused breakpoint immediately precedes it, lean (2); if a plain
`breakpoint(f)` + pause + `:n`/`:s` sequence trips it, it is (1).

## Also: the step-axis repro is wrong

`writefinding(mode=:step)` emits `reprorun(SRC)` (run-to-completion diff),
which reports NO DIVERGENCE for a *stepping* finding — it does not replay the
walk. Step/evalcode/corpus findings need a repro that replays `(SRC,
walkseed)` through `step_program`. Fix `writefinding`/`reprolib` so step
findings are reproducible from their `repro.jl` alone.
