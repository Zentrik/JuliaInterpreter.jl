# Status: FIXED — was a GENUINE interpreter bug (NOT an environment false positive)

Found by the `corpus` certified-value oracle on the `-O1` campaign
(2026-08-03). The interpreter threw `ErrorException: invalid redefinition of
constant Future` on a spliced copy of Julia's stdlib `Future` module, where
compiled Julia (`Core.eval`) completed.

## Resolution

This was **misdiagnosed** as a corpus environment-equivalence false positive.
It is a real JuliaInterpreter bug, now **fixed** in `src/construct.jl`
(`find_or_create_module`), with a regression test in `test/toplevel.jl`
("module shadows a using-imported non-module binding").

### Root cause

`find_or_create_module` unconditionally threw
`invalid redefinition of constant $newname` whenever `newname` was already a
defined global that was not itself a `Module`:

```julia
found = invokelatest(getglobal, parentmod, newname)
found isa Module || throw(ErrorException("invalid redefinition of constant $(newname)"))
```

When `using Distributed` (or any `using` exporting a non-module `Future`) is in
scope, `Future` resolves to `Distributed.Future` (a `DataType`). Native
toplevel `Core.eval(parentmod, :(module Future end))` **shadows** that
`using`-import with a fresh submodule — ordinary, well-defined Julia (same as
`include`). The interpreter's guard rejected exactly this legal case.

### Why the "environment mismatch" framing was wrong

The corpus prelude is applied *identically* to the reference and interpreted
runs (`corpus.jl` `corpus_run`), so there was no uncontrolled environment
difference. The minimal trigger is a **single statement**
(`using Distributed; module Future end`), so it is not a batch-vs-sequential
world-age artifact either. Native `Core.eval` and the interpreter disagreed in
the same module, same world, same imports — a genuine divergence.

### Fix

Take the module-reuse fast path only when `found isa Module`; for a non-module
`found`, fall through to `Core.eval(parentmod, module_ex)`, which shadows the
import (or raises Julia's own error for a true owned redefinition), matching
native evaluation by construction. Selftest 437/437; `test/toplevel.jl` green.

The `env_binding_mismatch` suppression in `fuzz/src/driver.jl` no longer
suppresses `redefinition of constant` — a regression will now surface as real
news. Duplicates of this signature: `-254b14e6`, `-938d349c`.
