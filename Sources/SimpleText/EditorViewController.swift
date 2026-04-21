import AppKit

final class EditorViewController: NSViewController {

    // Sub-components
    let editorView          = EditorView(frame: .zero)
    let documentController  = DocumentController()
    let appearanceManager: AppearanceManager
    private let initialFileURL: URL?
    private let restoredContent: String?

    /// Called whenever document state changes (title, modified flag, URL).
    /// TabController uses this to keep the window and tab label in sync.
    var onStateChanged: (() -> Void)?
    /// Fired on every keystroke — TabController uses this to snapshot all tabs.
    var onTextChanged: (() -> Void)?

    private var syntaxHighlighter: SyntaxHighlighter?
    private var highlightCoordinator: HighlightCoordinator?
    let tabUndoManager = UndoManager()

    /// Called when files are dropped onto the editor. TabController opens each URL in a new tab.
    var onFilesDropped: (([URL]) -> Void)? {
        didSet { editorView.onFilesDropped = onFilesDropped }
    }

    /// Called when right-clicking in the editor to show split/close pane options.
    var onEditorContextMenu: ((NSMenu) -> Void)? {
        didSet { editorView.onContextMenu = onEditorContextMenu }
    }

    private var textView: NSTextView { editorView.textView }

    // MARK: - Init

    init(appearanceManager: AppearanceManager,
         initialFileURL: URL? = nil,
         restoredContent: String? = nil) {
        self.appearanceManager = appearanceManager
        self.initialFileURL = initialFileURL
        self.restoredContent = restoredContent
        super.init(nibName: nil, bundle: nil)
        // Pre-populate URL so the tab bar can show the filename before viewDidLoad fires.
        documentController.currentURL = initialFileURL
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View lifecycle

    override func loadView() {
        view = editorView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        documentController.delegate = self
        textView.delegate = self

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
            onStateChanged?()
        } else if (tabUndoManager.isUndoing || tabUndoManager.isRedoing),
                  let clean = documentController.savedContent,
                  textView.string == clean {
            // All changes undone back to the saved state — clear the dirty flag.
            documentController.isModified = false
            onStateChanged?()
        }
        onTextChanged?()
        editorView.rulerView.needsDisplay = true
        updateStatusBar()
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        editorView.rulerView.needsDisplay = true
        updateStatusBar()
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

    @objc func zoomIn(_ sender: Any?)    { adjustFontSize(by:  1) }
    @objc func zoomOut(_ sender: Any?)   { adjustFontSize(by: -1) }
    @objc func resetZoom(_ sender: Any?) { setFontSize(12) }

    private func adjustFontSize(by delta: CGFloat) {
        let current = textView.font?.pointSize ?? 12
        setFontSize(max(8, min(72, current + delta)))
    }

    private func setFontSize(_ size: CGFloat) {
        let font = NSFont(name: "Monaco", size: size)
               ?? NSFont(name: "Menlo", size: size)
               ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        textView.font = font
        UserDefaults.standard.set(size, forKey: "fontSize")
        editorView.rulerView.needsDisplay = true
    }

    private func updateStatusBar() {
        let string = textView.string as NSString
        let loc    = min(textView.selectedRange().location, string.length)
        let lineStart = string.lineRange(for: NSRange(location: loc, length: 0)).location
        let col  = loc - lineStart + 1
        let line = (string.substring(to: loc) as String)
                       .components(separatedBy: "\n").count
        let words = textView.string.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
        let chars = textView.string.count
        editorView.updateStatus(line: line, col: col, words: words, chars: chars)
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
        highlightCoordinator = nil
        textView.textStorage?.delegate = nil

        textView.string = content
        tabUndoManager.removeAllActions()
        documentController.isModified = false
        editorView.rulerView.needsDisplay = true
        updateStatusBar()
        onStateChanged?()

        applyHighlighting(for: url)
    }

    /// Sets up (or replaces) the active syntax highlighter for the given URL.
    /// Safe to call after a Save As — tears down the old highlighter first.
    private func applyHighlighting(for url: URL?) {
        syntaxHighlighter = nil
        highlightCoordinator = nil
        textView.textStorage?.delegate = nil

        let ext = url?.pathExtension.lowercased()

        // Markdown: regex-based highlighter (handles bold/italic/links correctly).
        if ext == "md" || ext == "markdown" {
            let hl = SyntaxHighlighter(textView: textView)
            textView.textStorage?.delegate = hl
            hl.highlightAll()
            syntaxHighlighter = hl
            return
        }

        // All other recognized extensions: Tree-sitter via Neon.
        if let url, let langConfig = LanguageRegistry.shared.configuration(for: url) {
            highlightCoordinator = try? HighlightCoordinator(textView: textView, languageConfig: langConfig)
            highlightCoordinator?.observeScrollView()
        }
    }

    func documentDidSave(url: URL) {
        // If we just saved a previously-untitled buffer under a new name, the extension
        // may have changed (e.g. Untitled → test.ps1). Re-apply highlighting for the
        // new URL without reloading content.
        applyHighlighting(for: url)
        onStateChanged?()
    }

    func currentContent() -> String {
        textView.string
    }
}
