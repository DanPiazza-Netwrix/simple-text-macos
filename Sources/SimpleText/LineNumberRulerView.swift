import AppKit

final class LineNumberRulerView: NSRulerView {

    weak var textView: NSTextView? {
        didSet { observeTextView() }
    }

    private var observations: [NSObjectProtocol] = []

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError() }

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

    override func drawHashMarksAndLabels(in rect: NSRect) {
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

        // Auto-size based on digit count
        let totalLines = nsText.components(separatedBy: "\n").count
        let digits = max(String(totalLines).count, 2)
        let needed = font.maximumAdvancement.width * CGFloat(digits) + 18
        if abs(ruleThickness - needed) > 0.5 { ruleThickness = needed }

        let clipView = scrollView.contentView
        let visibleRect = tv.visibleRect

        // Get glyph range for visible area
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

            // Count newlines before this character to get line number
            var lineNum = 1
            for i in 0..<charRange.location {
                if nsText.character(at: i) == 10 { lineNum += 1 }
            }

            // Skip if we already drew this line
            guard !lineNumbersDrawn.contains(lineNum) else { return }
            lineNumbersDrawn.insert(lineNum)

            // Convert Y coordinate
            let textViewY = fragmentRect.midY
            let scrollViewY = textViewY + tv.textContainerOrigin.y
            let rulerY = scrollViewY - clipView.bounds.origin.y

            // Track first visible line for calculating empty line positions
            if firstLineY == nil {
                firstLineY = rulerY
                firstLineNum = lineNum
                lineHeight = fragmentRect.height
            }

            let label = "\(lineNum)" as NSString
            let size = label.size(withAttributes: attrs)

            if rulerY >= bounds.minY && rulerY <= bounds.maxY {
                label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: rulerY - size.height / 2), withAttributes: attrs)
            }
        }

        // Draw line numbers for empty lines that weren't enumerated
        if let firstLineY = firstLineY, let firstLineNum = firstLineNum, lineHeight > 0 {
            for lineNum in 1...totalLines {
                if !lineNumbersDrawn.contains(lineNum) {
                    // Estimate Y position based on line height
                    let estimatedRulerY = firstLineY + CGFloat(lineNum - firstLineNum) * lineHeight

                    let label = "\(lineNum)" as NSString
                    let size = label.size(withAttributes: attrs)

                    if estimatedRulerY >= bounds.minY && estimatedRulerY <= bounds.maxY {
                        label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: estimatedRulerY - size.height / 2), withAttributes: attrs)
                    }
                }
            }
        }

    }
}
