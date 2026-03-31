---
description: Full maintenance pass — sync docs, remove dead code, clean up, verify build
allowed-tools: [Read, Edit, Write, Glob, Grep, Bash]
---

# SimpleText Maintenance

Perform a thorough maintenance pass on the SimpleText project. Work through each step completely before moving on.

## Steps

### 1. Verify documentation sync
- Read every `.swift` source file in `Sources/SimpleText/`
- Read `README.md` and `CLAUDE.md`
- Identify anything in the code that is **not reflected** in the docs (new behavior, changed APIs, removed features)
- Identify anything in the docs that is **no longer true** in the code (stale descriptions, wrong file names, outdated behavior)
- Make targeted edits to `README.md` and `CLAUDE.md` to bring them in sync — do not rewrite sections that are already accurate

### 2. Check version sync
- Read `build.sh` for the VERSION variable
- Read `WindowController.swift` for the initial window title string
- Read `TabController.swift` for the `syncWindow()` title string
- If any are out of sync, fix them

### 3. Dead code and unused symbols
- Search for functions, properties, or types that are defined but never called or referenced
- Check for `private` helpers that are only referenced from one place and could be inlined if trivially simple
- Remove or inline anything genuinely unused — do not remove code that is called indirectly via `@objc` selectors or protocol conformances

### 4. Code clarity
- Look for obvious complexity that can be reduced without changing behavior
- Consolidate duplicated logic if the same pattern appears 3+ times
- Do not add abstractions for things that only appear once or twice

### 5. Build verification
- Run `./build.sh` and confirm it compiles cleanly
- Report the version number from the build output

### 6. Summary
Report what was changed and what was checked and found to be already clean.
