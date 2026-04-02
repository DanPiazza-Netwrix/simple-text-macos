import AppKit

final class WindowController: NSWindowController, NSWindowDelegate {

    private(set) var appearanceManager: AppearanceManager!
    private(set) var tabController: TabController!

    convenience init(initialFileURL: URL? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        window.title    = "Untitled — v0.0.1.89"
        window.minSize  = NSSize(width: 480, height: 300)

        self.init(window: window)
        window.delegate = self

        appearanceManager = AppearanceManager(window: window)
        tabController = TabController(appearanceManager: appearanceManager, initialFileURL: initialFileURL)
        window.contentViewController = tabController

        // Restore frame AFTER contentViewController is set (setting it resizes the window)
        window.setFrameAutosaveName("SimpleTextMain")
        if !window.setFrameUsingName(NSWindow.FrameAutosaveName("SimpleTextMain")) {
            window.center()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        tabController.activeEditorVC?.tabUndoManager
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of close, keep app running in background
        sender.orderOut(nil)
        return false
    }
}
