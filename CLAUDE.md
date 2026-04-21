# SimpleText — Developer Notes for Claude

## Font

Default font is **Monaco** (same as TextEdit), with fallback to Menlo, then system monospaced. Font size is persisted in `UserDefaults` under key `"fontSize"` (default 12pt) and read on startup by `EditorView.setupTextView()`. Zoom actions (`zoomIn`, `zoomOut`, `resetZoom`) live on `EditorViewController` and update `textView.font` directly.

## Taking the README screenshot

Use the `/screenshot` slash command, or run manually:

```bash
bash .claude/screenshot.sh
```

The script and the reasoning behind it are in `.claude/screenshot.sh`.

## Testing approach

**Do NOT interactively test the app by opening it, taking screenshots, and simulating user actions.** Instead:
- Verify changes by code review and `./build.sh` success
- Only open the app and take screenshots when the user explicitly asks for it
- Only use interactive "driving" of the application when explicitly requested or when using MCPs
- This keeps iteration fast and focused on correctness

## Build & Run

```bash
swift run                        # development run
./build.sh                       # produces build/SimpleText.app
swift build -c release           # release binary only
```

Always build with `./build.sh` when the user asks to test or verify — this produces the proper `.app` bundle.

**IMPORTANT:** Any time you make changes to the app code, you MUST update both `README.md` and this `CLAUDE.md` file to reflect those changes. Do not skip this step. Keep documentation in sync with implementation.

**IMPORTANT:** NEVER run `git commit` or `git push` (or any destructive git operation) without explicit user confirmation first. Always show the user what you plan to commit/push and wait for approval. A prior "commit and push" in one message does NOT grant standing permission for future operations.

**Version scheme — hybrid local/release:**
- **Local builds:** `MAJOR.MINOR.PATCH.DEV` (e.g. `1.0.0.4`). The fourth digit is auto-incremented by `.claude/local-build-counter.sh` which is called at the top of `build.sh` on every invocation. This lets you see exactly which local iteration is running.
- **GitHub releases:** Clean `MAJOR.MINOR.PATCH` (e.g. `1.0.1`). Use the `/release` slash command to strip the dev digit, choose the target semver, build, tag, and publish.
- Version is kept in sync across: `build.sh` (VERSION variable), `CLAUDE.md` (this file). The status bar reads version at runtime from `Bundle.main` (`CFBundleShortVersionString`) — no Swift files need updating.
- To manually bump just the patch (without releasing): `bash .claude/bump-version.sh`
- To release to GitHub: `/release`
- Always report the built version in output so user can confirm in Claude Code
- Current version: 1.1.0.131

## Architecture

Swift + AppKit, Swift Package Manager. macOS 13+. No Xcode project file.

**Ownership chain:** `AppDelegate` → `WindowController` → `SplitController` → `[TabController]` → `[EditorViewController]` → `EditorView`

### Key files

