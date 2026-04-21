import AppKit

final class WindowController: NSWindowController, NSWindowDelegate {

    private(set) var appearanceManager: AppearanceManager!
    private(set) var splitController: SplitController!

    convenience init(initialFileURL: URL? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        window.title    = "Untitled"
        window.minSize  = NSSize(width: 480, height: 300)

        self.init(window: window)
        window.delegate = self

        appearanceManager = AppearanceManager(window: window)
        splitController = SplitController(appearanceManager: appearanceManager, initialFileURL: initialFileURL)
        window.contentViewController = splitController

        // Restore frame AFTER contentViewController is set (setting it resizes the window)
        window.setFrameAutosaveName("SimpleTextMain")
        if !window.setFrameUsingName(NSWindow.FrameAutosaveName("SimpleTextMain")) {
            window.center()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        splitController.activeEditorVC?.tabUndoManager
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of close, keep app running in background
        sender.orderOut(nil)
        return false
    }
}
