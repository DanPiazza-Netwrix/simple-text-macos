import AppKit

// MARK: - Pasteboard type for cross-pane tab dragging

extension NSPasteboard.PasteboardType {
    static let tabDrag = NSPasteboard.PasteboardType("com.simpletext.tab-drag")
}

// MARK: - Delegate

protocol TabBarDelegate: AnyObject {
    func tabBar(_ bar: TabBarView, didSelectTabAt index: Int)
    func tabBar(_ bar: TabBarView, didCloseTabAt index: Int)
    func tabBar(_ bar: TabBarView, didCloseTabsToRightOf index: Int)
    func tabBar(_ bar: TabBarView, didCloseOtherTabsThan index: Int)
    func tabBarDidCloseAllTabs(_ bar: TabBarView)
    func tabBar(_ bar: TabBarView, didMoveTabFrom fromIndex: Int, to toIndex: Int)
    func tabBar(_ bar: TabBarView, didRequestMoveToNewPaneAt index: Int)
    func tabBar(_ bar: TabBarView, didReceiveDropFromPaneId paneId: String, tabIndex: Int, atLocalIndex destIndex: Int)
}

// MARK: - TabBarView

final class TabBarView: NSView {

    static let height: CGFloat = 36

    weak var delegate: TabBarDelegate?
    private(set) var selectedIndex: Int = 0
    private(set) var buttons: [TabButton] = []

    /// Unique identifier for this tab bar's pane (used in cross-pane drag pasteboard data).
    let paneId = UUID().uuidString

    /// When true, draws a 2px accent line at the bottom to indicate the active pane.
    var isActivePane: Bool = false {
        didSet { needsDisplay = true }
    }

    /// When true, tab context menus show "Move to Other Pane".
    var isSplitActive: Bool = false

    // Drag state
    private var draggingIndex: Int?
    private var dropIndex:     Int = 0
    private var dragTabWidth:  CGFloat = 0

