#!/bin/bash
# Remind Claude to update documentation when Swift source files are modified.
# Fires after every Edit or Write. Uses `git diff HEAD` so it reflects the
# current working-tree state — including any edits that reverted changes
# (undos), which drop out of the diff automatically.

cd /Users/daniel.piazza/Source/simple_text 2>/dev/null || exit 0

# All files modified vs HEAD (staged + unstaged)
modified=$(git diff --name-only HEAD 2>/dev/null || true)

[ -z "$modified" ] && exit 0

# Any Swift sources changed?
swift_count=$(echo "$modified" | grep -cE '^Sources/SimpleText/.*\.swift$' || true)
[ "$swift_count" -eq 0 ] && exit 0

# Which doc files are still missing?
missing=""
echo "$modified" | grep -qE '^README\.md$'  || missing="README.md"
echo "$modified" | grep -qE '^CLAUDE\.md$'  || {
  [ -n "$missing" ] && missing="$missing and CLAUDE.md" || missing="CLAUDE.md"
}

[ -z "$missing" ] && exit 0

printf '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Documentation reminder: Swift source files are modified but %s has not been updated. Per CLAUDE.md rules, both README.md and CLAUDE.md must reflect every code change. Update them now if the changes are complete — or if you just reverted the Swift changes, no update is needed."
  }
}\n' "$missing"