- `TextEngine.swift` — **no AppKit import**. Pure Swift/Foundation logic. Keep it that way — it's the portability seam for future Windows/Linux builds.
- `SplitController.swift` — `NSSplitViewController` managing unlimited `TabController` panes in a vertical (left/right) split. Owns `panes: [TabController]` (can be 1 or more) and `activePaneIndex`. Handles split/unsplit/moveTab actions (`splitPane`, `unsplitPane`, `moveTabToOtherPane`). Forwards `newTab`/`closeTab`/`closeAllTabs` to the active pane. Aggregates all panes into a single `RecoverySession` snapshot. Cross-pane tab transfer via `moveTab(from:at:to:at:)`. Distributes pane widths evenly when splitting. Divider positions are auto-saved to UserDefaults via `autosaveName` so user drags persist across sessions. Session loading and initial tab restoration happen here (moved from TabController).
- `RecoveryBuffer.swift` — manages `~/Library/Application Support/SimpleText/session.json`. Saves a pane-aware multi-tab session (`[PaneRecoveryEntry]` + `activePaneIndex`) on every keystroke and state change, loads on app startup, clears when user triggers "Clear Unsaved Buffer". Migrates both legacy single-tab `unsaved_buffer.txt` and pre-split-view flat `{tabs, selectedIndex}` formats automatically on first run. Save failures are logged via `OSLog` (subsystem `com.simpletext.app`, category `RecoveryBuffer`) rather than `print()`.
- `AppearanceManager.swift` — sets `window.appearance` to force dark/light. Mode is persisted to `UserDefaults` under key `"appearanceMode"` (`"dark"` / `"light"` / `"system"`; defaults to dark on first launch). All colors elsewhere must be semantic `NSColor` values so they auto-adapt.
- `LineNumberRulerView.swift` — Plain `NSView` subclass (NOT `NSRulerView`). Positioned as a sibling to the scroll view inside `EditorView`, avoiding all `NSScrollView` ruler machinery (separator lines, dividers). `isFlipped = true` so coordinate math works the same as scroll view content. Uses `NSLayoutManager.enumerateLineFragments` to position numbers. Coordinate math: `rulerY = fragmentRect.midY + textContainerOrigin.y - clipView.bounds.origin.y`. Width is managed via an `NSLayoutConstraint` that is updated dynamically as line count grows.
- `StatusBarView` (defined in `EditorView.swift`) — thin 22pt bar anchored to the bottom of `EditorView`, above which both the ruler and scroll view terminate. Contains an `NSBox` separator at its top edge, a left-aligned `versionLabel` (populated from `Bundle.main` `CFBundleShortVersionString` at init), and a right-aligned `label` for cursor stats. Updated via `EditorView.updateStatus(line:col:words:chars:)`. Uses semantic colors (`secondaryLabelColor`) so it adapts to dark/light mode automatically.
- `TabController.swift` — `NSViewController` representing a single pane in the split view. Manages multiple `EditorViewController` instances. Owns a `TabBarView` at top and an `editorContainer` below it. Handles tab switching, closing, and opening files. Callbacks for parent coordination: `onBecameActive` (pane focus), `onRecoveryNeeded` (session save), `onLastTabClosed` (auto-unsplit), `onRequestMoveToOtherPane` / `onReceiveCrossPaneDrop` (cross-pane tab transfer). Exposes `removeTab(at:)` and `insertTab(_:at:)` for cross-pane moves. `restoreTabs(from:selectedIndex:)` loads tabs from recovery entries (called by SplitController). `buildRecoveryEntries()` returns the pane's current `PaneRecoveryEntry`. Closing the last tab in a secondary pane fires `onLastTabClosed`; in the only pane, replaces with a blank tab. Observes `simpleTextEditorDidBecomeActive` notification to detect when its text views gain focus.
- `TabBarView.swift` — Custom `NSView` tab bar. Chrome-style tab sizing (fills available width, clamped to min/max). Active tabs get a rounded-rect pill background; inactive tabs are transparent. Contains `TabButton` inner class. `TabButton` overrides `menu(for:)` to show a right-click context menu ("Close Tabs to the Right", "Close Other Tabs", "Close All Tabs", and "Move to Other Pane" when split is active); uses `autoenablesItems = false` so items gray out correctly. No `+` button — new tabs are opened via Cmd+T. **Drag-to-reorder**: `TabButton` detects drag threshold (>4 px) in `mouseDragged`/`mouseUp` and fires `onDragStarted`/`onDragged`/`onDragEnded` callbacks; `TabBarView` moves the dragged button in real-time, slides other tabs into place with a 0.12 s animation, then calls `tabBar(_:didMoveTabFrom:to:)` on the delegate. **Cross-pane drag**: when a drag leaves the tab bar bounds, `TabButton` starts an `NSDraggingSession` with a `TabDragInfo` payload (custom `com.simpletext.tab-drag` pasteboard type). `TabBarView` is an `NSDraggingDestination` that accepts drops from other panes, showing a drop indicator line. `isActivePane` property draws a 2px accent line at top of the active pane's tab bar. `isSplitActive` controls whether the "Move to Other Pane" context menu item appears.
- `SyntaxHighlighter.swift` — `NSTextStorageDelegate` implementation for **Markdown-only** syntax highlighting. Uses VS Code Dark+/Light+ dynamic colors via `NSColor(name:dynamicProvider:)`. Pre-compiled static regex patterns. Activated only for `.md`/`.markdown` files. Uses **`NSLayoutManager` temporary attributes** (`addTemporaryAttributes`) instead of `NSTextStorage.addAttributes` — temporary attributes are purely visual overlays that are never tracked by the undo manager and never saved to file. Fires in `didProcessEditing` (not `willProcessEditing`). Wired in `EditorViewController.documentDidLoad`. Kept separate from Tree-sitter because the Markdown grammar has a complex block+inline architecture that would require embedded language setup.
- `HighlightTheme.swift` — Maps tree-sitter capture names (e.g. `"keyword"`, `"string"`, `"comment"`) to VS Code Dark+/Light+ colors using the same `vscodeColor(dark:light:)` helper pattern. Uses prefix matching so sub-scopes like `"keyword.control"` correctly resolve to the `"keyword"` color. Called directly by `HighlightCoordinator`'s `attributeProvider` closure via `highlightAttributes(for: token.name)`.
- `LanguageRegistry.swift` — Singleton that maps file extensions to `LanguageConfiguration` objects (from `SwiftTreeSitter`). Configurations are created lazily on first use and cached. Supports: Swift, Python, JavaScript, TypeScript/TSX, JSON, HTML, CSS, Bash/sh, Go, Rust, Java, Ruby, YAML, PowerShell (`.ps1`/`.psm1`/`.psd1`). Returns `nil` for unrecognized extensions (plain text, no highlighting). Grammar packages that had broken `FileManager.fileExists` SPM manifests (Python, JavaScript, CSS, YAML, PowerShell) are vendored in `Sources/Grammars/` with fixed source lists.
- `HighlightCoordinator.swift` — `@MainActor` class wrapping Neon's `TextViewHighlighter`. Created by `EditorViewController.documentDidLoad` when `LanguageRegistry` returns a config for the opened file. Sets itself as `NSTextStorage` delegate (via Neon internals) and drives incremental Tree-sitter re-highlighting. Call `observeScrollView()` after creation to enable visible-range optimization.
- `DocumentController.swift` — file I/O (open, save, new). `restore(content:url:)` sets `isModified = true` after the delegate call so restored tabs are immediately saveable without requiring edits. `saveDocumentAs(completion:)` accepts an optional `completion: (() -> Void)?` that is called only after a successful write — used by `TabController.confirmAndClose` to close the tab only when the save actually completed. `savedContent: String?` stores the file content at the last disk load or save; `nil` for new/restored docs. `EditorViewController.handleTextDidChange` compares current text against `savedContent` to automatically clear `isModified` when the user undoes all changes back to the saved state. Uses `NSApp.keyWindow ?? NSApp.mainWindow` to find the window for panels.
- `EditorViewController.swift` — central coordinator; owns `DocumentController`, `AppearanceManager`, `EditorView`. All `@objc` menu actions wired via responder chain (`target: nil` in `AppDelegate.buildMainMenu`). Exposes `onFilesDropped: (([URL]) -> Void)?` callback forwarded from `EditorView` up to `TabController`. Owns a per-tab `tabUndoManager: UndoManager` (returned by `WindowController.windowWillReturnUndoManager`). Conforms to `NSTextViewDelegate` and calls `textView.breakUndoCoalescing()` at word-boundary characters (space, newline, punctuation) to achieve word-granularity undo. Uses `applyHighlighting(for:)` to pick between `SyntaxHighlighter` (Markdown) and `HighlightCoordinator` (everything else via `LanguageRegistry`); called from both `documentDidLoad` and `documentDidSave` so that saving an untitled buffer under a new name (e.g. `test.ps1`) activates highlighting immediately without requiring a reload. Font zoom actions (`zoomIn`, `zoomOut`, `resetZoom`) update `textView.font` and persist size to `UserDefaults`. `updateStatusBar()` is called from `selectionDidChange`, `handleTextDidChange`, and `documentDidLoad` to keep the status bar current.
- `WindowController.swift` — window creation, appearance override, background mode, and frame autosaving. Owns `SplitController` (set as `contentViewController`). Closes window but keeps app running (`windowShouldClose` returns false, calls `orderOut`). Saves and restores window position/size via `setFrameAutosaveName`. Implements `windowWillReturnUndoManager(_:)` to return the active pane's active tab's per-tab `UndoManager` via `splitController.activeEditorVC?.tabUndoManager`.
- `AppDelegate.swift` — app lifecycle and programmatic menu construction. `applicationShouldHandleReopen(_:hasVisibleWindows:)` re-shows the window when the Dock icon is clicked while all windows are hidden. `applicationShouldTerminate(_:)` checks all tabs across all panes (`splitController.allEditorVCs`) for unsaved file changes on Cmd+Q and shows a Save All/Don't Save/Cancel alert before quitting. File menu routes New/Close Tab/Close All through `SplitController` (which forwards to active pane). View menu includes Zoom In/Out/Reset (Cmd+= / Cmd+- / Cmd+0), Split Editor (Cmd+\\), Unsplit Editor, and Move Tab to Other Pane.