    // Cross-pane drop indicator
    private var crossPaneDropIndex: Int? {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.tabDrag])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - API

    func reloadTabs(titles: [String], modified: [Bool], selectedIndex: Int) {
        self.selectedIndex = selectedIndex
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []

        for i in 0 ..< titles.count {
            let btn = TabButton(title: titles[i], isModified: modified[i], isSelected: i == selectedIndex)
            let idx = i
            btn.onSelect       = { [weak self] in guard let s = self else { return }; s.delegate?.tabBar(s, didSelectTabAt: idx) }
            btn.onClose        = { [weak self] in guard let s = self else { return }; s.delegate?.tabBar(s, didCloseTabAt: idx) }
            if titles.count > 1 {
                btn.onCloseOthers = { [weak self] in guard let s = self else { return }; s.delegate?.tabBar(s, didCloseOtherTabsThan: idx) }
            }
            if i < titles.count - 1 {
                btn.onCloseToRight = { [weak self] in guard let s = self else { return }; s.delegate?.tabBar(s, didCloseTabsToRightOf: idx) }
            }
            btn.onCloseAll    = { [weak self] in guard let s = self else { return }; s.delegate?.tabBarDidCloseAllTabs(s) }
            btn.onMoveToNewPane = { [weak self] in guard let s = self else { return }; s.delegate?.tabBar(s, didRequestMoveToNewPaneAt: idx) }
            btn.onDragStarted = { [weak self] in self?.beginDrag(from: idx) }
            btn.onDragged     = { [weak self] x in self?.moveDrag(to: x) }
            btn.onDragEnded   = { [weak self] in self?.endDrag() }
            btn.parentTabBar  = self
            addSubview(btn)
            buttons.append(btn)
        }

        layoutContents()
        needsDisplay = true
    }

    // MARK: - Layout

    private static let tabMaxWidth: CGFloat = 240
    private static let tabMinWidth: CGFloat = 80
    private static let leftPad:     CGFloat = 8

    private func layoutContents() {
        let h = Self.height
        let n = buttons.count

        let available = max(0, bounds.width - Self.leftPad - 8)
        let tabW: CGFloat = n > 0
            ? min(Self.tabMaxWidth, max(Self.tabMinWidth, (available / CGFloat(n)).rounded(.down)))
            : Self.tabMaxWidth

        var x = Self.leftPad
        for btn in buttons {
            btn.frame = NSRect(x: x, y: 0, width: tabW, height: h)
            x += tabW
        }
    }

    override func resizeSubviews(withOldSize old: NSSize) {
        super.resizeSubviews(withOldSize: old)
        if draggingIndex == nil { layoutContents() }
    }

    // MARK: - Drag

    private func beginDrag(from index: Int) {
        guard index < buttons.count else { return }
        draggingIndex = index
        dropIndex     = index
        dragTabWidth  = buttons[index].frame.width
        // Bring dragged button to front of z-order
        addSubview(buttons[index])
        buttons[index].alphaValue = 0.85
    }

    private func moveDrag(to mouseX: CGFloat) {
        guard let fromIndex = draggingIndex, fromIndex < buttons.count else { return }
        let btn  = buttons[fromIndex]
        let tabW = dragTabWidth
        let n    = buttons.count

        // Clamp button position within the tab rail
        let minX = Self.leftPad
        let maxX = Self.leftPad + tabW * CGFloat(n - 1)
        let newX = max(minX, min(maxX, mouseX - tabW / 2))
        btn.frame.origin.x = newX

        // Compute insertion slot from button center
        let toIndex = max(0, min(n - 1, Int((newX + tabW / 2 - Self.leftPad) / tabW)))
        guard toIndex != dropIndex else { return }
        dropIndex = toIndex

        // Slide non-dragged buttons into their new positions
        var slot = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = false
            for (i, b) in buttons.enumerated() where i != fromIndex {
                if slot == toIndex { slot += 1 }
                b.animator().frame = NSRect(x: Self.leftPad + tabW * CGFloat(slot),
                                            y: 0, width: tabW, height: Self.height)
                slot += 1
            }
        }
    }

    private func endDrag() {
        guard let fromIndex = draggingIndex else { return }
        draggingIndex = nil
        if fromIndex < buttons.count { buttons[fromIndex].alphaValue = 1.0 }

        if fromIndex != dropIndex {
            delegate?.tabBar(self, didMoveTabFrom: fromIndex, to: dropIndex)
            // delegate calls reloadTabs which resets all frames
        } else {
            layoutContents()
        }
    }

    /// Cancels an in-progress drag without committing any reorder.
    /// Used when transitioning to a cross-pane NSDragging session so that
    /// the intra-pane visual state is reset without reshuffling editorVCs.
    func cancelDrag() {
        guard draggingIndex != nil else { return }
        draggingIndex = nil
        for btn in buttons { btn.alphaValue = 1.0 }
        layoutContents()
    }

    // MARK: - Cross-pane NSDragging destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(.tabDrag) == true,
              let data = sender.draggingPasteboard.data(forType: .tabDrag),
              let info = try? JSONDecoder().decode(TabDragInfo.self, from: data),
              info.sourcePaneId != paneId else { return [] }
        crossPaneDropIndex = dropIndexForDrag(sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(.tabDrag) == true else { return [] }
        crossPaneDropIndex = dropIndexForDrag(sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        crossPaneDropIndex = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { crossPaneDropIndex = nil }
        guard let data = sender.draggingPasteboard.data(forType: .tabDrag),
              let info = try? JSONDecoder().decode(TabDragInfo.self, from: data),
              info.sourcePaneId != paneId else { return false }
        let destIndex = dropIndexForDrag(sender)
        delegate?.tabBar(self, didReceiveDropFromPaneId: info.sourcePaneId, tabIndex: info.tabIndex, atLocalIndex: destIndex)
        return true
    }

    private func dropIndexForDrag(_ sender: NSDraggingInfo) -> Int {
        let pt = convert(sender.draggingLocation, from: nil)
        let n = buttons.count
        guard n > 0 else { return 0 }
        let tabW = buttons[0].frame.width
        return max(0, min(n, Int((pt.x - Self.leftPad + tabW / 2) / tabW)))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        // Active pane accent line
        if isActivePane {
            NSColor.controlAccentColor.setFill()
            NSRect(x: 0, y: bounds.maxY - 2, width: bounds.width, height: 2).fill()
        }

        // Cross-pane drop indicator
        if let dropIdx = crossPaneDropIndex {
            let n = buttons.count
            let tabW: CGFloat = n > 0 ? buttons[0].frame.width : Self.tabMaxWidth
            let x = Self.leftPad + tabW * CGFloat(dropIdx)
            NSColor.controlAccentColor.setFill()
            NSRect(x: x - 1, y: 4, width: 2, height: bounds.height - 8).fill()
        }
    }
}

