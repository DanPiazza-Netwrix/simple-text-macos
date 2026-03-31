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
- Current version: 0.0.1.69

## Architecture

Swift + AppKit, Swift Package Manager. macOS 13+. No Xcode project file.

### Key files

- `TextEngine.swift` — **no AppKit import**. Pure Swift/Foundation logic. Keep it that way — it's the portability seam for future Windows/Linux builds.
- `RecoveryBuffer.swift` — manages `~/Library/Application Support/SimpleText/session.json`. Saves a full multi-tab session (all tab content + selected index) on every keystroke and state change, loads on app startup, clears when user triggers "Clear Unsaved Buffer". Legacy single-tab `unsaved_buffer.txt` is migrated automatically on first run.
- `AppearanceManager.swift` — sets `window.appearance` to force dark/light. All colors elsewhere must be semantic `NSColor` values so they auto-adapt.
- `LineNumberRulerView.swift` — Plain `NSView` subclass (NOT `NSRulerView`). Positioned as a sibling to the scroll view inside `EditorView`, avoiding all `NSScrollView` ruler machinery (separator lines, dividers). `isFlipped = true` so coordinate math works the same as scroll view content. Uses `NSLayoutManager.enumerateLineFragments` to position numbers. Coordinate math: `rulerY = fragmentRect.midY + textContainerOrigin.y - clipView.bounds.origin.y`. Width is managed via an `NSLayoutConstraint` that is updated dynamically as line count grows.
- `TabController.swift` — `NSViewController` managing multiple `EditorViewController` instances. Owns a `TabBarView` at top (anchored to `safeAreaLayoutGuide.topAnchor`) and an `editorContainer` below it. Handles tab switching, closing, and opening files without losing the current tab. Wires `onFilesDropped` on each `EditorViewController` so file-URL drops anywhere in the window open a new tab via `openFileInTab(at:)`. `confirmAndClose(vc:closeAction:)` shows a Save/Don't Save/Cancel sheet before closing any tab whose `documentController.currentURL != nil && isModified`; untitled buffers close silently. Closing the last tab calls `replaceLastTabWithBlank()` — the window stays open with a fresh blank tab rather than hiding.
- `TabBarView.swift` — Custom `NSView` tab bar. Chrome-style tab sizing (fills available width, clamped to min/max). Active tabs get a rounded-rect pill background; inactive tabs are transparent. Contains `TabButton` inner class. `TabButton` overrides `menu(for:)` to show a right-click context menu ("Close Tabs to the Right", "Close Other Tabs"); uses `autoenablesItems = false` so items gray out correctly when not applicable (rightmost tab / only tab). No `+` button — new tabs are opened via Cmd+T. **Drag-to-reorder**: `TabButton` detects drag threshold (>4 px) in `mouseDragged`/`mouseUp` and fires `onDragStarted`/`onDragged`/`onDragEnded` callbacks; `TabBarView` moves the dragged button in real-time, slides other tabs into place with a 0.12 s animation, then calls `tabBar(_:didMoveTabFrom:to:)` on the delegate. `wantsLayer = true` on each button enables Core Animation for smooth sliding.
- `SyntaxHighlighter.swift` — `NSTextStorageDelegate` implementation for Markdown syntax highlighting. Uses VS Code Dark+/Light+ dynamic colors via `NSColor(name:dynamicProvider:)`. Pre-compiled static regex patterns. Activated only for `.md`/`.markdown` files. Uses **`NSLayoutManager` temporary attributes** (`addTemporaryAttributes`) instead of `NSTextStorage.addAttributes` — temporary attributes are purely visual overlays that are never tracked by the undo manager and never saved to file. Fires in `didProcessEditing` (not `willProcessEditing`). Wired in `EditorViewController.documentDidLoad`.
- `DocumentController.swift` — file I/O (open, save, new). `restore(content:url:)` sets `isModified = true` after the delegate call so restored tabs are immediately saveable without requiring edits. Uses `NSApp.keyWindow ?? NSApp.mainWindow` to find the window for panels.
- `EditorViewController.swift` — central coordinator; owns `DocumentController`, `AppearanceManager`, `EditorView`. All `@objc` menu actions wired via responder chain (`target: nil` in `AppDelegate.buildMainMenu`). Exposes `onFilesDropped: (([URL]) -> Void)?` callback forwarded from `EditorView` up to `TabController`. Owns a per-tab `tabUndoManager: UndoManager` (returned by `WindowController.windowWillReturnUndoManager`). Conforms to `NSTextViewDelegate` and calls `textView.breakUndoCoalescing()` at word-boundary characters (space, newline, punctuation) to achieve word-granularity undo.
- `WindowController.swift` — window creation, appearance override, background mode, and frame autosaving. Closes window but keeps app running (`windowShouldClose` returns false, calls `orderOut`). Saves and restores window position/size via `setFrameAutosaveName`. Implements `windowWillReturnUndoManager(_:)` to return the active tab's per-tab `UndoManager`, giving each tab an isolated undo stack.
- `AppDelegate.swift` — app lifecycle and programmatic menu construction. `applicationShouldHandleReopen(_:hasVisibleWindows:)` re-shows the window when the Dock icon is clicked while all windows are hidden. `applicationShouldTerminate(_:)` checks all tabs for unsaved file changes on Cmd+Q and shows a Save All/Don't Save/Cancel alert before quitting.

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

## Undo architecture

Each tab has its own isolated undo stack:

- `EditorViewController` owns a `let tabUndoManager = UndoManager()` instance.
- `WindowController` implements `windowWillReturnUndoManager(_:) -> UndoManager?` returning `tabController.activeEditorVC?.tabUndoManager`. This intercepts the window-level undo lookup that `NSTextView` uses for both **registering** and **executing** undo — so both go to the active tab's manager.
- When switching tabs, the window's undo manager automatically becomes the new tab's manager.
- `tabUndoManager.removeAllActions()` is called in `documentDidLoad` to clear history when a new file loads.
- Word-boundary granularity: `EditorViewController` conforms to `NSTextViewDelegate` and calls `textView.breakUndoCoalescing()` whenever a space, newline, or punctuation character is about to be inserted. This seals the previous word as its own undo step, matching TextEdit/VS Code behavior.
- Syntax highlighting uses `NSLayoutManager` temporary attributes — these are never tracked by the undo manager, so highlighting changes are never undo-able.

**Do NOT** try to manage undo grouping manually via `beginUndoGrouping`/`endUndoGrouping` — with `groupsByEvent = true` (default), calling `endUndoGrouping` when no group is open throws `NSInternalInconsistencyException`.

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

- Session is saved as JSON to `~/Library/Application Support/SimpleText/session.json`
- Captures **all open tabs**: each tab's URL (if saved) and/or content (if unsaved or modified)
- Saves after every keystroke, state change, and tab close/open
- Persists between app launches — no save prompt on quit
- On launch, all tabs are restored with the same selected tab as when the app was last used
- Saved+unmodified tabs are restored by reopening their file from disk (content not duplicated in JSON)
- Tabs whose file no longer exists on disk are silently skipped on restore (not shown as errors)
- Unsaved or modified tabs have their full text content stored in the session; restored as modified so Cmd+S works immediately without requiring edits
- If all session tabs are skipped, a single blank tab is opened as a fallback
- User can manually clear via Edit → "Clear Unsaved Buffer"
- Legacy single-tab `unsaved_buffer.txt` is auto-migrated to the new format on first run

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
