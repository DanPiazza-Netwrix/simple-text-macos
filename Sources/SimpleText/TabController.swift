import AppKit

final class TabController: NSViewController {

    private let appearanceManager: AppearanceManager
    var editorVCs: [EditorViewController] = []
    private var selectedIndex: Int = 0
    private var currentChildVC: EditorViewController?

    private let tabBar = TabBarView()
    private let editorContainer = NSView()

    // MARK: - Init

    init(appearanceManager: AppearanceManager, initialFileURL: URL? = nil) {
        self.appearanceManager = appearanceManager
        super.init(nibName: nil, bundle: nil)

        if let url = initialFileURL {
            // Launched with a specific file — open it, skip session restore.
            appendEditorVC(fileURL: url)
        } else if let session = RecoveryBuffer.loadSession(), !session.tabs.isEmpty {
            // Restore all tabs from the previous session.
            for entry in session.tabs {
                if let content = entry.content {
                    appendEditorVC(fileURL: entry.url, restoredContent: content)
                } else if let url = entry.url,
                          FileManager.default.fileExists(atPath: url.path) {
                    appendEditorVC(fileURL: url)
                } else if entry.url == nil, entry.content == nil {
                    appendEditorVC()
                }
                // else: had a URL but file is gone — skip
            }
            if editorVCs.isEmpty { appendEditorVC() }
            selectedIndex = min(session.selectedIndex, editorVCs.count - 1)
        } else {
            appendEditorVC()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View lifecycle

    override func loadView() {
        let root = NSView()

        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(tabBar)
        root.addSubview(editorContainer)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: TabBarView.height),

            editorContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            editorContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            editorContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            editorContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadTabBar()
        switchTo(index: selectedIndex)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        syncWindow()
    }

    // MARK: - Accessors

    var activeEditorVC: EditorViewController? { editorVCs[safe: selectedIndex] }

    // MARK: - Tab actions (reached via responder chain, target: nil in menu)

    @objc func newTab(_ sender: Any? = nil) {
        appendEditorVC()
        DispatchQueue.main.async {
            self.view.window?.makeFirstResponder(self.activeEditorVC?.editorView.textView)
        }
    }

    @objc func closeTab(_ sender: Any? = nil) {
        guard let vc = editorVCs[safe: selectedIndex] else { return }
        confirmAndClose(vc: vc) { [weak self] in self?.performCloseCurrentTab() }
    }

    private func performCloseCurrentTab() {
        guard editorVCs.count > 1 else {
            clearSessionIfCleanFile(editorVCs.first)
            view.window?.orderOut(nil)
            return
        }
        detachCurrent()
        editorVCs.remove(at: selectedIndex)
        selectedIndex = min(selectedIndex, editorVCs.count - 1)
        reloadTabBar()
        switchTo(index: selectedIndex)
        snapshotRecovery()
    }

    // MARK: - File opens (called by AppDelegate)

    func openFileInTab(at url: URL) {
        // Reuse active tab only if it is pristine
        if let active = activeEditorVC,
           active.documentController.currentURL == nil,
           !active.documentController.isModified,
           active.currentContent().isEmpty {
            active.documentController.openFile(at: url)
        } else {
            appendEditorVC(fileURL: url)
        }
    }

    // MARK: - Window sync

    func syncWindow() {
        guard let vc = activeEditorVC, let window = view.window else { return }
        let filename = vc.documentController.currentURL?.lastPathComponent ?? "Untitled"
        window.title = "\(filename) — v0.0.1.66"
        window.representedURL = vc.documentController.currentURL
        window.isDocumentEdited = vc.documentController.isModified
        reloadTabBar()
    }

    // MARK: - Private helpers

    private func appendEditorVC(fileURL: URL? = nil, restoredContent: String? = nil) {
        let vc = EditorViewController(
            appearanceManager: appearanceManager,
            initialFileURL: fileURL,
            restoredContent: restoredContent
        )
        vc.onStateChanged = { [weak self] in
            self?.syncWindow()
            self?.snapshotRecovery()
        }
        vc.onTextChanged  = { [weak self] in self?.snapshotRecovery() }
        vc.onFilesDropped = { [weak self] urls in urls.forEach { self?.openFileInTab(at: $0) } }
        editorVCs.append(vc)
        selectedIndex = editorVCs.count - 1

        if isViewLoaded {
            reloadTabBar()
            switchTo(index: selectedIndex)
        }
    }

    /// Shows a Save/Don't Save/Cancel sheet when closing a named file with unsaved changes.
    /// Calls `closeAction` immediately if no prompt is needed (untitled buffers, or clean files).
    private func confirmAndClose(vc: EditorViewController, closeAction: @escaping () -> Void) {
        guard let url = vc.documentController.currentURL,
              vc.documentController.isModified,
              let window = view.window else {
            closeAction()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Save \"\(url.lastPathComponent)\" before closing?"
        alert.informativeText = "Your changes will be lost if you don't save."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:   // Save
                vc.documentController.saveDocument()
                closeAction()
            case .alertSecondButtonReturn:  // Don't Save
                closeAction()
            default: break                  // Cancel — abort close
            }
        }
    }

