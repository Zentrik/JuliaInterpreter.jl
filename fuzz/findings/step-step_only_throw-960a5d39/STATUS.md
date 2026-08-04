# Status: FIXED — real debugger bug (breakpoint in kwarg value broke the is_leaf invariant)

Found by the `step` axis (real-breakpoint driver) on the `-O1` campaign
(2026-08-03); triaged + fixed.

## Root cause

When a command steps through keyword-argument setup and the kwarg *value* is
itself a call to a breakpointed function, the breakpoint fires mid-kwprep.
`advance_to_kwcall!` (`src/commands.jl`) discarded the returned `BreakpointRef`
and left `frame` **non-leaf** (a callee paused at the breakpoint). `debug_command`
then returned that non-leaf frame with an ordinary integer pc — violating the
`is_leaf(frame)` invariant that `step_expr!` asserts. Feeding the returned frame
back into the next command (the documented `debug_command` loop, used by
Debugger.jl and `test/debug.jl`) crashed with `AssertionError: is_leaf(frame)`.
The breakpoint was also silently lost.

## Fix

`src/commands.jl`: after each `maybe_step_through_kwprep!` in `debug_command`
(the `:nc` path via `nicereturn!`, and the two `:s`-path sites), detect a
non-leaf frame and surface a normal pause at the leaf with a `BreakpointRef`
(`kwprep_breakpoint!` helper). The breakpoint now pauses correctly inside the
kw-value call instead of corrupting the frame.

Verified: the minimal public-API repro (`breakpoint(kwval); debug_command(frame,
:nc)`) now returns a leaf frame paused at the breakpoint, `:c` resumes cleanly,
and `:s` behaves the same. Regression test added to `test/breakpoints.jl`
("breakpoint in kwarg value survives stepping (is_leaf invariant)", 8/8);
`test/debug.jl` + `test/breakpoints.jl` green; fuzz selftest passes.

## Note: the step-axis repro.jl is still wrong (separate harness item)

`writefinding(mode=:step)` emits `reprorun(SRC)`, which runs to completion and
diffs observations — it does NOT replay the walk, so this finding's `repro.jl`
alone shows "no divergence". The bug reproduces via the public-API sequence
above (and the step-axis walk with `usebreakpoints=true`). Fixing
`writefinding`/`reprolib` to emit a `reprostep(SRC, walkseed)` that replays the
walk is a tracked harness follow-up (`fuzz/src/driver.jl` reprocall selector).
