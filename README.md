# SimpleText

A lightweight, native macOS plaintext editor. No rich formatting — just fast, clean text editing.

![SimpleText screenshot](docs/screenshot.png)

## Features

- **Tabs** — Cmd+T new tab, Cmd+W close tab; right-click a tab for "Close Tabs to the Right" / "Close Other Tabs"; unsaved tabs restored on relaunch
- **Line numbers** with automatic gutter width
- **Dark / light mode toggle** (Cmd+Shift+D) — independent of system setting
- **Remove blank lines** (Edit menu)
- **Markdown syntax highlighting** — VS Code Dark+/Light+ color scheme, auto-detected by file extension
- **Native find bar** with Next / Previous / case-sensitive (Cmd+F)
- **Undo / Redo** (Cmd+Z / Cmd+Shift+Z)
- **Session recovery** — all open tabs (unsaved or modified) persist between app launches, restoring your exact tab layout and content
- **Window position & size memory** — remembers your window layout on relaunch
- **Background mode** — closing the window hides the app instead of quitting
- Opens files via command-line arguments, Finder (double-click / "Open With…"), drag onto Dock icon, or drag-and-drop directly into the app window
- Custom app icon

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)

## Build

### Run directly (development)

```bash
swift run
swift run SimpleText /path/to/file.txt   # open a specific file
```

### Build a .app bundle

```bash
./build.sh
open build/SimpleText.app
```

The `.app` is written to `build/SimpleText.app`. You can drag it to `/Applications`.

### Open in Xcode

```bash
open Package.swift
```

## Architecture

Built with **Swift + AppKit**, structured for future cross-platform portability:

| File | Role |
|------|------|
| `TextEngine.swift` | Pure Swift text logic — no AppKit, portable to other platforms |
| `RecoveryBuffer.swift` | Auto-saves full session (all tabs) to `~/Library/Application Support/SimpleText/session.json` |
| `EditorView.swift` | `NSScrollView` + `NSTextView` with `LineNumberRulerView` as a sibling view; intercepts file-URL drags to open in a new tab instead of inserting text |
| `LineNumberRulerView.swift` | Custom `NSView` line number gutter with dynamic width; sibling to the scroll view |
| `TabBarView.swift` | Chrome-style tab bar with pill-shaped active tabs and a "+" button |
| `TabController.swift` | Manages multiple editor tabs; routes Finder file opens without losing current work |
| `DocumentController.swift` | File I/O (open, save, new) and recovery buffer integration |
| `AppearanceManager.swift` | Dark / light mode toggle via `window.appearance` override |
| `EditorViewController.swift` | Central coordinator; owns UI subviews and handles menu actions |
| `WindowController.swift` | Window lifecycle; hides on close (background mode) |
| `AppDelegate.swift` | App lifecycle and programmatic menu bar construction |
| `SyntaxHighlighter.swift` | Markdown syntax highlighting using VS Code–matched colors |
| `FindBarCoordinator.swift` | Thin wrapper around AppKit's native find bar |
