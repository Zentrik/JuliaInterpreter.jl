# Status: DUPLICATE of the Future-redefinition class (d4a272b3) — under root-cause triage

Same signature as `corpusvalue-interp_only_throw-d4a272b3` and `-938d349c`:
`interp threw ErrorException: invalid redefinition of constant Future`, on a
spliced copy of Julia's stdlib `Future` module (`Core.@doc "…" module Future …
end`) with `using Distributed` (which exports `Future`) in the prelude.

**This is NOT confirmed to be a false positive.** Earlier notes called the
whole class an "environment mismatch," but the environment (repaired prelude)
is applied identically to the reference and interpreted runs
(`corpus.jl:corpus_run`). The real difference is evaluation strategy: the
reference runs the fragment statement-by-statement with `Core.eval` (latest
world, treats `module Future` over an imported `Future` as allowed
shadowing), while the interpreter runs the whole batch through
`ExprSplitter`/`Frame` and raises a redefinition error. That is either a
genuine interpreter bug in how it evaluates `module`/`const`/method-def
toplevel forms against imported bindings, or a batch-vs-sequential world-age
artifact fixable in the harness.

Root-cause investigation tracked under d4a272b3. Do not suppress-and-forget;
resolve the fork there.
