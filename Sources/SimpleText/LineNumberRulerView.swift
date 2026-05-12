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
        // Update width and redisplay together — width must never be mutated inside draw()
        // because changing a constraint during draw triggers a layout pass that resizes
        // sibling views (scroll view → text view → text container), which can corrupt
        // NSTextView's cursor state mid-operation and cause phantom deletions.
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateWidthIfNeeded()
                self?.needsDisplay = true
            }
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

    /// Adjusts the ruler's width constraint to fit the current line-count digit count.
    /// Must be called outside of draw() — never mutate constraints inside a draw pass.
    private func updateWidthIfNeeded() {
        guard let tv = textView else { return }
        let totalLines = (tv.string as NSString).components(separatedBy: "\n").count
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .regular)
        let digits = max(String(totalLines).count, 2)
        let needed = font.maximumAdvancement.width * CGFloat(digits) + 18
        if abs((widthConstraint?.constant ?? 44) - needed) > 0.5 {
            widthConstraint?.constant = needed
        }
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

        // Width was already set by updateWidthIfNeeded() — do NOT mutate it here.
        let w = widthConstraint?.constant ?? bounds.width

        let clipView = scrollView.contentView
        let visibleRect = tv.visibleRect

        // Ensure layout is up-to-date before querying — without this,
        // AppKit's synchronous draw during live window resize can query
        // a stale layout and produce wrong/overlapping line numbers.
        lm.ensureLayout(for: tc)

        // Expand the query rect by a few points so the last partially-visible
        // line fragment is always included (glyphRange(forBoundingRect:) can
        // clip right at the boundary and miss the final line).
        let queryRect = visibleRect.insetBy(dx: 0, dy: -4)
        let glyphRange = lm.glyphRange(forBoundingRect: queryRect, in: tc)
        guard glyphRange.length > 0 else { return }

        var lineNumbersDrawn = Set<Int>()

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

            let label = "\(lineNum)" as NSString
            let size = label.size(withAttributes: attrs)

            if rulerY >= bounds.minY && rulerY <= bounds.maxY {
                label.draw(at: NSPoint(x: w - size.width - 6, y: rulerY - size.height / 2), withAttributes: attrs)
            }
        }
    }
}
