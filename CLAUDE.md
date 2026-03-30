# SimpleText — Developer Notes for Claude

## Font

Default font is **Monaco 12pt** (same as TextEdit), with fallback to Menlo 13pt if Monaco is not available.

## Build & Run

```bash
swift run                        # development run
./build.sh                       # produces build/SimpleText.app
swift build -c release           # release binary only
```

Always build with `./build.sh` when the user asks to test or verify — this produces the proper `.app` bundle.

**IMPORTANT:** Any time you make changes to the app code, you MUST update both `README.md` and this `CLAUDE.md` file to reflect those changes. Do not skip this step. Keep documentation in sync with implementation.

**IMPORTANT:** NEVER run `git commit` or `git push` (or any destructive git operation) without explicit user confirmation first. Always show the user what you plan to commit/push and wait for approval. A prior "commit and push" in one message does NOT grant standing permission for future operations.

**Version bumping:** Use semantic versioning with a fourth digit for dev builds: `MAJOR.MINOR.PATCH.DEV`
- Each rebuild **automatically** increments the DEV digit via `.claude/bump-version.sh` (PreToolUse hook on `./build.sh`)
- Only the user changes MAJOR/MINOR/PATCH
- If unsure about what version to build, ask the user first
- Version is kept in sync across: `WindowController.swift` (initial window title), `TabController.swift` (runtime window title via `syncWindow()`), `build.sh` (VERSION variable)
- Always report the built version in output so user can confirm in Claude Code
- Current version: 0.0.1.44

## Architecture

Swift + AppKit, Swift Package Manager. macOS 13+. No Xcode project file.

### Key files

- `TextEngine.swift` — **no AppKit import**. Pure Swift/Foundation logic. Keep it that way — it's the portability seam for future Windows/Linux builds.
- `RecoveryBuffer.swift` — manages `~/Library/Application Support/SimpleText/unsaved_buffer.txt`. Saves on every keystroke, loads on app startup, clears on file save or new document.
- `AppearanceManager.swift` — sets `window.appearance` to force dark/light. All colors elsewhere must be semantic `NSColor` values so they auto-adapt.
- `LineNumberRulerView.swift` — Plain `NSView` subclass (NOT `NSRulerView`). Positioned as a sibling to the scroll view inside `EditorView`, avoiding all `NSScrollView` ruler machinery (separator lines, dividers). `isFlipped = true` so coordinate math works the same as scroll view content. Uses `NSLayoutManager.enumerateLineFragments` to position numbers. Coordinate math: `rulerY = fragmentRect.midY + textContainerOrigin.y - clipView.bounds.origin.y`. Width is managed via an `NSLayoutConstraint` that is updated dynamically as line count grows.
- `TabController.swift` — `NSViewController` managing multiple `EditorViewController` instances. Owns a `TabBarView` at top (anchored to `safeAreaLayoutGuide.topAnchor`) and an `editorContainer` below it. Handles tab switching, closing, and opening files without losing the current tab. Wires `onFilesDropped` on each `EditorViewController` so file-URL drops anywhere in the window open a new tab via `openFileInTab(at:)`.
- `TabBarView.swift` — Custom `NSView` tab bar. Chrome-style tab sizing (fills available width, clamped to min/max). Active tabs get a rounded-rect pill background; inactive tabs are transparent. Contains `TabButton` and `AddTabButton` inner classes.
- `FindBarCoordinator.swift` — thin wrapper activating AppKit's native find bar on the text view.
- `DocumentController.swift` — file I/O (open, save, new). Integrates with recovery buffer instead of prompting for unsaved changes.
- `EditorViewController.swift` — central coordinator; owns `DocumentController`, `AppearanceManager`, `EditorView`. Loads recovery buffer on `viewDidLoad`. All `@objc` menu actions wired via responder chain (`target: nil` in `AppDelegate.buildMainMenu`). Exposes `onFilesDropped: (([URL]) -> Void)?` callback forwarded from `EditorView` up to `TabController`.
- `WindowController.swift` — window creation, appearance override, background mode, and frame autosaving. Closes window but keeps app running (`windowShouldClose` returns false, calls `orderOut`). Saves and restores window position/size via `setFrameAutosaveName`.

## Color rules

- `textView.textColor = .labelColor` — semantic, adapts to light/dark mode (black in light, white in dark)
- `textView.insertionPointColor = .labelColor` — semantic, matches text color
- `textView.backgroundColor = .textBackgroundColor` — semantic, adapts to appearance
- Line number color: `NSColor.secondaryLabelColor` — adapts to appearance
- Line number gutter background: `NSColor.textBackgroundColor` — matches the editor background
- **Never add hardcoded `NSColor(red:green:blue:)` values** — always use semantic colors for proper light/dark mode support

## Drag-and-drop file opening

Files dragged onto the app window open in a new tab. Implementation notes:
- `EditorView` uses a private `EditorTextView: NSTextView` subclass that overrides `draggingEntered`, `draggingUpdated`, and `performDragOperation`. Without this, `NSTextView` intercepts file-URL drags and inserts the file path as text instead of opening the file.
- The callback chain is: `EditorTextView.onFilesDropped` → `EditorView.onFilesDropped` → `EditorViewController.onFilesDropped` → `TabController.openFileInTab(at:)`
- Do NOT rely on `NSTextView`'s default drag handling for file URLs — it always inserts the path as text.

## Find bar

Uses the **native AppKit find bar** (`textView.usesFindBar = true`). Do not replace with a custom find UI — the native bar gives Next/Prev/case-sensitive/match-count for free.

## Undo for text replacements

Any bulk text replacement (e.g., Remove Blank Lines) must go through:

```swift
textView.insertText(newContent, replacementRange: NSRange(location: 0, length: nsLength))
textView.undoManager?.setActionName("Action Name")
```

Never assign to `textView.string` directly — it bypasses the undo stack.

## Adding menu items

Add items in `AppDelegate.buildMainMenu()`. Use `target: nil` so AppKit dispatches via the responder chain. Add the corresponding `@objc` handler on `EditorViewController`.

## Recovery buffer behavior

- Auto-saves to `~/Library/Application Support/SimpleText/unsaved_buffer.txt` after every keystroke
- Persists between app launches (no save prompt on quit)
- Cleared when: user saves a file, creates new document, or opens a file
- User can manually clear via Edit → "Clear Unsaved Buffer"
- On app launch, if buffer exists and is non-empty, it's automatically loaded

## Background mode

- Closing the window (clicking X) hides the app instead of quitting
- App stays in Dock and continues running
- `applicationShouldTerminateAfterLastWindowClosed` returns `false`
- `WindowController.windowShouldClose` returns `false` and calls `orderOut` instead of closing

## Window position and size memory

- Uses AppKit's `setFrameAutosaveName("SimpleTextMain")` to auto-save window frame to UserDefaults
- Window position and size are saved automatically when moved/resized
- Restoration uses `setFrameUsingName(_:)` which returns true if successful, false if first launch
- On first launch, window centers; on subsequent launches, restores to saved position/size
- Stored in UserDefaults under key `"NSWindow Frame SimpleTextMain"`

## Future cross-platform work

When porting to Windows/Linux:
1. Keep `TextEngine.swift` as-is
2. Keep `RecoveryBuffer.swift` logic but change the storage path (`~/AppData/Local/SimpleText` on Windows, `~/.config/simpletext` on Linux)
3. Replace the AppKit UI layer (`EditorView`, `LineNumberRulerView`, `WindowController`, `AppearanceManager`) with platform-native equivalents
4. `DocumentController` is mostly portable — only `NSOpenPanel`/`NSSavePanel` need replacing
