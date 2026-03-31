import AppKit

// NSTextView intercepts file-URL drags and inserts the path as text by default.
// This subclass redirects file drops to the onFilesDropped handler instead.
final class EditorTextView: NSTextView {
    var onFilesDropped: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(sender) { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(sender) { return .copy }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        if !urls.isEmpty {
            onFilesDropped?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true])
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
         options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}

final class EditorView: NSView {

    let scrollView: NSScrollView = NSScrollView()
    let textView:   NSTextView   = EditorTextView()
    let rulerView   = LineNumberRulerView()

    var onFilesDropped: (([URL]) -> Void)? {
        didSet { (textView as? EditorTextView)?.onFilesDropped = onFilesDropped }
    }

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
