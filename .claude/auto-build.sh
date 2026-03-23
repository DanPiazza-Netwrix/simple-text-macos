#!/bin/bash
# Auto-build on Swift source file edits

file=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ -z "$file" ]]; then
  echo '{}'
  exit 0
fi

# Check if it's a Swift file in Sources/SimpleText/
if echo "$file" | grep -qE 'Sources/SimpleText/.*\.swift$'; then
  cd /Users/daniel.piazza/Source/simple_text
  if ./build.sh >/dev/null 2>&1; then
    echo '{"systemMessage":"✓ App rebuilt after code change"}'
  else
    echo '{"systemMessage":"⚠ Build failed"}'
  fi
else
  echo '{}'
fi
