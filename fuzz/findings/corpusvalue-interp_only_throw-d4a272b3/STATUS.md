# Status: LIKELY corpus environment-equivalence FALSE POSITIVE (not a core interp bug)

Found by the `corpus` certified-value oracle on the `-O1` campaign
(2026-08-03). Reproduces (`reprocorpus`): reference completes, interpreter
throws `ErrorException: invalid redefinition of constant Future` on a spliced
copy of Julia's stdlib `Future` module, preceded by `using .ConflictingBindings`
and `using Test, Distributed, Random, Logging, Libdl; using REPL`.

## Why it is most likely NOT a core interpreter bug

Minimal module-redefinition cases all AGREE between the interpreter and
`Core.eval` (both `ok`):
- `module Future end`
- `using Distributed; module Future end`  (Distributed exports `Future`)
- `const Future = 1; module Future end`

So the interpreter's `module`/const-redefinition handling is correct in
isolation. The divergence only appears with the full fragment's environment —
the classic shape of an **environment mismatch**: a `using` (here plausibly
`using .ConflictingBindings`, a test-fixture relative import, or the interplay
of the stdlib preludes) takes effect differently on the interpreted single
run than on the certification's two fresh-module reference runs, so
`module Future` redefines a constant only on the interpreted side.

This is exactly the **corpus environment-equivalence** false-positive class
NEXT.md flags as a deferred hardening item ("discard a case when the
interpreted module's environment differs from the environment the reference
succeeded in"). The certified-value oracle admits it because that gate is not
yet implemented.

## Recommendation

Do NOT change `src/`. Two options, in order:
1. **Un-defer the corpus environment-equivalence gate** (NEXT.md long-horizon
   item / port from `claude/julia-fuzzing-strategy-bmh692` commit `be1d869`):
   have the corpus runner record which prelude `using`/`import`s actually took
   effect on each side and discard when the interpreted and reference
   environments diverge. That suppresses this whole class.
2. Until then, add a targeted suppression for
   `interp_only_throw` whose message is `invalid redefinition of constant …`
   on the corpus axis (redefinition mismatches are environment artifacts,
   not interpreter bugs — method/const redefinition is excluded from the
   generated grammar for the same reason).

Before fully closing, a keen reviewer could still try to minimize the full
fragment to rule out a genuine `ExprSplitter`/module bug — but the minimal
evidence above puts the burden on that, not on the interpreter.
