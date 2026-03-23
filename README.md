# SimpleText

A lightweight, native macOS plaintext editor. No rich formatting — just fast, clean text editing.

## Features

- **Line numbers** with automatic gutter width
- **Dark / light mode toggle** (Cmd+Shift+D) — independent of system setting
- **Remove blank lines** (Edit menu)
- **Native find bar** with Next / Previous / case-sensitive (Cmd+F)
- **Undo / Redo** (Cmd+Z / Cmd+Shift+Z)
- **Recovery buffer** — unsaved edits auto-save and persist between app launches
- **Window position & size memory** — remembers your window layout on relaunch
- **Background mode** — closing the window hides the app instead of quitting
- Opens files passed as command-line arguments
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
| `RecoveryBuffer.swift` | Auto-saves unsaved edits to `~/Library/Application Support/SimpleText/` |
| `EditorView.swift` | `NSScrollView` + `NSTextView` composition with line number ruler |
| `LineNumberRulerView.swift` | Custom `NSRulerView` gutter with dynamic sizing |
| `DocumentController.swift` | File I/O (open, save, new) and recovery buffer integration |
| `AppearanceManager.swift` | Dark / light mode toggle via `window.appearance` override |
| `EditorViewController.swift` | Central coordinator; owns UI subviews and handles menu actions |
| `WindowController.swift` | Window lifecycle; hides on close (background mode) |
| `AppDelegate.swift` | App lifecycle and programmatic menu bar construction |
| `FindBarCoordinator.swift` | Thin wrapper around AppKit's native find bar |
