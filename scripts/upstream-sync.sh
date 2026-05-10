#!/bin/sh
# upstream-sync.sh - fast-forward zig from upstream, push origin, branch off
#
# Usage: scripts/upstream-sync.sh <topic-branch>
#
# Refuses to run with a dirty working tree.
# Refuses non-fast-forward zig updates (lets git fail loudly).
# Pushes the freshly-merged zig to origin.
# Switches to the requested topic branch (creates it if needed).

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <topic-branch>" >&2
    exit 64
fi
topic="$1"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "upstream-sync: working tree is dirty; commit or stash first" >&2
    exit 1
fi

echo "upstream-sync: fetching upstream..." >&2
git fetch upstream

echo "upstream-sync: switching to zig and fast-forwarding..." >&2
git switch zig
git merge --ff-only upstream/zig

echo "upstream-sync: pushing origin/zig..." >&2
git push origin zig

if git show-ref --verify --quiet "refs/heads/$topic"; then
    echo "upstream-sync: switching to existing topic branch $topic" >&2
    git switch "$topic"
else
    echo "upstream-sync: creating topic branch $topic" >&2
    git switch -c "$topic"
fi
