#!/usr/bin/env bash
# Commit and push whatever findings/ currently holds.
#
#   fuzz/preserve-findings.sh [message]
#
# findings/ is gitignored — it is scratch output of a campaign, and committing
# every rerun's artifacts would be noise. But a finding produced by a long run
# on a throwaway machine is not scratch: it is the whole point, and it is lost
# when the machine goes away. This force-adds them so a finding survives, and
# does nothing at all when there is nothing to preserve.
set -uo pipefail
cd "$(dirname "$0")/.."

if [ ! -d fuzz/findings ] || [ -z "$(ls -A fuzz/findings 2>/dev/null)" ]; then
    echo "no findings to preserve"
    exit 0
fi

n=$(ls fuzz/findings | wc -l)
msg="${1:-Preserve $n fuzzing finding(s) from a long campaign}"

git add -f fuzz/findings
git commit -q -m "$msg

Reproducers and metadata for findings produced by a long campaign. findings/
is normally gitignored as campaign scratch; these are force-added because the
machine that produced them is ephemeral, and an un-triaged finding is worth
more than a clean ignore list.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CZ19kTvCwoapsrDRPq4TyU" || {
    echo "nothing new to commit"
    exit 0
}

for attempt in 1 2 3 4; do
    git push -u origin HEAD 2>&1 | tail -2 && break
    sleep $((2 ** attempt))
done
echo "preserved $n finding(s)"
