import AppKit

// MARK: - SplitController

final class SplitController: NSSplitViewController {

    private let appearanceManager: AppearanceManager
    private(set) var panes: [TabController] = []
    private(set) var activePaneIndex: Int = 0

    var activePane: TabController { panes[activePaneIndex] }
    var activeEditorVC: EditorViewController? { activePane.activeEditorVC }

    /// Flattened list of all editor VCs across all panes.
    var allEditorVCs: [EditorViewController] {
        panes.flatMap { $0.editorVCs }
    }

    // MARK: - Divider persistence

    /// Divider fraction to apply once the view has appeared (set from loaded session).
    private var pendingDividerFraction: Double? = nil

    /// True while we are programmatically positioning the divider.
    /// Suppresses the save in splitViewDidResizeSubviews so intermediate states
    /// (e.g. the moment a new pane is inserted) don't get written to disk.
    private var isSettingDivider = false

    /// Current left-pane fraction of total split width. nil when not split.
    private var currentDividerFraction: Double? {
        guard panes.count == 2,
              splitView.bounds.width > 0,
              let firstSubview = splitView.subviews.first else { return nil }
        return Double(firstSubview.frame.width / splitView.bounds.width)
    }

    /// Positions the divider at `fraction` of the split view's total width.
    private func applyDivider(fraction: CGFloat) {
        guard panes.count >= 2, splitView.bounds.width > 0 else { return }
        isSettingDivider = true
        splitView.setPosition(splitView.bounds.width * fraction, ofDividerAt: 0)
        isSettingDivider = false
    }

    // MARK: - Init

    init(appearanceManager: AppearanceManager, initialFileURL: URL? = nil) {
        self.appearanceManager = appearanceManager
        super.init(nibName: nil, bundle: nil)

        if let url = initialFileURL {
            let pane = makePane()
            pane.restoreTabs(from: [TabRecoveryEntry(url: url, content: nil)], selectedIndex: 0)
            addPane(pane)
        } else if let session = RecoveryBuffer.loadSession(), !session.panes.isEmpty {
            for (i, paneEntry) in session.panes.enumerated() {
                guard !paneEntry.tabs.isEmpty else { continue }
                let pane = makePane()
                pane.restoreTabs(from: paneEntry.tabs, selectedIndex: paneEntry.selectedIndex)
                addPane(pane)
                if i == session.activePaneIndex { activePaneIndex = panes.count - 1 }
            }
            if panes.isEmpty {
                let pane = makePane()
                pane.restoreTabs(from: [], selectedIndex: 0)
                addPane(pane)
            }
            activePaneIndex = min(activePaneIndex, panes.count - 1)
            if panes.count == 2 {
                pendingDividerFraction = session.dividerFraction ?? 0.5
            }
        } else {
            let pane = makePane()
            pane.restoreTabs(from: [], selectedIndex: 0)
            addPane(pane)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let fraction = pendingDividerFraction, panes.count == 2 {
            pendingDividerFraction = nil
            applyDivider(fraction: CGFloat(fraction))
        }
    }

    /// Fired whenever the split view's subviews are resized — by the user dragging
    /// the divider OR by programmatic changes. We save only for user-initiated drags
    /// (isSettingDivider is true during programmatic moves).
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard !isSettingDivider, panes.count == 2 else { return }
        snapshotRecovery()
    }

    // MARK: - Pane management

    private func makePane() -> TabController {
        let pane = TabController(appearanceManager: appearanceManager)
        pane.onBecameActive = { [weak self, weak pane] in
            guard let self, let pane, let idx = self.panes.firstIndex(of: pane) else { return }
            self.setActivePane(idx)
        }
        pane.onRecoveryNeeded = { [weak self] in
            self?.snapshotRecovery()
        }
        pane.onLastTabClosed = { [weak self, weak pane] in
            guard let self, let pane, self.panes.count > 1 else { return }
            if let idx = self.panes.firstIndex(of: pane) {
                self.removePane(at: idx)
                self.updateActivePaneIndicators()
                self.snapshotRecovery()
            }
        }
        pane.onRequestMoveToNewPane = { [weak self, weak pane] tabIndex in
            guard let self, let pane else { return }
            self.moveTabToNewPane(pane, at: tabIndex)
        }
        pane.onReceiveCrossPaneDrop = { [weak self, weak pane] sourcePaneId, sourceTabIndex, destIndex in
            guard let self, let destPane = pane else { return }
            guard let sourcePane = self.panes.first(where: { $0.tabBar.paneId == sourcePaneId }) else { return }
            self.moveTab(from: sourcePane, at: sourceTabIndex, to: destPane, at: destIndex)
        }
        pane.onRequestSplitPane = { [weak self] _ in
            self?.splitPane(nil)
        }
        pane.onRequestClosePane = { [weak self] in
            self?.unsplitPane(nil)
        }
        pane.canClosePaneCallback = { [weak self] in
            (self?.panes.count ?? 0) > 1
        }
        return pane
    }

    private func addPane(_ pane: TabController) {
        panes.append(pane)
        let item = NSSplitViewItem(viewController: pane)
        item.minimumThickness = 200
        item.holdingPriority = .defaultLow
        addSplitViewItem(item)
    }

