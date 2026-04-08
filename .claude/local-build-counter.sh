#!/bin/bash
# Appends or increments the fourth (dev) digit in build.sh VERSION.
# 1.0.0   → 1.0.0.1
# 1.0.0.7 → 1.0.0.8
set -e

REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$REPO_ROOT"

current=$(grep '^VERSION=' build.sh | head -1 | cut -d'"' -f2)

IFS='.' read -r major minor patch dev <<< "$current"

if [ -z "$dev" ]; then
    dev=1
else
    dev=$((dev + 1))
fi

next="${major}.${minor}.${patch}.${dev}"

sed -i '' "s/VERSION=\"[^\"]*\"/VERSION=\"$next\"/" build.sh
sed -i '' "s/- Current version: .*/- Current version: $next/" CLAUDE.md

echo "Local build version: $current → $next"