// MARK: - TabButton

/// Pasteboard data for cross-pane tab drags.
struct TabDragInfo: Codable {
    var sourcePaneId: String
    var tabIndex: Int
}

final class TabButton: NSView {

    var onSelect:            (() -> Void)?
    var onClose:             (() -> Void)?
    var onCloseToRight:      (() -> Void)?
    var onCloseOthers:       (() -> Void)?
    var onCloseAll:          (() -> Void)?
    var onMoveToNewPane:     (() -> Void)?
    var onDragStarted:       (() -> Void)?
    var onDragged:           ((_ mouseX: CGFloat) -> Void)?
    var onDragEnded:         (() -> Void)?
    weak var parentTabBar:   TabBarView?

    private let label: NSTextField
    private var isSelected:   Bool
    private var isModified:   Bool
    private var tabHovered   = false
    private var closeHovered = false

    // Drag tracking
    private var dragStartPoint: NSPoint?
    private var isDragging = false

    // Layout constants
    private static let vInset:     CGFloat = 4
    private static let hInset:     CGFloat = 2
    private static let cornerR:    CGFloat = 6
    private static let hPad:       CGFloat = 10
    private static let closeSize:  CGFloat = 14
    private static let closeRight: CGFloat = 7
    private static let fontSize:   CGFloat = 11.5

    private var closeRect: NSRect {
        NSRect(
            x: bounds.maxX - Self.closeSize - Self.closeRight - Self.hInset,
            y: (bounds.height - Self.closeSize) / 2,
            width: Self.closeSize, height: Self.closeSize
        )
    }

    // MARK: - Init

    init(title: String, isModified: Bool, isSelected: Bool) {
        self.isSelected = isSelected
        self.isModified = isModified
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .systemFont(ofSize: Self.fontSize)
        label.lineBreakMode = .byTruncatingMiddle
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let h = newSize.height
        let cr = NSRect(
            x: newSize.width - Self.closeSize - Self.closeRight - Self.hInset,
            y: (h - Self.closeSize) / 2,
            width: Self.closeSize, height: Self.closeSize
        )
        let labelW = cr.minX - Self.hPad - Self.hInset - 2
        label.frame = NSRect(x: Self.hPad + Self.hInset, y: (h - 14) / 2, width: max(0, labelW), height: 14)
        refreshTracking()
    }

    // MARK: - Tracking

    private var tabTrack:   NSTrackingArea?
    private var closeTrack: NSTrackingArea?

    private func refreshTracking() {
        if let t = tabTrack   { removeTrackingArea(t) }
        if let t = closeTrack { removeTrackingArea(t) }
        guard !bounds.isEmpty else { return }
        tabTrack   = NSTrackingArea(rect: bounds,    options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: ["z": "tab"])
        closeTrack = NSTrackingArea(rect: closeRect, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: ["z": "x"])
        addTrackingArea(tabTrack!)
        addTrackingArea(closeTrack!)
    }

    override func mouseEntered(with event: NSEvent) {
        if (event.trackingArea?.userInfo?["z"] as? String) == "x" { closeHovered = true } else { tabHovered = true }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        if (event.trackingArea?.userInfo?["z"] as? String) == "x" { closeHovered = false } else { tabHovered = false; closeHovered = false }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        dragStartPoint = pt
        isDragging = false
        // Select immediately; close waits for mouseUp (so accidental drags don't close)
        if !closeRect.contains(pt) { onSelect?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartPoint else { return }
        let pt = convert(event.locationInWindow, from: nil)
        if !isDragging {
            guard abs(pt.x - start.x) > 4 else { return }
            isDragging = true
            onDragStarted?()
        }

        // Check if mouse has left the tab bar bounds — start cross-pane NSDragging session
        if let bar = parentTabBar {
            let mouseInBar = bar.convert(event.locationInWindow, from: nil)
            if !bar.bounds.contains(mouseInBar), !isCrossPaneDragging {
                startCrossPaneDrag(event: event)
                return
            }
        }

        let mouseX = superview?.convert(event.locationInWindow, from: nil).x ?? pt.x
        onDragged?(mouseX)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStartPoint = nil; isDragging = false; isCrossPaneDragging = false }
        if isDragging {
            onDragEnded?()
        } else if let start = dragStartPoint, closeRect.contains(start) {
            onClose?()
        }
    }

