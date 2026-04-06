#!/bin/bash
set -e

REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Extract current version from build.sh
current=$(grep '^VERSION=' build.sh | cut -d'"' -f2)

# Parse version parts
IFS='.' read -r major minor patch dev <<< "$current"

# Increment dev number
if [ -z "$dev" ]; then
  dev=1
else
  dev=$((dev + 1))
fi

next="${major}.${minor}.${patch}.${dev}"

# Update all files
sed -i '' "s/VERSION=\"[^\"]*\"/VERSION=\"$next\"/" build.sh
sed -i '' "s/- Current version: ${major}\.${minor}\.${patch}\.[0-9]*/- Current version: $next/" CLAUDE.md

echo "{\"systemMessage\":\"✓ Version bumped: $current → $next\"}"
