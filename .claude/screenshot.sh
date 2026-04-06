#!/bin/bash
# Captures the SimpleText window into docs/screenshot.png.
# Must be run from the repo root with SimpleText already open.
#
# SimpleText has no AppleScript scripting dictionary, so we can't use
# `tell app "SimpleText" to id of window 1`. Instead: activate the app,
# get window geometry via System Events, then use screencapture -R.

set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Bring SimpleText to front, then wait for it to be visible
osascript -e 'tell application "SimpleText" to activate'
sleep 1

# Get window position and size via System Events
WIN=$(osascript -e '
tell application "System Events"
  tell process "SimpleText"
    tell window 1
      set p to position
      set s to size
      return "" & (item 1 of p) & "," & (item 2 of p) & "," & (item 1 of s) & "," & (item 2 of s)
    end tell
  end tell
end tell')

IFS=',' read -r X Y W H <<< "$WIN"
screencapture -R "${X},${Y},${W},${H}" docs/screenshot.png
echo "Screenshot saved to docs/screenshot.png"
