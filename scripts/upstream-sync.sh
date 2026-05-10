#!/bin/sh
# upstream-sync.sh - fast-forward main from upstream/zig, push origin, branch off
#
# Usage: scripts/upstream-sync.sh <topic-branch>
#
# Refuses to run with a dirty working tree.
# Refuses non-fast-forward main updates (lets git fail loudly).
# Pushes the freshly-merged main to origin.
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

echo "upstream-sync: switching to main and fast-forwarding from upstream/zig..." >&2
git switch main
git merge --ff-only upstream/zig

echo "upstream-sync: pushing origin/main..." >&2
git push origin main

if git show-ref --verify --quiet "refs/heads/$topic"; then
    echo "upstream-sync: switching to existing topic branch $topic" >&2
    git switch "$topic"
else
    echo "upstream-sync: creating topic branch $topic" >&2
    git switch -c "$topic"
fi
