import AppKit

final class TabController: NSViewController {

    private let appearanceManager: AppearanceManager
    private var editorVCs: [EditorViewController] = []
    private var selectedIndex: Int = 0
    private var currentChildVC: EditorViewController?

    private let tabBar = TabBarView()
    private let editorContainer = NSView()

    // MARK: - Init

    init(appearanceManager: AppearanceManager, initialFileURL: URL? = nil) {
        self.appearanceManager = appearanceManager
        super.init(nibName: nil, bundle: nil)
        appendEditorVC(fileURL: initialFileURL, loadRecoveryBuffer: true)
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
        guard editorVCs.count > 1 else { view.window?.orderOut(nil); return }
        detachCurrent()
        editorVCs.remove(at: selectedIndex)
        selectedIndex = min(selectedIndex, editorVCs.count - 1)
        reloadTabBar()
        switchTo(index: selectedIndex)
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
        window.title = "\(filename) — v0.0.1.39"
        window.representedURL = vc.documentController.currentURL
        window.isDocumentEdited = vc.documentController.isModified
        reloadTabBar()
    }

    // MARK: - Private helpers

    private func appendEditorVC(fileURL: URL? = nil, loadRecoveryBuffer: Bool = false) {
        let vc = EditorViewController(
            appearanceManager: appearanceManager,
            initialFileURL: fileURL,
            loadRecoveryBuffer: loadRecoveryBuffer
        )
        vc.onStateChanged = { [weak self] in self?.syncWindow() }
        editorVCs.append(vc)
        selectedIndex = editorVCs.count - 1

        if isViewLoaded {
            reloadTabBar()
            switchTo(index: selectedIndex)
        }
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
    func tabBarDidClickNewTab(_ bar: TabBarView) { newTab() }

    func tabBar(_ bar: TabBarView, didSelectTabAt index: Int) {
        guard index != selectedIndex else { return }
        switchTo(index: index)
    }

    func tabBar(_ bar: TabBarView, didCloseTabAt index: Int) {
        guard editorVCs.count > 1 else { view.window?.orderOut(nil); return }
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
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