    /// If the given VC is a clean saved file (no unsaved changes), clear the
    /// session so the next launch opens a blank Untitled tab instead of
    /// re-opening the file. If it's an unsaved buffer, leave the session alone
    /// — the last snapshotRecovery() call already captured the content.
    private func clearSessionIfCleanFile(_ vc: EditorViewController?) {
        guard let dc = vc?.documentController else { return }
        if dc.currentURL != nil && !dc.isModified {
            RecoveryBuffer.clear()
        }
    }

    private func snapshotRecovery() {
        let entries = editorVCs.map { vc -> TabRecoveryEntry in
            let dc = vc.documentController
            if let url = dc.currentURL, !dc.isModified {
                // Saved and clean — just reopen the file on restore.
                return TabRecoveryEntry(url: url, content: nil)
            }
            // Unsaved or modified — persist the content (and URL if known).
            return TabRecoveryEntry(url: dc.currentURL, content: vc.currentContent())
        }
        RecoveryBuffer.saveSession(RecoverySession(tabs: entries, selectedIndex: selectedIndex))
    }

    private func switchTo(index: Int) {
        detachCurrent()
        guard let vc = editorVCs[safe: index] else { return }
        currentChildVC = vc
        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
            vc.view.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
        ])
        selectedIndex = index
        syncWindow()
        view.window?.makeFirstResponder(vc.editorView.textView)
    }

    private func detachCurrent() {
        guard let vc = currentChildVC else { return }
        vc.view.removeFromSuperview()
        if let idx = children.firstIndex(of: vc) { removeChild(at: idx) }
        currentChildVC = nil
    }

    private func reloadTabBar() {
        let titles   = editorVCs.map { $0.documentController.currentURL?.lastPathComponent ?? "Untitled" }
        let modified = editorVCs.map { $0.documentController.isModified }
        tabBar.reloadTabs(titles: titles, modified: modified, selectedIndex: selectedIndex)
    }
}

// MARK: - TabBarDelegate

extension TabController: TabBarDelegate {
    func tabBar(_ bar: TabBarView, didSelectTabAt index: Int) {
        guard index != selectedIndex else { return }
        switchTo(index: index)
    }

    func tabBar(_ bar: TabBarView, didCloseTabAt index: Int) {
        guard let vc = editorVCs[safe: index] else { return }
        confirmAndClose(vc: vc) { [weak self] in self?.performClose(at: index) }
    }

    private func performClose(at index: Int) {
        guard editorVCs.count > 1 else {
            clearSessionIfCleanFile(editorVCs.first)
            view.window?.orderOut(nil)
            return
        }
        let wasSelected = (index == selectedIndex)
        if wasSelected { detachCurrent() }
        editorVCs.remove(at: index)
        // Adjust selected index: closing a tab to the left shifts everything left by 1
        if index < selectedIndex {
            selectedIndex -= 1
        } else if wasSelected {
            selectedIndex = min(selectedIndex, editorVCs.count - 1)
        }
        reloadTabBar()
        if wasSelected { switchTo(index: selectedIndex) }
        snapshotRecovery()
    }

    func tabBar(_ bar: TabBarView, didCloseTabsToRightOf index: Int) {
        guard index < editorVCs.count - 1 else { return }
        if selectedIndex > index {
            detachCurrent()
            selectedIndex = index
        }
        editorVCs.removeSubrange((index + 1)...)
        reloadTabBar()
        if currentChildVC == nil { switchTo(index: selectedIndex) }
        snapshotRecovery()
    }

    func tabBar(_ bar: TabBarView, didCloseOtherTabsThan index: Int) {
        guard editorVCs.count > 1 else { return }
        let keep = editorVCs[index]
        if currentChildVC !== keep { detachCurrent() }
        editorVCs = [keep]
        selectedIndex = 0
        reloadTabBar()
        if currentChildVC == nil { switchTo(index: 0) } else { syncWindow() }
        snapshotRecovery()
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
