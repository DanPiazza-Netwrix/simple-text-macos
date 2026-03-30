import AppKit

final class LineNumberRulerView: NSView {

    // Use flipped coordinates so Y=0 is at the top, matching the scroll view content
    override var isFlipped: Bool { true }

    weak var textView: NSTextView? {
        didSet { observeTextView() }
    }

    private var observations: [NSObjectProtocol] = []
    private var widthConstraint: NSLayoutConstraint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 44)
        widthConstraint?.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        observations.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeTextView() {
        observations.forEach { NotificationCenter.default.removeObserver($0) }
        observations = []
        guard let tv = textView else { return }

        let nc = NotificationCenter.default
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }

        let clipView = tv.enclosingScrollView?.contentView
        observations = [
            nc.addObserver(forName: NSView.frameDidChangeNotification,
                           object: tv,       queue: .main, using: refresh),
            nc.addObserver(forName: NSView.boundsDidChangeNotification,
                           object: clipView, queue: .main, using: refresh),
            nc.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                           object: tv.textStorage, queue: .main, using: refresh),
        ]
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
              let scrollView = tv.enclosingScrollView else { return }

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let nsText = tv.string as NSString
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        // Auto-size width based on digit count
        let totalLines = nsText.components(separatedBy: "\n").count
        let digits = max(String(totalLines).count, 2)
        let needed = font.maximumAdvancement.width * CGFloat(digits) + 18
        if abs((widthConstraint?.constant ?? 44) - needed) > 0.5 {
            widthConstraint?.constant = needed
        }
        let w = widthConstraint?.constant ?? bounds.width

        let clipView = scrollView.contentView
        let visibleRect = tv.visibleRect

        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        guard glyphRange.length > 0 else { return }

        var lineNumbersDrawn = Set<Int>()
        var firstLineY: CGFloat?
        var firstLineNum: Int?
        var lineHeight: CGFloat = 0

        lm.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self]
            (fragmentRect, _, _, glyphRange, _) in
            guard let self = self else { return }

            let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            var lineNum = 1
            for i in 0..<charRange.location {
                if nsText.character(at: i) == 10 { lineNum += 1 }
            }

            guard !lineNumbersDrawn.contains(lineNum) else { return }
            lineNumbersDrawn.insert(lineNum)

            let textViewY = fragmentRect.midY
            let scrollViewY = textViewY + tv.textContainerOrigin.y
            let rulerY = scrollViewY - clipView.bounds.origin.y

            if firstLineY == nil {
                firstLineY = rulerY
                firstLineNum = lineNum
                lineHeight = fragmentRect.height
            }

            let label = "\(lineNum)" as NSString
            let size = label.size(withAttributes: attrs)

            if rulerY >= bounds.minY && rulerY <= bounds.maxY {
                label.draw(at: NSPoint(x: w - size.width - 6, y: rulerY - size.height / 2), withAttributes: attrs)
            }
        }

        if let firstLineY = firstLineY, let firstLineNum = firstLineNum, lineHeight > 0 {
            for lineNum in 1...totalLines {
                if !lineNumbersDrawn.contains(lineNum) {
                    let estimatedRulerY = firstLineY + CGFloat(lineNum - firstLineNum) * lineHeight
                    let label = "\(lineNum)" as NSString
                    let size = label.size(withAttributes: attrs)
                    if estimatedRulerY >= bounds.minY && estimatedRulerY <= bounds.maxY {
                        label.draw(at: NSPoint(x: w - size.width - 6, y: estimatedRulerY - size.height / 2), withAttributes: attrs)
                    }
                }
            }
        }
    }
}
