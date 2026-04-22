import AppKit

// MARK: - Split direction

enum SplitDirection {
    case vertical   // left/right
    case horizontal // top/bottom
}

// MARK: - TabController

final class TabController: NSViewController {

    private let appearanceManager: AppearanceManager
    var editorVCs: [EditorViewController] = []
    private(set) var selectedIndex: Int = 0
    private var currentChildVC: EditorViewController?

    let tabBar = TabBarView()
    private let editorContainer = NSView()

    /// Track if this is the leftmost pane (should show version in status bar)
    var isLeftmostPane: Bool = false {
        didSet { updateEditorViewsVersionDisplay() }
    }

    // MARK: - Callbacks (set by SplitController)

    /// Fired when this pane receives user focus (e.g. its text view becomes first responder).
    var onBecameActive: (() -> Void)?
    /// Replaces direct RecoveryBuffer saves — SplitController aggregates all panes.
    var onRecoveryNeeded: (() -> Void)?
    /// Fired when the last tab in this pane is closed (signals SplitController to unsplit).
    var onLastTabClosed: (() -> Void)?
    /// Fired when user right-clicks "Move to New View" / "Move to Other Pane" — passes the tab index.
    var onRequestMoveToNewPane: ((_ tabIndex: Int) -> Void)?
    /// Fired when a cross-pane drop lands — passes source pane ID, source tab index, dest local index.
    var onReceiveCrossPaneDrop: ((_ sourcePaneId: String, _ sourceTabIndex: Int, _ destIndex: Int) -> Void)?
    /// Fired when user right-clicks "Split View Vertically/Horizontally" in the editor context menu.
    var onRequestSplitPane: ((_ direction: SplitDirection) -> Void)?
    /// Fired when user right-clicks "Merge Views" in the editor context menu.
    var onRequestClosePane: (() -> Void)?
    /// Supply a closure that returns true if close pane should be enabled.
    var canClosePaneCallback: (() -> Bool)?

    // MARK: - Init

    init(appearanceManager: AppearanceManager) {
        self.appearanceManager = appearanceManager
        super.init(nibName: nil, bundle: nil)
    }

