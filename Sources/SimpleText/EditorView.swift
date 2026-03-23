import AppKit

final class EditorView: NSView {

    let scrollView  = NSScrollView()
    let textView    = NSTextView()
    let rulerView   = LineNumberRulerView(scrollView: nil, orientation: .verticalRuler)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        setupTextView()
        setupScrollView()
        setupRuler()

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
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
        textView.textContainerInset                  = NSSize(width: 4, height: 6)

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

    private func setupRuler() {
        // NSRulerView requires the scroll view to be the owner
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler  = true
        scrollView.rulersVisible     = true

        rulerView.scrollView = scrollView
        rulerView.textView   = textView
    }
}
