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

DURATION="${1:-3600}"
shift || true
SHARDS=("$@")
if [ ${#SHARDS[@]} -eq 0 ]; then
    SHARDS=(native step step2 call corpus misc)
fi

LOGDIR="fuzz/longrun"
mkdir -p "$LOGDIR"
DEADLINE=$(( $(date +%s) + DURATION ))

# Per-batch case counts, chosen so a batch is minutes rather than hours: the
# loop can only react to the deadline between batches. $2 is the batch number,
# used by the alternating misc shard.
batch_args() {
    case "$1" in
        native)     echo "--engine native --n 4000 --modes both" ;;
        native-big) echo "--engine native --n 1500 --modes both --big" ;;
        step|step2) echo "--engine step --n 1500" ;;
        evalcode)   echo "--engine evalcode --n 1200" ;;
        corpus)     echo "--engine corpus --n 800 --maxsplice 4" ;;
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
        timeout 1800 $JULIA_CMD --project=fuzz fuzz/run.jl $args \
            --seed "$seed" --nosync --noshrink --journaldir "$jdir" >> "$log" 2>&1
        echo "--- exit $? ---" >> "$log"
        seed=$((seed + 100000))
    done
    echo "=== $name done after $batch batches ===" >> "$log"
}

echo "longrun: ${#SHARDS[@]} shards for ${DURATION}s -> $LOGDIR/"
i=0
for s in "${SHARDS[@]}"; do
    i=$((i + 1))
    # 10^8 apart: shards advance 100000 per batch, so the old 10^6 spacing made
    # shard i re-explore shard i+1's seed range after ten batches.
    run_shard "$s" $(( i * 100000000 )) &
done
wait
echo "longrun: complete"
