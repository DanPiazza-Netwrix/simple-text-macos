#!/bin/bash
# Captures the SimpleText window into docs/screenshot.png.
# Must be run from the repo root with SimpleText already open.
#
# Uses `screencapture -l <CGWindowID>` which composites the window correctly,
# preserving rounded corners and the drop shadow. The CGWindowID is obtained
# via Python/Quartz since SimpleText has no AppleScript scripting dictionary.

set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Bring SimpleText to front, then wait for it to be visible
osascript -e 'tell application "SimpleText" to activate'
sleep 1

# Get the CGWindowID via Quartz — works for any app regardless of AppleScript support
WIN_ID=$(python3 -c "
import Quartz
wins = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
for w in wins:
    if w.get('kCGWindowOwnerName') == 'SimpleText' and w.get('kCGWindowLayer') == 0:
        print(w['kCGWindowNumber'])
        break
")

if [ -z "$WIN_ID" ]; then
  echo "ERROR: SimpleText window not found — is the app running and visible?" >&2
  exit 1
fi

screencapture -l "$WIN_ID" docs/screenshot.png
echo "Screenshot saved to docs/screenshot.png"