## Color rules

- `textView.textColor = .labelColor` — semantic, adapts to light/dark mode (black in light, white in dark)
- `textView.insertionPointColor = .labelColor` — semantic, matches text color
- `textView.backgroundColor = .textBackgroundColor` — semantic, adapts to appearance
- Line number color: `NSColor.secondaryLabelColor` — adapts to appearance
- Line number gutter background: `NSColor.textBackgroundColor` — matches the editor background
- **Never add hardcoded `NSColor(red:green:blue:)` values** — always use semantic colors for proper light/dark mode support

## Syntax highlighting architecture

Two highlighting paths coexist — at most one is active per tab:

1. **Markdown** (`SyntaxHighlighter`) — regex-based, handles bold/italic/links/code inline correctly. Kept separate because the tree-sitter-markdown grammar needs complex block+inline embedded-language setup.
2. **Everything else** (`HighlightCoordinator` + Neon + Tree-sitter) — incremental structural parsing. Uses `TextViewHighlighter` from [Neon (ChimeHQ)](https://github.com/ChimeHQ/Neon) which internally sets `NSTextStorage.delegate` and applies `NSLayoutManager` temporary attributes.

**Adding a new language:**
1. Add the SPM grammar package to `Package.swift` (verify its `Package.swift` hardcodes `scanner.c`; if not, vendor in `Sources/Grammars/<Lang>/`).
2. Import the module in `LanguageRegistry.swift` and add the extension→name mapping + `LanguageConfiguration` init.
3. Add the file extension to `CFBundleDocumentTypes` in `build.sh`.

**Vendored grammars** (`Sources/Grammars/`): Python, JavaScript, CSS, YAML, PowerShell (`airbus-cert/tree-sitter-powershell` v0.26.3). Their upstream SPM packages use a `FileManager.fileExists` check for `scanner.c` that fails during SPM manifest evaluation, causing linker errors. The vendored copies include all C sources, headers, and query files copied from the resolved package checkouts.

**Grammar packages not yet supported** due to broken SPM manifests: C (`tree-sitter-c`), C++ (`tree-sitter-cpp`). Both use `tree-sitter/swift-tree-sitter` without `name:` alias, causing `unknown dependency 'SwiftTreeSitter'` at resolution time. Fixable by vendoring their sources the same way.

**`LanguageConfiguration` bundle resolution**: Neon looks for `TreeSitter<Name>_TreeSitter<Name>.bundle` in the app bundle's `Resources/` to load `.scm` query files. `build.sh` copies all `.bundle` dirs from `.build/release/` into `Contents/Resources/` using `find -L` (the `-L` flag is required because `.build/release` is a symlink to `arm64-apple-macosx/release`).

Two grammars don't follow the `TreeSitter<Name>_TreeSitter<Name>` naming convention and need an explicit `bundleName:` parameter in `LanguageRegistry.swift`:
- **TSX**: bundle is `TreeSitterTypeScript_TreeSitterTSX` (lives in the typescript package, not its own)
- **PowerShell**: bundle is `SimpleText_TreeSitterPowershell` (vendored target owned by the SimpleText package)

## Drag-and-drop file opening

Files dragged onto the app window open in a new tab. Implementation notes:
- `EditorView` uses a private `EditorTextView: NSTextView` subclass that overrides `draggingEntered`, `draggingUpdated`, and `performDragOperation`. Without this, `NSTextView` intercepts file-URL drags and inserts the file path as text instead of opening the file. `EditorTextView` also overrides `keyDown` to handle bulk indent/dedent: Tab with a multi-line selection prepends `\t` to every selected line; Shift+Tab strips one leading tab (or up to 4 leading spaces) from every line in the selection (or current line if no selection). Both operations go through `insertText(_:replacementRange:)` for proper undo support.
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
- Pane-aware format: `RecoverySession { panes: [PaneRecoveryEntry], activePaneIndex }` where each `PaneRecoveryEntry` has `tabs: [TabRecoveryEntry]` and `selectedIndex`
- Captures **all open tabs across all panes**: each tab's URL (if saved) and/or content (if unsaved or modified)
- Saves after every keystroke, state change, and tab close/open — SplitController aggregates all panes
- Persists between app launches — no save prompt on quit
- On launch, all panes and their tabs are restored with the same selected tab and active pane as when the app was last used
- Saved+unmodified tabs are restored by reopening their file from disk (content not duplicated in JSON)
- Tabs whose file no longer exists on disk are silently skipped on restore (not shown as errors)
- Unsaved or modified tabs have their full text content stored in the session; restored as modified so Cmd+S works immediately without requiring edits
- If all session tabs are skipped, a single blank tab is opened as a fallback
- User can manually clear via Edit → "Clear Unsaved Buffer"
- Migrates both legacy single-tab `unsaved_buffer.txt` and pre-split-view flat `{tabs, selectedIndex}` formats automatically on first run

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

## Split view

The editor supports splitting the window into two side-by-side panes, each with its own tab bar and set of tabs.

**Architecture:** `SplitController` (subclass of `NSSplitViewController`) sits between `WindowController` and `TabController`. Each `TabController` is a self-contained pane with its own tab bar, editor container, and tab array. The split view uses `NSSplitViewItem` with a thin vertical divider.

**Key behaviors:**
- Right-click in editor → "Split View Vertically" creates another pane with a blank tab; grayed out when a split is already active
- Right-click in editor → "Merge Views" closes the current pane and moves its tabs to the other pane; grayed out when only one pane exists
- The active pane is indicated by a 2px accent line at the top of its tab bar
- Version number displays only in the leftmost pane's status bar (all panes show line/column/word/char stats on the right)
- Focus tracking: `EditorTextView.becomeFirstResponder` posts a notification; `TabController` observes it and fires `onBecameActive`; `SplitController` updates `activePaneIndex`
- Menu actions (New Tab, Close Tab, Save, etc.) route through the active pane via `SplitController`

**View menu (Split section):**
- "Split Editor" (Cmd+\\) — same as right-click "Split View Vertically"
- "Merge Views" — same as right-click "Merge Views"; combines both panes' tabs into one
- "Move Tab to Other Pane" — moves the active tab from the current pane to the other pane

**Cross-pane tab transfer:**
- Right-click tab context menu: "Move to New View" (when unsplit) or "Move to Other Pane" (when split) — label is context-aware via `isSplitActive`
- View menu: "Move Tab to Other Pane"
- Drag-and-drop: dragging a tab outside its tab bar starts an `NSDraggingSession` with a `TabDragInfo` payload (`com.simpletext.tab-drag` pasteboard type). The destination pane's `TabBarView` accepts the drop and shows a drop indicator line.
- Moving the last tab out of a pane triggers auto-unsplit

**Editor context menu:**
- `EditorTextView.menu(for:)` intercepts right-clicks and fires `onContextMenu` callback. `EditorView` forwards to `EditorViewController.onEditorContextMenu`. `TabController.buildContextMenuItems(_:)` appends "Split View Vertically" and "Merge Views" after the standard text editing menu items.
- Enabled state is controlled by `validateMenuItem(_:)` on `TabController` (not `isEnabled` directly, which AppKit overrides via `autoenablesItems`). "Split View Vertically" is disabled when `canClosePaneCallback` returns true; "Merge Views" is disabled when it returns false.

**Edge cases:**
- Closing the last tab in any pane (when multiple panes exist) automatically closes that pane and unsplits if only 1 pane remains
- Closing the last tab in the only pane opens a fresh blank tab (window stays open)
- Cmd+Q checks all tabs across all panes for unsaved changes
- Session recovery persists all panes, their tabs, and the active pane index

## Future cross-platform work

When porting to Windows/Linux:
1. Keep `TextEngine.swift` as-is
2. Keep `RecoveryBuffer.swift` logic but change the storage path (`~/AppData/Local/SimpleText` on Windows, `~/.config/simpletext` on Linux)
3. Replace the AppKit UI layer (`EditorView`, `LineNumberRulerView`, `WindowController`, `AppearanceManager`) with platform-native equivalents
4. `DocumentController` is mostly portable — only `NSOpenPanel`/`NSSavePanel` need replacing
