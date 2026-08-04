#!/usr/bin/env bash
# Long unattended fuzzing across every axis.
#
#   fuzz/longrun.sh [SECONDS] [SHARDS...]
#
# Each shard is an independent `run.jl` invocation in a restart loop, because a
# campaign can be ended by something other than finishing: a generated program
# that kills the worker, an OOM, a Julia-level abort. The journal holds the
# candidate that was executing (fsync'd before it ran), so a shard that dies
# leaves its reproducer behind and the loop simply starts the next batch —
# which is what makes "run it long" safe to do unattended.
#
# Seeds advance every batch so restarts explore new ground rather than
# repeating the batch that just died. Each shard gets its own journal
# directory, since journal/current.jl is a single file and concurrent shards
# would otherwise clobber each other's crash evidence. They deliberately
# *share* findings/, so the dedup set is global: a divergence one shard already
# reported does not get re-reported by the other three.
#
# Default shards are weighted by demonstrated yield per hour, not one-per-axis
# (see evaluation-2026-08-03.md and mutantbench-report.md):
#   - step gets TWO shards: it is the one axis with ground-truth validation
#     (rediscovered the whereis-nothing crash at n=300 in the mutant pilot,
#     plus one real crash found historically), and the breakpoint driver just
#     opened breakpoints.jl (13% -> 80% line coverage).
#   - native keeps one: 4 of 5 historical findings, mostly via the prober.
#   - call gets one: brand-new public-API surface, unvalidated but high prior.
#   - corpus keeps one: uniquely reaches 12 builtin arms no generated axis hits.
#   - split and evalcode SHARE one shard (alternating batches): ~14k clean
#     split cases at calibration, evalcode has 0 findings and — per the mutant
#     curation — no clean historical mutant to validate against, so neither
#     earns a full core until one produces.
# native-big remains available by name (program size is the weaker lever).
# With four cores, six shards is a slight oversubscription on purpose — the
# corpus shard spends real time in Core.eval compiling fragments, so it does
# not hold a core the whole time.

set -uo pipefail
cd "$(dirname "$0")/.."

# Which Julia to run. Default `julia`; override with e.g.
# JULIA_CMD="julia +release" to run on a newer channel. On Julia 1.11 a latent
# GC bug (the codegen-abort's sibling, fixed in 1.12) segfaults sustained
# campaigns at an allocation site every few hundred cases — the restart loop
# below survives it, but 1.12 avoids it entirely and is the recommended channel
# for a long run. See NEXT.md.
JULIA_CMD="${JULIA_CMD:-julia}"

# Optimization level for the campaign julia. Default -O1, for two reasons:
#   1. Faster. The reference side JIT-compiles every generated program, so a
#      compile-heavy differential fuzzer is throughput-bound on LLVM; -O1
#      measured ~1.3x faster than the -O2 default.
#   2. Works around the 1.12/1.13 GC-corruption crash. That bug (JuliaLang/julia
#      #59483 / #60622, "fixed" by #60651) is codegen-induced: LICM — an -O2/-O3
#      pass — can materialize an `undef` GC stack root that the collector then
#      marks, segfaulting inside gc-stock.c. -O1 does not run that pass, so it
#      sidesteps the crash; the restart loop is no longer paying for it.
# The oracle stays valid: Julia guarantees semantic equivalence across -O
# levels, so the interpreter must still match the -O1-compiled reference; and
# fewer optimizations means fewer optimization-dependent class-U false positives.
# Set JULIA_OPT=2 to restore the -O2 config (keeps the free Julia-codegen
# fuzzing and reproduces the GC crash for the upstream report).
JULIA_OPT="${JULIA_OPT:-1}"
JULIA_CMD="$JULIA_CMD -O$JULIA_OPT"

