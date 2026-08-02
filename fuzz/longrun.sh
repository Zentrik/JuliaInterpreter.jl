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
# Default shards cover all four axes plus a large-program variant of the
# differential one. With four cores, five shards is a slight oversubscription
# on purpose — the corpus shard spends real time in Core.eval compiling
# fragments, so it does not hold a core the whole time.

set -uo pipefail
cd "$(dirname "$0")/.."

DURATION="${1:-3600}"
shift || true
SHARDS=("$@")
if [ ${#SHARDS[@]} -eq 0 ]; then
    SHARDS=(native step corpus evalcode native-big)
fi

LOGDIR="fuzz/longrun"
mkdir -p "$LOGDIR"
DEADLINE=$(( $(date +%s) + DURATION ))

# Per-batch case counts, chosen so a batch is minutes rather than hours: the
# loop can only react to the deadline between batches.
batch_args() {
    case "$1" in
        native)     echo "--engine native --n 4000 --modes both" ;;
        native-big) echo "--engine native --n 1500 --modes both --big" ;;
        step)       echo "--engine step --n 1500" ;;
        evalcode)   echo "--engine evalcode --n 1200" ;;
        corpus)     echo "--engine corpus --n 800 --maxsplice 4" ;;
        *) echo "unknown shard $1" >&2; return 1 ;;
    esac
}

run_shard() {
    local name="$1" seed="$2" args log jdir batch=0
    args="$(batch_args "$name")" || return 1
    log="$LOGDIR/$name.log"
    jdir="fuzz/journal-$name"
    : > "$log"
    while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        batch=$((batch + 1))
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
        timeout 1800 julia --project=fuzz fuzz/run.jl $args \
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
    run_shard "$s" $(( i * 1000000 )) &
done
wait
echo "longrun: complete"
