import AppKit

final class EditorViewController: NSViewController {

    // Sub-components
    let editorView          = EditorView(frame: .zero)
    let documentController  = DocumentController()
    let appearanceManager: AppearanceManager
    private let initialFileURL: URL?
    private let shouldLoadRecoveryBuffer: Bool
    private var findCoordinator: FindBarCoordinator!

    /// Called whenever document state changes (title, modified flag, URL).
    /// TabController uses this to keep the window and tab label in sync.
    var onStateChanged: (() -> Void)?

    private var textView: NSTextView { editorView.textView }

    // MARK: - Init

    init(appearanceManager: AppearanceManager, initialFileURL: URL? = nil, loadRecoveryBuffer: Bool = false) {
        self.appearanceManager = appearanceManager
        self.initialFileURL = initialFileURL
        self.shouldLoadRecoveryBuffer = loadRecoveryBuffer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View lifecycle

    override func loadView() {
        view = editorView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        documentController.delegate = self
        findCoordinator = FindBarCoordinator(textView: textView)

        // Load initial file if launched by Finder/CLI; otherwise restore recovery buffer
        if let url = initialFileURL {
            documentController.openFile(at: url)
        } else if shouldLoadRecoveryBuffer, let recovered = RecoveryBuffer.load(), !recovered.isEmpty {
            textView.string = recovered
            documentController.isModified = true
            updateWindowState()
        }

        // Observe text changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )

        // Observe cursor movement
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
    }

    // MARK: - Notifications

    @objc private func textDidChange(_ notification: Notification) {
        if !documentController.isModified {
            documentController.isModified = true
            updateWindowState()
        }
        // Auto-save to recovery buffer
        documentController.saveToRecoveryBuffer()
        editorView.rulerView.needsDisplay = true
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        // Redraw line numbers when cursor moves (to show new line number immediately)
        editorView.rulerView.needsDisplay = true
    }

    // MARK: - Window state

    private func updateWindowState() {
        onStateChanged?()
    }

    // MARK: - Menu actions (via responder chain, target: nil in menu setup)

    @objc func newDocument(_ sender: Any?)      { documentController.newDocument() }
    @objc func openDocument(_ sender: Any?)     { documentController.openDocument() }
    @objc func saveDocument(_ sender: Any?)     { documentController.saveDocument() }
    @objc func saveDocumentAs(_ sender: Any?)   { documentController.saveDocumentAs() }

    @objc func removeBlankLines(_ sender: Any?) {
        let original = textView.string
        let result   = TextEngine.removeBlankLines(in: original)
        guard result != original else { return }
        let nsLen = (original as NSString).length
        textView.insertText(result, replacementRange: NSRange(location: 0, length: nsLen))
        textView.undoManager?.setActionName("Remove Blank Lines")
    }

    @objc func toggleDarkMode(_ sender: Any?) {
        appearanceManager.toggle()
        // Update menu item title if sender is an NSMenuItem
        if let item = sender as? NSMenuItem {
            item.title = appearanceManager.mode.menuTitle
        }
    }

    @objc func clearRecoveryBuffer(_ sender: Any?) {
        documentController.clearRecoveryBuffer()
    }

// MARK: - Validate menu items (NSMenuItemValidation)
}

// MARK: - NSMenuItemValidation

extension EditorViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(saveDocument(_:)):
            return documentController.isModified
        case #selector(toggleDarkMode(_:)):
            menuItem.title = appearanceManager.mode.menuTitle
            return true
        default:
            return true
        }
    }
}

// MARK: - DocumentControllerDelegate

extension EditorViewController: DocumentControllerDelegate {

    func documentDidLoad(url: URL?, content: String) {
        textView.string = content
        textView.undoManager?.removeAllActions()
        documentController.isModified = false
        editorView.rulerView.needsDisplay = true
        updateWindowState()
    }

    func documentDidSave(url: URL) {
        updateWindowState()
    }

    func currentContent() -> String {
        textView.string
    }
}
