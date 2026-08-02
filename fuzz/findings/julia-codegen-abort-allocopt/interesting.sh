#!/usr/bin/env bash
# Interestingness test for reducing the alloc-opt codegen abort.
#
#   interesting.sh [FILE]     # default: ./minimized.jl (C-Reduce's convention)
#   exit 0  -> still the crash we are chasing
#   exit 1  -> not interesting, discard this reduction
#
# Any reducer (C-Reduce, C-Vise, a Julia AST reducer) is only as good as this
# script. The trap it exists to avoid: reducing toward *a* crash rather than
# *this* crash. "Died by a signal" alone is satisfied by a stack overflow from
# runaway recursion, an out-of-memory kill, or an unrelated assertion — all of
# which a reducer will happily converge on, leaving a small program that
# reproduces nothing of interest. So match the specific assertion site.
#
# Runtime exceptions are deliberately swallowed. The abort happens while the
# `let` block's thunk is *compiled*; the program's own UndefVarErrors and
# MethodErrors are irrelevant to it, and refusing them would block reductions
# that delete a definition while keeping the crashing code path.

set -u
FILE="${1:-minimized.jl}"
[ -f "$FILE" ] || exit 1

JULIA="${JULIA:-julia}"
TIMEOUT="${TIMEOUT:-90}"

# Fresh module, statement by statement, exceptions ignored.
RUNNER=$(mktemp /tmp/interesting-runner.XXXXXX.jl)
trap 'rm -f "$RUNNER"' EXIT
cat > "$RUNNER" <<'JLEOF'
m = Module(:CrashCase)
for st in Meta.parseall(read(ARGS[1], String)).args
    st isa LineNumberNode && continue
    try
        Core.eval(m, st)
    catch
    end
end
JLEOF

out=$(timeout "$TIMEOUT" "$JULIA" --startup-file=no "$RUNNER" "$FILE" 2>&1)
rc=$?

# 124 = timeout(1). A hang is not this bug, and letting it count would let the
# reducer wander into infinite loops.
[ "$rc" -eq 124 ] && exit 1
# A clean run or an ordinary Julia error exit is not a crash.
[ "$rc" -lt 128 ] && exit 1

# The signature: the abort must come from the allocation-optimization pass.
echo "$out" | grep -q "llvm-alloc-opt" || exit 1
echo "$out" | grep -q "moveToStack"    || exit 1
# Guard against converging on a different fatal path that happens to touch the
# same pass — a genuine stack overflow prints its own banner.
echo "$out" | grep -qi "StackOverflow" && exit 1

exit 0
