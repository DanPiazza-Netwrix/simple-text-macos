import AppKit

// MARK: - Delegate

protocol TabBarDelegate: AnyObject {
    func tabBar(_ bar: TabBarView, didSelectTabAt index: Int)
    func tabBar(_ bar: TabBarView, didCloseTabAt index: Int)
    func tabBarDidClickNewTab(_ bar: TabBarView)
}

// MARK: - TabBarView

final class TabBarView: NSView {

    static let height: CGFloat = 36

    weak var delegate: TabBarDelegate?
    private(set) var selectedIndex: Int = 0
    private var buttons: [TabButton] = []
    private let addButton = AddTabButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addButton.onTap = { [weak self] in
            guard let self else { return }
            self.delegate?.tabBarDidClickNewTab(self)
        }
        addSubview(addButton)
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
            btn.onSelect = { [weak self] in guard let s = self else { return }; s.delegate?.tabBar(s, didSelectTabAt: idx) }
            btn.onClose  = { [weak self] in guard let s = self else { return }; s.delegate?.tabBar(s, didCloseTabAt: idx) }
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
    private static let addBtnSize:  CGFloat = 22
    private static let addBtnGap:   CGFloat = 8   // gap between last tab and + button

    private func layoutContents() {
        let h    = Self.height
        let n    = buttons.count
        let btnS = Self.addBtnSize

        // Available width for tabs: full width minus left pad, + button, and its gap
        let reserved = Self.leftPad + Self.addBtnGap + btnS + 8
        let available = max(0, bounds.width - reserved)

        // Chrome rule: divide available space equally, clamped to [min, max]
        let tabW: CGFloat = n > 0
            ? min(Self.tabMaxWidth, max(Self.tabMinWidth, (available / CGFloat(n)).rounded(.down)))
            : Self.tabMaxWidth

        var x = Self.leftPad
        for btn in buttons {
            btn.frame = NSRect(x: x, y: 0, width: tabW, height: h)
            x += tabW   // no gap between tabs — Chrome style
        }

        addButton.frame = NSRect(
            x: x + Self.addBtnGap,
            y: (h - btnS) / 2,
            width: btnS, height: btnS
        )
    }

    override func resizeSubviews(withOldSize old: NSSize) {
        super.resizeSubviews(withOldSize: old)
        layoutContents()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

// MARK: - TabButton

final class TabButton: NSView {

    var onSelect: (() -> Void)?
    var onClose:  (() -> Void)?

    private let label: NSTextField
    private var isSelected:   Bool
    private var isModified:   Bool
    private var tabHovered   = false
    private var closeHovered = false

    // Layout constants
    private static let vInset:     CGFloat = 4     // top/bottom inset for pill rect
    private static let hInset:     CGFloat = 2     // left/right inset for pill rect
    private static let cornerR:    CGFloat = 6
    private static let hPad:       CGFloat = 10    // text left padding inside pill
    private static let closeSize:  CGFloat = 14
    private static let closeRight: CGFloat = 7
    private static let fontSize:   CGFloat = 11.5

    var preferredWidth: CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: Self.fontSize)]
        let tw = (label.stringValue as NSString).size(withAttributes: attrs).width
        return max(80, min(220, (Self.hPad + tw + 4 + Self.closeSize + Self.closeRight + Self.hInset * 2).rounded(.up)))
    }

    // Close icon rect in the button's local (non-flipped) coordinate space
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
        label.font = .systemFont(ofSize: Self.fontSize)
        label.lineBreakMode = .byTruncatingMiddle
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout (called when frame is set from outside)

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
        if closeRect.contains(pt) { onClose?() } else { onSelect?() }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let h = bounds.height

        // Pill background
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
        // Inactive tabs: no background drawn — title floats on bar

        // Label color
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor

        // Close (✕) / modified (●) indicator
        let showDot = isModified && !closeHovered
        let sym     = showDot ? "●" : "✕"
        let symPt: CGFloat = 9
        let symCol: NSColor = {
            if showDot      { return .systemOrange }
            if closeHovered { return .labelColor }
            // Only show ✕ dimly when selected or hovered; invisible on plain inactive tabs
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

// MARK: - AddTabButton

final class AddTabButton: NSView {

    var onTap: (() -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let t = tracking { removeTrackingArea(t) }
        guard newSize.width > 0 && newSize.height > 0 else { return }
        tracking = NSTrackingArea(rect: NSRect(origin: .zero, size: newSize), options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(tracking!)
    }

    override func mouseEntered(with event: NSEvent) { hovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { onTap?() }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if hovered {
            (dark ? NSColor(white: 0.26, alpha: 1) : NSColor(white: 0.80, alpha: 1)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .light),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let str = NSAttributedString(string: "+", attributes: attrs)
        let sz  = str.size()
        str.draw(at: NSPoint(x: bounds.midX - sz.width / 2, y: bounds.midY - sz.height / 2))
    }
}
