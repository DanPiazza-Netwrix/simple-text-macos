import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: WindowController?
    private var pendingFileURL: URL?

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prefer a Finder-opened file over CLI args; CLI args over recovery buffer
        let initialURL: URL? = pendingFileURL
            ?? CommandLine.arguments.dropFirst()
                .first(where: { FileManager.default.fileExists(atPath: $0) })
                .map { URL(fileURLWithPath: $0) }
        pendingFileURL = nil

        windowController = WindowController(initialFileURL: initialURL)
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            windowController?.showWindow(nil)
        }
        return true
    }

    // Called by macOS before applicationDidFinishLaunching when the app is
    // launched by opening a file (double-click, "Open With…", Dock drop).
    // Also called when the app is already running and a file is opened.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let wc = windowController {
            // App already running — open in a tab
            wc.window?.orderFrontRegardless()
            wc.tabController.openFileInTab(at: url)
        } else {
            // App just launched — store for applicationDidFinishLaunching
            pendingFileURL = url
        }
    }

    // MARK: - Menu construction

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // ── App menu ──────────────────────────────────────────────────────
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About SimpleText", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide SimpleText", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit SimpleText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // ── File menu ─────────────────────────────────────────────────────
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(item("New Tab",   action: #selector(TabController.newTab(_:)),              key: "t"))
        fileMenu.addItem(item("New",       action: #selector(EditorViewController.newDocument(_:)),   key: "n"))
        fileMenu.addItem(item("Open…",     action: #selector(EditorViewController.openDocument(_:)),  key: "o"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Save",      action: #selector(EditorViewController.saveDocument(_:)),  key: "s"))
        let saveAs = item("Save As…", action: #selector(EditorViewController.saveDocumentAs(_:)), key: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Close Tab", action: #selector(TabController.closeTab(_:)),             key: "w"))

        // ── Edit menu ─────────────────────────────────────────────────────
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(item("Undo",       action: Selector(("undo:")),       key: "z"))
        let redo = item("Redo",            action: Selector(("redo:")),        key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut",        action: #selector(NSText.cut(_:)),          key: "x"))
        editMenu.addItem(item("Copy",       action: #selector(NSText.copy(_:)),         key: "c"))
        editMenu.addItem(item("Paste",      action: #selector(NSText.paste(_:)),        key: "v"))
        editMenu.addItem(item("Select All", action: #selector(NSText.selectAll(_:)),    key: "a"))
        editMenu.addItem(.separator())
        let removeBlank = item("Remove Blank Lines", action: #selector(EditorViewController.removeBlankLines(_:)), key: "")
        editMenu.addItem(removeBlank)
        editMenu.addItem(item("Clear Unsaved Buffer", action: #selector(EditorViewController.clearRecoveryBuffer(_:)), key: ""))

        // ── View menu ─────────────────────────────────────────────────────
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let darkToggle = item("Use Dark Mode", action: #selector(EditorViewController.toggleDarkMode(_:)), key: "d")
        darkToggle.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(darkToggle)

        // ── Find menu ─────────────────────────────────────────────────────
        let findItem = NSMenuItem()
        mainMenu.addItem(findItem)
        let findMenu = NSMenu(title: "Find")
        findItem.submenu = findMenu
        // Use NSTextView's built-in find bar action
        let findAction = item("Find…", action: #selector(NSTextView.performFindPanelAction(_:)), key: "f")
        findAction.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        findMenu.addItem(findAction)
        let findNext = item("Find Next", action: #selector(NSTextView.performFindPanelAction(_:)), key: "g")
        findNext.tag = Int(NSTextFinder.Action.nextMatch.rawValue)
        findMenu.addItem(findNext)
        let findPrev = item("Find Previous", action: #selector(NSTextView.performFindPanelAction(_:)), key: "g")
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        findPrev.tag = Int(NSTextFinder.Action.previousMatch.rawValue)
        findMenu.addItem(findPrev)

        // ── Window menu ───────────────────────────────────────────────────
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(item("Minimize", action: #selector(NSWindow.miniaturize(_:)), key: "m"))
        windowMenu.addItem(item("Zoom",     action: #selector(NSWindow.zoom(_:)),        key: ""))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Helper

    private func item(_ title: String, action: Selector?, key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}