DURATION="${1:-3600}"
shift || true
SHARDS=("$@")
if [ ${#SHARDS[@]} -eq 0 ]; then
    SHARDS=(native step step2 call corpus misc)
fi

# Per-run seed offset, so two campaigns explore DIFFERENT programs instead of
# re-testing the same ones. Without this every invocation — local reruns, the
# nightly CI, a second machine — started from the same shard bases and walked
# the same seed sequence, differing only by Julia version. Generation is a pure
# function of the seed, so identical bases meant identical programs and no
# growth in cumulative coverage.
#
# Determinism is preserved where it matters: every finding's meta.md/repro.jl
# records the *absolute* candidate seed, so a bug still reproduces exactly. What
# varies per run is only the starting point. Set SEED_BASE explicitly to replay
# a whole campaign; default is random (bash $RANDOM, 0..32767). The nightly CI
# passes a monotonic per-run value in a disjoint high band (see the workflow).
SEED_BASE="${SEED_BASE:-$RANDOM}"

LOGDIR="fuzz/longrun"
mkdir -p "$LOGDIR"
DEADLINE=$(( $(date +%s) + DURATION ))

# Per-batch case counts, chosen so a batch is minutes rather than hours: the
# loop can only react to the deadline between batches, and a batch that outruns
# the per-batch timeout below is killed mid-flight — losing its tail and (before
# the exit-124 check below existed) leaving a spurious "crash" journal behind.
# Sized to finish inside the 1800 s timeout at measured rates
# (throughput-report.md): native ~2.4/s ⇒ 3500 ≈ 24 min, corpus ~3 s/case ⇒
# 450 ≈ 23 min (800 could never finish and was killed at 30 min every batch).
# $2 is the batch number, used by the alternating misc shard.
batch_args() {
    case "$1" in
        native)     echo "--engine native --n 3500 --modes both" ;;
        native-big) echo "--engine native --n 1500 --modes both --big" ;;
        step|step2) echo "--engine step --n 1500" ;;
        evalcode)   echo "--engine evalcode --n 1200" ;;
        corpus)     echo "--engine corpus --n 450 --maxsplice 4" ;;
        split)      echo "--engine split --n 3000" ;;
        call)       echo "--engine call --n 1500" ;;
        misc)       # split and evalcode alternate on one core (downweighted)
                    if [ $(( ${2:-1} % 2 )) -eq 1 ]; then
                        echo "--engine split --n 3000"
                    else
                        echo "--engine evalcode --n 1200"
                    fi ;;
        *) echo "unknown shard $1" >&2; return 1 ;;
    esac
}

run_shard() {
    local name="$1" seed="$2" args log jdir batch=0
    batch_args "$name" 1 >/dev/null || return 1
    log="$LOGDIR/$name.log"
    jdir="fuzz/journal-$name"
    : > "$log"
    while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        batch=$((batch + 1))
        # Re-derived per batch: the misc shard alternates engines.
        args="$(batch_args "$name" "$batch")"
        # The journal holds the candidate that was executing, but only until the
        # next one overwrites it — so a batch that died leaves its reproducer in
        # current.jl and the *next* batch immediately destroys it. Set it aside
        # first. This is the whole point of journalling a crash: observed on the
        # first real abort of a long run, where a Julia codegen assertion killed
        # a shard and the restart clobbered the program that caused it.
        if [ -f "$jdir/current.jl" ]; then
            mkdir -p "$jdir/crashed"
            mv "$jdir/current.jl" "$jdir/crashed/batch$((batch - 1))-$(date -u +%H%M%S).jl"
        fi
        echo "=== $name batch $batch seed=$seed $(date -u +%H:%M:%S) ===" >> "$log"
        # --nosync: the fsync per candidate is a disk round trip, and the
        # journal write itself (which is what recovers a crash) still happens.
        #
        # -k 30: escalate to SIGKILL if julia does not die from the TERM within
        # 30 s. Without it a julia wedged somewhere TERM cannot reach (observed
        # on the nightly CI lane: the campaign step ran 5h48 against a 3 h
        # DURATION until the runner's 6 h limit cancelled the whole job before
        # any findings were reported) runs unbounded and the deadline check
        # below never gets another look.
        timeout -k 30 1800 $JULIA_CMD --project=fuzz fuzz/run.jl $args \
            --seed "$seed" --nosync --noshrink --journaldir "$jdir" >> "$log" 2>&1
        rc=$?
        echo "--- exit $rc ---" >> "$log"
        # Exit 124 is the batch timeout doing its job: julia honored the TERM,
        # nothing crashed, and the candidate that happened to be in flight is
        # not crash evidence — preserving it (which the top of the next loop
        # iteration would do) buries the real crashes in one spurious entry per
        # oversized batch. Every other nonzero exit keeps its journal: 137
        # (TERM ignored, KILLed) is a genuine hang worth the evidence, and
        # signal deaths are the crashes the journal exists for.
        [ "$rc" -eq 124 ] && rm -f "$jdir/current.jl"
        seed=$((seed + 100000))
    done
    echo "=== $name done after $batch batches ===" >> "$log"
}

echo "longrun: ${#SHARDS[@]} shards for ${DURATION}s, SEED_BASE=$SEED_BASE -> $LOGDIR/"
i=0
for s in "${SHARDS[@]}"; do
    i=$((i + 1))
    # Absolute shard base = SEED_BASE·10^9 + i·10^8. The 10^9 per-run stride sits
    # above the ~6·10^8 a whole run spans (6 shards · 10^8), so distinct SEED_BASE
    # values never overlap. Within a run, shards stay 10^8 apart (each advances
    # 100000/batch, ~10^7 over a long run), so they never collide either.
    run_shard "$s" $(( SEED_BASE * 1000000000 + i * 100000000 )) &
done
wait
echo "longrun: complete"
