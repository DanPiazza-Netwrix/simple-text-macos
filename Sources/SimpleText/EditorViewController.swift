import AppKit

final class EditorViewController: NSViewController {

    // Sub-components
    let editorView          = EditorView(frame: .zero)
    let documentController  = DocumentController()
    let appearanceManager: AppearanceManager
    private let initialFileURL: URL?
    private let restoredContent: String?
    private let shouldLoadRecoveryBuffer: Bool
    private var findCoordinator: FindBarCoordinator!

    /// Called whenever document state changes (title, modified flag, URL).
    /// TabController uses this to keep the window and tab label in sync.
    var onStateChanged: (() -> Void)?
    /// Fired on every keystroke — TabController uses this to snapshot all tabs.
    var onTextChanged: (() -> Void)?

    private var syntaxHighlighter: SyntaxHighlighter?
    let tabUndoManager = UndoManager()

    /// Called when files are dropped onto the editor. TabController opens each URL in a new tab.
    var onFilesDropped: (([URL]) -> Void)? {
        didSet { editorView.onFilesDropped = onFilesDropped }
    }

    private var textView: NSTextView { editorView.textView }

    // MARK: - Init

    init(appearanceManager: AppearanceManager,
         initialFileURL: URL? = nil,
         restoredContent: String? = nil,
         loadRecoveryBuffer: Bool = false) {
        self.appearanceManager = appearanceManager
        self.initialFileURL = initialFileURL
        self.restoredContent = restoredContent
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
        textView.delegate = self

        // Priority: restoredContent > initialFileURL > (legacy single-tab recovery is now
        // handled by TabController, so shouldLoadRecoveryBuffer is vestigial)
        if let content = restoredContent {
            documentController.restore(content: content, url: initialFileURL)
        } else if let url = initialFileURL {
            documentController.openFile(at: url)
        }

        // Observe text changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextDidChange(_:)),
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

    @objc private func handleTextDidChange(_ notification: Notification) {
        if !documentController.isModified {
            documentController.isModified = true
            updateWindowState()
        }
        onTextChanged?()
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

// MARK: - NSTextViewDelegate

extension EditorViewController: NSTextViewDelegate {
    func textView(_ textView: NSTextView,
                  shouldChangeTextIn range: NSRange,
                  replacementString string: String?) -> Bool {
        if let s = string,
           s.unicodeScalars.contains(where: {
               CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0)
           }) {
            textView.breakUndoCoalescing()
        }
        return true
    }
}

// MARK: - DocumentControllerDelegate

extension EditorViewController: DocumentControllerDelegate {

    func documentDidLoad(url: URL?, content: String) {
        // Tear down any existing highlighter before changing the text.
        syntaxHighlighter = nil
        textView.textStorage?.delegate = nil

        textView.string = content
        tabUndoManager.removeAllActions()
        documentController.isModified = false
        editorView.rulerView.needsDisplay = true
        updateWindowState()

        // Wire up syntax highlighting for Markdown files.
        let ext = url?.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            let hl = SyntaxHighlighter(textView: textView)
            textView.textStorage?.delegate = hl
            hl.highlightAll()
            syntaxHighlighter = hl
        }
    }

    func documentDidSave(url: URL) {
        updateWindowState()
    }

    func currentContent() -> String {
        textView.string
    }
}