    private func removePane(at index: Int) {
        guard panes.indices.contains(index) else { return }
        let item = splitViewItems[index]
        removeSplitViewItem(item)
        panes.remove(at: index)
        activePaneIndex = min(activePaneIndex, panes.count - 1)
    }

    private func setActivePane(_ index: Int) {
        guard index != activePaneIndex, panes.indices.contains(index) else { return }
        activePaneIndex = index
        updateActivePaneIndicators()
        syncWindow()
    }

    func updateActivePaneIndicators() {
        let split = panes.count > 1
        for (i, pane) in panes.enumerated() {
            pane.tabBar.isActivePane = (i == activePaneIndex) && split
            pane.tabBar.isSplitActive = split
            pane.isLeftmostPane = (i == 0)
        }
        for pane in panes { pane.reloadTabBarIfNeeded() }
    }

    // MARK: - Split / Unsplit actions (reached via responder chain)

    @objc func splitPane(_ sender: Any? = nil) {
        guard panes.count < 2 else { return }
        let pane = makePane()
        pane.restoreTabs(from: [], selectedIndex: 0)
        isSettingDivider = true   // suppress intermediate saves during addPane layout
        addPane(pane)
        isSettingDivider = false
        updateActivePaneIndicators()
        snapshotRecovery()
        // Set 50/50 after the split view has completed its layout pass
        DispatchQueue.main.async { [weak self] in
            self?.applyDivider(fraction: 0.5)
            self?.snapshotRecovery()   // persist the 0.5 fraction
        }
    }

    @objc func unsplitPane(_ sender: Any? = nil) {
        guard panes.count > 1 else { return }
        let closingIndex = activePaneIndex
        let closingPane = panes[closingIndex]
        let survivingPane = panes[0 == closingIndex ? 1 : 0]

        for vc in closingPane.editorVCs {
            survivingPane.insertTab(vc, at: survivingPane.editorVCs.count)
        }
        closingPane.editorVCs.removeAll()

        removePane(at: closingIndex)
        activePaneIndex = min(activePaneIndex, panes.count - 1)
        updateActivePaneIndicators()
        syncWindow()
        snapshotRecovery()
    }

    @objc func moveTabToOtherPane(_ sender: Any? = nil) {
        guard panes.count > 1 else { return }
        moveTabFromPane(activePane, at: activePane.selectedIndex)
    }

    /// Moves the tab at `tabIndex` from `sourcePane` to the other pane.
    private func moveTabFromPane(_ sourcePane: TabController, at tabIndex: Int) {
        guard panes.count > 1,
              let sourceIdx = panes.firstIndex(of: sourcePane) else { return }
        let destPane = panes[sourceIdx == 0 ? 1 : 0]

        guard let vc = sourcePane.removeTab(at: tabIndex) else {
            unsplitPane(nil)
            return
        }
        destPane.insertTab(vc, at: destPane.editorVCs.count)
        snapshotRecovery()
    }

    /// Called by TabBarView delegate when a tab is dropped from another pane.
    func moveTab(from sourcePane: TabController, at sourceIndex: Int,
                 to destPane: TabController, at destIndex: Int) {
        guard let vc = sourcePane.removeTab(at: sourceIndex) else {
            unsplitPane(nil)
            return
        }
        destPane.insertTab(vc, at: destIndex)
        if let idx = panes.firstIndex(of: destPane) {
            setActivePane(idx)
        }
        snapshotRecovery()
    }

    /// Moves a tab from `sourcePane` to a new pane.
    /// When already at 2 panes, moves to the other existing pane instead.
    private func moveTabToNewPane(_ sourcePane: TabController, at tabIndex: Int) {
        if panes.count >= 2 {
            moveTabFromPane(sourcePane, at: tabIndex)
            return
        }
        guard let vc = sourcePane.removeTab(at: tabIndex) else {
            unsplitPane(nil)
            return
        }
        let newPane = makePane()
        newPane.restoreTabs(from: [], selectedIndex: 0)
        addPane(newPane)
        newPane.insertTab(vc, at: 0)
        setActivePane(panes.count - 1)
        updateActivePaneIndicators()
        snapshotRecovery()
    }

    // MARK: - Window sync

    func syncWindow() {
        activePane.syncWindow()
    }

    // MARK: - Recovery

    private func snapshotRecovery() {
        let paneEntries = panes.map { $0.buildRecoveryEntries() }
        RecoveryBuffer.saveSession(RecoverySession(
            panes: paneEntries,
            activePaneIndex: activePaneIndex,
            dividerFraction: currentDividerFraction
        ))
    }

    // MARK: - File opens (called by AppDelegate)

    func openFileInTab(at url: URL) {
        activePane.openFileInTab(at: url)
    }
}

// MARK: - Menu item validation

extension SplitController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(splitPane(_:)):
            return panes.count < 2
        case #selector(unsplitPane(_:)):
            return panes.count > 1
        case #selector(moveTabToOtherPane(_:)):
            return panes.count == 2
        default:
            return true
        }
    }
}

// MARK: - Responder chain helpers for TabController actions

extension SplitController {
    @objc func newTab(_ sender: Any? = nil) {
        activePane.newTab(sender)
    }

    @objc func closeTab(_ sender: Any? = nil) {
        activePane.closeTab(sender)
    }

    @objc func closeAllTabs(_ sender: Any? = nil) {
        activePane.closeAllTabs(sender)
    }
}