    // MARK: - Cross-pane drag (NSDragging source)

    private var isCrossPaneDragging = false

    private func startCrossPaneDrag(event: NSEvent) {
        guard let bar = parentTabBar,
              let idx = bar.buttons.firstIndex(of: self) else { return }
        isCrossPaneDragging = true

        // Cancel the intra-pane drag without committing any reorder.
        // Calling onDragEnded?() here would invoke endDrag(), which — if the tab
        // had moved to a different visual slot — would reorder editorVCs via the
        // delegate and then invalidate `idx`. cancelDrag() resets visual state only.
        bar.cancelDrag()

        let info = TabDragInfo(sourcePaneId: bar.paneId, tabIndex: idx)
        guard let data = try? JSONEncoder().encode(info) else { return }

        let pbItem = NSPasteboardItem()
        pbItem.setData(data, forType: .tabDrag)

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        dragItem.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func snapshot() -> NSImage {
        let img = NSImage(size: bounds.size)
        img.lockFocus()
        if let ctx = NSGraphicsContext.current {
            layer?.render(in: ctx.cgContext)
        }
        img.unlockFocus()
        return img
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let rightItem = menu.addItem(withTitle: "Close Tabs to the Right",
                                     action: #selector(handleCloseToRight),
                                     keyEquivalent: "")
        rightItem.target = self
        rightItem.isEnabled = onCloseToRight != nil

        let othersItem = menu.addItem(withTitle: "Close Other Tabs",
                                      action: #selector(handleCloseOthers),
                                      keyEquivalent: "")
        othersItem.target = self
        othersItem.isEnabled = onCloseOthers != nil

        menu.addItem(.separator())

        let allItem = menu.addItem(withTitle: "Close All Tabs",
                                   action: #selector(handleCloseAll),
                                   keyEquivalent: "")
        allItem.target = self
        allItem.isEnabled = true

        menu.addItem(.separator())

        if onMoveToNewPane != nil {
            let splitActive = parentTabBar?.isSplitActive ?? false
            let moveTitle = splitActive ? "Move to Other Pane" : "Move to New View"
            let moveNewItem = menu.addItem(withTitle: moveTitle,
                                           action: #selector(handleMoveToNewPane),
                                           keyEquivalent: "")
            moveNewItem.target = self
            moveNewItem.isEnabled = true
        }

        return menu
    }

    @objc private func handleCloseToRight()     { onCloseToRight?() }
    @objc private func handleCloseOthers()       { onCloseOthers?() }
    @objc private func handleCloseAll()          { onCloseAll?() }
    @objc private func handleMoveToNewPane()     { onMoveToNewPane?() }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let h = bounds.height

        let pillRect = NSRect(
            x: Self.hInset, y: Self.vInset,
            width: bounds.width - Self.hInset * 2,
            height: h - Self.vInset * 2
        )
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: Self.cornerR, yRadius: Self.cornerR)

        if isSelected {
            (dark ? NSColor(white: 0.26, alpha: 1) : NSColor(white: 0.88, alpha: 1)).setFill()
            pillPath.fill()
        } else if tabHovered {
            (dark ? NSColor(white: 0.20, alpha: 1) : NSColor(white: 0.80, alpha: 1)).setFill()
            pillPath.fill()
        }

        label.textColor = isSelected ? .labelColor : .secondaryLabelColor

        let showDot = isModified && !closeHovered
        let sym     = showDot ? "●" : "✕"
        let symPt: CGFloat = 9
        let symCol: NSColor = {
            if showDot      { return .systemOrange }
            if closeHovered { return .labelColor }
            return (isSelected || tabHovered) ? .secondaryLabelColor : NSColor.clear
        }()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: symPt, weight: .medium),
            .foregroundColor: symCol,
        ]
        let str = NSAttributedString(string: sym, attributes: attrs)
        let sz  = str.size()
        let cr  = closeRect
        str.draw(at: NSPoint(x: cr.midX - sz.width / 2, y: cr.midY - sz.height / 2))
    }
}

// MARK: - NSDraggingSource

extension TabButton: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
}
