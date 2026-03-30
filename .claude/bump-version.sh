#!/bin/bash
set -e

PROJECT_DIR="/Users/daniel.piazza/Source/simple_text"
cd "$PROJECT_DIR"

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
sed -i '' "s/v${major}\.${minor}\.${patch}\.[0-9]*/v$next/" Sources/SimpleText/WindowController.swift
sed -i '' "s/v${major}\.${minor}\.${patch}\.[0-9]*/v$next/" Sources/SimpleText/TabController.swift
sed -i '' "s/- Current version: ${major}\.${minor}\.${patch}\.[0-9]*/- Current version: $next/" CLAUDE.md

echo "{\"systemMessage\":\"✓ Version bumped: $current → $next\"}"
