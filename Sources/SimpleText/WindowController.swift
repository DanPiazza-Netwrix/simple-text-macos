import AppKit

final class WindowController: NSWindowController, NSWindowDelegate {

    private(set) var appearanceManager: AppearanceManager!
    private(set) var editorVC: EditorViewController!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        window.title                        = "Untitled — v0.0.1.22"
        window.minSize                      = NSSize(width: 480, height: 300)

        self.init(window: window)
        window.delegate = self

        appearanceManager = AppearanceManager(window: window)

        editorVC = EditorViewController(appearanceManager: appearanceManager)
        window.contentViewController = editorVC

        // Wire DocumentController's window reference
        editorVC.documentController.window = window

        // Restore frame AFTER contentViewController is set (setting it resizes the window)
        window.setFrameAutosaveName("SimpleTextMain")
        if !window.setFrameUsingName(NSWindow.FrameAutosaveName("SimpleTextMain")) {
            window.center()
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of close, keep app running in background
        sender.orderOut(nil)
        return false
    }
}
