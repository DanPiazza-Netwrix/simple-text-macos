#!/bin/bash
# Bumps the patch version in build.sh and syncs CLAUDE.md.
# For minor or major bumps, edit build.sh VERSION manually.
set -e

REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$REPO_ROOT"

current=$(grep '^VERSION=' build.sh | cut -d'"' -f2)
IFS='.' read -r major minor patch <<< "$current"
patch=$((patch + 1))
next="${major}.${minor}.${patch}"

sed -i '' "s/VERSION=\"[^\"]*\"/VERSION=\"$next\"/" build.sh
sed -i '' "s/- Current version: .*/- Current version: $next/" CLAUDE.md

echo "Version bumped: $current → $next"
