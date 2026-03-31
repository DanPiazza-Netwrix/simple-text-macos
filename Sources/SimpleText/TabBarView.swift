import AppKit

// MARK: - Delegate

protocol TabBarDelegate: AnyObject {
    func tabBar(_ bar: TabBarView, didSelectTabAt index: Int)
    func tabBar(_ bar: TabBarView, didCloseTabAt index: Int)
    func tabBar(_ bar: TabBarView, didCloseTabsToRightOf index: Int)
    func tabBar(_ bar: TabBarView, didCloseOtherTabsThan index: Int)
    func tabBar(_ bar: TabBarView, didMoveTabFrom fromIndex: Int, to toIndex: Int)
}

// MARK: - TabBarView

final class TabBarView: NSView {

    static let height: CGFloat = 36

    weak var delegate: TabBarDelegate?
    private(set) var selectedIndex: Int = 0
    private var buttons: [TabButton] = []

    // Drag state
    private var draggingIndex: Int?
    private var dropIndex:     Int = 0
    private var dragTabWidth:  CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
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
            btn.onDragStarted = { [weak self] in self?.beginDrag(from: idx) }
            btn.onDragged     = { [weak self] x in self?.moveDrag(to: x) }
            btn.onDragEnded   = { [weak self] in self?.endDrag() }
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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

// MARK: - TabButton

final class TabButton: NSView {

    var onSelect:       (() -> Void)?
    var onClose:        (() -> Void)?
    var onCloseToRight: (() -> Void)?
    var onCloseOthers:  (() -> Void)?
    var onDragStarted:  (() -> Void)?
    var onDragged:      ((_ mouseX: CGFloat) -> Void)?
    var onDragEnded:    (() -> Void)?

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
        let mouseX = superview?.convert(event.locationInWindow, from: nil).x ?? pt.x
        onDragged?(mouseX)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStartPoint = nil; isDragging = false }
        if isDragging {
            onDragEnded?()
        } else if let start = dragStartPoint, closeRect.contains(start) {
            onClose?()
        }
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
        return menu
    }

    @objc private func handleCloseToRight() { onCloseToRight?() }
    @objc private func handleCloseOthers()  { onCloseOthers?() }

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