    /// Restore tabs from recovery entries. Call before the view loads.
    func restoreTabs(from entries: [TabRecoveryEntry], selectedIndex: Int) {
        for entry in entries {
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
        self.selectedIndex = min(selectedIndex, editorVCs.count - 1)
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

        NotificationCenter.default.addObserver(
            self, selector: #selector(editorDidBecomeActive(_:)),
            name: .simpleTextEditorDidBecomeActive, object: nil)
    }

    @objc private func editorDidBecomeActive(_ note: Notification) {
        guard let textView = note.object as? EditorTextView,
              editorVCs.contains(where: { $0.editorView.textView === textView }) else { return }
        onBecameActive?()
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

    @objc func closeAllTabs(_ sender: Any? = nil) {
        guard editorVCs.count > 1 else { closeTab(nil); return }
        // Close all but the last (prompting for each dirty tab), then close the
        // last one via closeTab which handles the replace-with-blank case.
        let all = Array(editorVCs)
        confirmAndCloseMultiple(vcs: Array(all.dropLast())) { [weak self] in
            self?.closeTab(nil)
        }
    }

    private func performCloseCurrentTab() {
        guard editorVCs.count > 1 else {
            replaceLastTabWithBlank()
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
        window.title = filename
        window.representedURL = vc.documentController.currentURL
        window.isDocumentEdited = vc.documentController.isModified
        reloadTabBar()
    }

    // MARK: - Private helpers

    private func wireCallbacks(_ vc: EditorViewController) {
        vc.onStateChanged = { [weak self] in
            self?.syncWindow()
            self?.snapshotRecovery()
        }
        vc.onTextChanged  = { [weak self] in self?.snapshotRecovery() }
        vc.onFilesDropped = { [weak self] urls in urls.forEach { self?.openFileInTab(at: $0) } }
        vc.onEditorContextMenu = { [weak self] menu in
            self?.buildContextMenuItems(menu)
        }
    }

    private func appendEditorVC(fileURL: URL? = nil, restoredContent: String? = nil) {
        let vc = EditorViewController(
            appearanceManager: appearanceManager,
            initialFileURL: fileURL,
            restoredContent: restoredContent
        )
        wireCallbacks(vc)
        editorVCs.append(vc)
        selectedIndex = editorVCs.count - 1

        if isViewLoaded {
            reloadTabBar()
            switchTo(index: selectedIndex)
        }
    }

    /// Returns true if `vc` needs a save prompt before closing.
    private func needsPrompt(_ vc: EditorViewController) -> Bool {
        let dc = vc.documentController
        if dc.currentURL != nil && dc.isModified { return true }
        if dc.currentURL == nil && dc.isModified && !vc.currentContent().isEmpty { return true }
        return false
    }

    /// Processes `vcs` one at a time: prompts for dirty tabs, closes each tab immediately
    /// after its prompt is resolved, then moves on to the next. Cancelling any prompt
    /// aborts the rest of the batch. `completion` is called only if all tabs are closed.
    private func confirmAndCloseMultiple(vcs: [EditorViewController], completion: (() -> Void)? = nil) {
        guard !vcs.isEmpty else { completion?(); return }
        var rest = vcs
        let vc = rest.removeFirst()

        let closeAndContinue = { [weak self] in
            guard let self else { return }
            if let idx = self.editorVCs.firstIndex(of: vc) { self.closeVC(at: idx) }
            self.confirmAndCloseMultiple(vcs: rest, completion: completion)
        }

        if needsPrompt(vc) {
            confirmAndClose(vc: vc, closeAction: closeAndContinue)
        } else {
            closeAndContinue()
        }
    }

    /// Closes the tab at `index` without any prompt. Updates selectedIndex, reloads the
    /// tab bar, and snapshots recovery. Does nothing if it would remove the last tab.
    private func closeVC(at index: Int) {
        guard editorVCs.count > 1 else { return }
        let wasSelected = (index == selectedIndex)
        if wasSelected { detachCurrent() }
        editorVCs.remove(at: index)
        if index < selectedIndex {
            selectedIndex -= 1
        } else if wasSelected {
            selectedIndex = min(selectedIndex, editorVCs.count - 1)
        }
        reloadTabBar()
        if wasSelected { switchTo(index: selectedIndex) }
        snapshotRecovery()
    }

    /// Shows a Save/Don't Save/Cancel sheet when closing a tab with unsaved content.
    /// - Named file with unsaved changes: prompts with the filename.
    /// - Untitled buffer with content: prompts generically; Save shows a Save panel and
    ///   only closes the tab after the file is written.
    /// - Clean or empty tabs: closes immediately with no prompt.
    private func confirmAndClose(vc: EditorViewController, closeAction: @escaping () -> Void) {
        guard let window = view.window else { closeAction(); return }
        let dc = vc.documentController

        if let url = dc.currentURL, dc.isModified {
            // Named file with unsaved changes
            let alert = NSAlert()
            alert.messageText = "Save \"\(url.lastPathComponent)\" before closing?"
            alert.informativeText = "Your changes will be lost if you don't save."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in
                switch response {
                case .alertFirstButtonReturn:   // Save
                    dc.saveDocument()
                    closeAction()
                case .alertSecondButtonReturn:  // Don't Save
                    closeAction()
                default: break
                }
            }
        } else if dc.currentURL == nil && dc.isModified && !vc.currentContent().isEmpty {
            // Untitled buffer with content
            let alert = NSAlert()
            alert.messageText = "Save changes to this untitled document?"
            alert.informativeText = "Your changes will be lost if you don't save."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in
                switch response {
                case .alertFirstButtonReturn:   // Save — show Save panel; close after write
                    dc.saveDocumentAs(completion: closeAction)
                case .alertSecondButtonReturn:  // Don't Save
                    closeAction()
                default: break
                }
            }
        } else {
            closeAction()
        }
    }

    /// Closes the last remaining tab. If this is a secondary pane in a split,
    /// signals the parent to unsplit. Otherwise replaces with a fresh blank tab.
    private func replaceLastTabWithBlank() {
        if onLastTabClosed != nil && (canClosePaneCallback?() == true) {
            detachCurrent()
            editorVCs.removeAll()
            selectedIndex = 0
            onLastTabClosed?()
            return
        }
        detachCurrent()
        editorVCs.removeAll()
        selectedIndex = 0
        appendEditorVC()  // appends, reloads tab bar, and switches to index 0
        snapshotRecovery()
    }

    /// Returns the current recovery state for this pane (used by SplitController).
    func buildRecoveryEntries() -> PaneRecoveryEntry {
        let entries = editorVCs.map { vc -> TabRecoveryEntry in
            let dc = vc.documentController
            if let url = dc.currentURL, !dc.isModified {
                return TabRecoveryEntry(url: url, content: nil)
            }
            return TabRecoveryEntry(url: dc.currentURL, content: vc.currentContent())
        }
        return PaneRecoveryEntry(tabs: entries, selectedIndex: selectedIndex)
    }

    private func snapshotRecovery() {
        onRecoveryNeeded?()
    }

    // MARK: - Cross-pane tab transfer

    /// Detaches and returns the editor VC at `index` without destroying it.
    /// Returns nil if this is the last tab (use onLastTabClosed instead).
    func removeTab(at index: Int) -> EditorViewController? {
        guard editorVCs.count > 1 else { return nil }
        let wasSelected = (index == selectedIndex)
        if wasSelected { detachCurrent() }
        let vc = editorVCs.remove(at: index)
        vc.onStateChanged = nil
        vc.onTextChanged = nil
        vc.onFilesDropped = nil
        if index < selectedIndex {
            selectedIndex -= 1
        } else if wasSelected {
            selectedIndex = min(selectedIndex, editorVCs.count - 1)
        }
        reloadTabBar()
        if wasSelected { switchTo(index: selectedIndex) }
        snapshotRecovery()
        return vc
    }

    /// Inserts an existing EditorViewController (from another pane) at `index`.
    func insertTab(_ vc: EditorViewController, at index: Int) {
        wireCallbacks(vc)
        let clampedIndex = min(index, editorVCs.count)
        editorVCs.insert(vc, at: clampedIndex)
        selectedIndex = clampedIndex
        if isViewLoaded {
            reloadTabBar()
            switchTo(index: selectedIndex)
        }
        snapshotRecovery()
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

    /// Update all editor views' version display based on isLeftmostPane flag.
    private func updateEditorViewsVersionDisplay() {
        for vc in editorVCs {
            vc.editorView.showVersionInStatusBar = isLeftmostPane
        }
    }

    /// Public wrapper so SplitController can trigger a tab bar refresh (e.g. after split state changes).
    func reloadTabBarIfNeeded() { reloadTabBar() }

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
            replaceLastTabWithBlank()
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
        confirmAndCloseMultiple(vcs: Array(editorVCs[(index + 1)...]))
    }

    func tabBar(_ bar: TabBarView, didCloseOtherTabsThan index: Int) {
        guard editorVCs.count > 1 else { return }
        let keep = editorVCs[index]
        confirmAndCloseMultiple(vcs: editorVCs.filter { $0 !== keep })
    }

    func tabBarDidCloseAllTabs(_ bar: TabBarView) {
        closeAllTabs(nil)
    }

    func tabBar(_ bar: TabBarView, didMoveTabFrom fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex,
              editorVCs.indices.contains(fromIndex),
              editorVCs.indices.contains(toIndex) else { return }
        let vc = editorVCs.remove(at: fromIndex)
        editorVCs.insert(vc, at: toIndex)
        // Keep the selected tab visually tracked through the move
        if selectedIndex == fromIndex {
            selectedIndex = toIndex
        } else if fromIndex < selectedIndex && toIndex >= selectedIndex {
            selectedIndex -= 1
        } else if fromIndex > selectedIndex && toIndex <= selectedIndex {
            selectedIndex += 1
        }
        reloadTabBar()
        snapshotRecovery()
    }

    func tabBar(_ bar: TabBarView, didRequestMoveToNewPaneAt index: Int) {
        onRequestMoveToNewPane?(index)
    }

    func tabBar(_ bar: TabBarView, didReceiveDropFromPaneId paneId: String, tabIndex: Int, atLocalIndex destIndex: Int) {
        onReceiveCrossPaneDrop?(paneId, tabIndex, destIndex)
    }
}

// MARK: - Editor context menu (split/close pane)

extension TabController {
    private func buildContextMenuItems(_ menu: NSMenu) {
        menu.addItem(.separator())

        let alreadySplit = canClosePaneCallback?() ?? false
        let splitVItem = menu.addItem(withTitle: "Split View Vertically", action: #selector(handleSplitVerticalFromMenu), keyEquivalent: "")
        splitVItem.target = self
        splitVItem.isEnabled = !alreadySplit

        let closeItem = menu.addItem(withTitle: "Merge Views", action: #selector(handleCloseFromMenu), keyEquivalent: "")
        closeItem.target = self
        closeItem.isEnabled = alreadySplit
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let alreadySplit = canClosePaneCallback?() ?? false
        if menuItem.action == #selector(handleSplitVerticalFromMenu) { return !alreadySplit }
        if menuItem.action == #selector(handleCloseFromMenu) { return alreadySplit }
        return true
    }

    @objc private func handleSplitVerticalFromMenu() {
        onRequestSplitPane?(.vertical)
    }

    @objc private func handleCloseFromMenu() {
        onRequestClosePane?()
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
