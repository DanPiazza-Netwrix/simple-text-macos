import AppKit

final class EditorView: NSView {

    let scrollView  = NSScrollView()
    let textView    = NSTextView()
    let rulerView   = LineNumberRulerView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        setupTextView()
        setupScrollView()

        // Ruler is a plain sibling view — no NSScrollView ruler machinery,
        // so no built-in separator or divider lines are drawn.
        addSubview(rulerView)
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rulerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rulerView.topAnchor.constraint(equalTo: topAnchor),
            rulerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: rulerView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        rulerView.textView = textView
    }

    private func setupTextView() {
        let font = NSFont(name: "Monaco", size: 12)
               ?? NSFont(name: "Menlo", size: 13)
               ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        textView.font                              = font
        textView.isRichText                        = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled   = false
        textView.isContinuousSpellCheckingEnabled    = false
        textView.isGrammarCheckingEnabled            = false
        textView.allowsUndo                          = true
        textView.isVerticallyResizable               = true
        textView.isHorizontallyResizable             = false
        textView.usesFindBar                         = true
        textView.isIncrementalSearchingEnabled       = true
        textView.textContainerInset                  = NSSize(width: 4, height: 0)

        textView.backgroundColor     = .textBackgroundColor
        textView.textColor           = .labelColor
        textView.insertionPointColor = .labelColor

        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView  = true
        textView.textContainer?.containerSize        = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    private func setupScrollView() {
        scrollView.hasVerticalScroller    = true
        scrollView.hasHorizontalScroller  = false
        scrollView.autohidesScrollers     = true
        scrollView.borderType             = .noBorder
        scrollView.backgroundColor        = .textBackgroundColor
        scrollView.documentView           = textView
    }
}
