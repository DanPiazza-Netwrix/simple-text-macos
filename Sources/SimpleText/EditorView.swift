import AppKit

// NSTextView intercepts file-URL drags and inserts the path as text by default.
// This subclass redirects file drops to the onFilesDropped handler instead.
final class EditorTextView: NSTextView {
    var onFilesDropped: (([URL]) -> Void)?
    var onContextMenu: ((NSMenu) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            NotificationCenter.default.post(name: .simpleTextEditorDidBecomeActive, object: self)
        }
        return result
    }

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

    // MARK: - Bulk indent / dedent

    // MARK: - Context menu for split/close pane

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        onContextMenu?(menu)
        return menu
    }

    // MARK: - Bulk indent / dedent

    override func keyDown(with event: NSEvent) {
        let isTab   = event.keyCode == 48  // kVK_Tab
        let isShift = event.modifierFlags.contains(.shift)

        if isTab && isShift {
            dedentSelectedLines()
            return
        }

        if isTab {
            let sel = selectedRange()
            if sel.length > 0 && (string as NSString).substring(with: sel).contains("\n") {
                indentSelectedLines()
                return
            }
        }

        super.keyDown(with: event)
    }

    private func indentSelectedLines() {
        let sel      = selectedRange()
        let nsStr    = string as NSString
        let lineRange = nsStr.lineRange(for: sel)
        let linesText = nsStr.substring(with: lineRange)
        let lines     = linesText.components(separatedBy: "\n")
        let newText   = lines.enumerated().map { i, line in
            // Don't indent the empty sentinel after a trailing newline.
            (i == lines.count - 1 && line.isEmpty) ? line : "\t" + line
        }.joined(separator: "\n")
        insertText(newText, replacementRange: lineRange)
        undoManager?.setActionName("Indent")
        setSelectedRange(NSRange(location: lineRange.location,
                                 length: (newText as NSString).length))
    }

    private func dedentSelectedLines() {
        let sel       = selectedRange()
        let nsStr     = string as NSString
        let lineRange = nsStr.lineRange(for: sel)
        let linesText = nsStr.substring(with: lineRange)
        let lines     = linesText.components(separatedBy: "\n")
        let newLines  = lines.enumerated().map { i, line -> String in
            // Don't touch the empty sentinel after a trailing newline.
            if i == lines.count - 1 && line.isEmpty { return line }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            // Fall back: strip up to 4 leading spaces.
            var spaces = 0
            for ch in line { if ch == " " && spaces < 4 { spaces += 1 } else { break } }
            return spaces > 0 ? String(line.dropFirst(spaces)) : line
        }
        let newText = newLines.joined(separator: "\n")
        guard newText != linesText else { return }
        insertText(newText, replacementRange: lineRange)
        undoManager?.setActionName("Dedent")
        setSelectedRange(NSRange(location: lineRange.location,
                                 length: (newText as NSString).length))
    }
}

final class StatusBarView: NSView {

    let versionLabel: NSTextField = {
        let f = NSTextField(labelWithString: "")
        f.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        f.textColor = .secondaryLabelColor
        f.alignment = .left
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()

    let label: NSTextField = {
        let f = NSTextField(labelWithString: "Line 1, Col 1  |  0 words  0 chars")
        f.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        f.textColor = .secondaryLabelColor
        f.alignment = .right
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()

    private let separator: NSBox = {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    var showVersion: Bool = false {
        didSet { updateLayout() }
    }

    private var versionLabelLeadingConstraint: NSLayoutConstraint!
    private var labelLeadingWithVersionConstraint: NSLayoutConstraint!
    private var labelLeadingAloneConstraint: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(separator)
        addSubview(versionLabel)
        addSubview(label)

        versionLabelLeadingConstraint = versionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        labelLeadingWithVersionConstraint = label.leadingAnchor.constraint(equalTo: versionLabel.trailingAnchor, constant: 8)
        labelLeadingAloneConstraint = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),

            versionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateLayout() {
        if showVersion {
            versionLabel.isHidden = false
            labelLeadingAloneConstraint.isActive = false
            versionLabelLeadingConstraint.isActive = true
            labelLeadingWithVersionConstraint.isActive = true
        } else {
            versionLabel.isHidden = true
            labelLeadingWithVersionConstraint.isActive = false
            versionLabelLeadingConstraint.isActive = false
            labelLeadingAloneConstraint.isActive = true
        }
    }
}

final class EditorView: NSView {

    let scrollView:  NSScrollView = NSScrollView()
    let textView:    NSTextView   = EditorTextView()
    let rulerView    = LineNumberRulerView()
    let statusBar    = StatusBarView()

    var onFilesDropped: (([URL]) -> Void)? {
        didSet { (textView as? EditorTextView)?.onFilesDropped = onFilesDropped }
    }

    var onContextMenu: ((NSMenu) -> Void)? {
        didSet { (textView as? EditorTextView)?.onContextMenu = onContextMenu }
    }

    var showVersionInStatusBar: Bool = false {
        didSet {
            statusBar.showVersion = showVersionInStatusBar
            if showVersionInStatusBar, statusBar.versionLabel.stringValue.isEmpty {
                if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    statusBar.versionLabel.stringValue = "v\(v)"
                }
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateStatus(line: Int, col: Int, words: Int, chars: Int) {
        statusBar.label.stringValue = "Line \(line), Col \(col)  |  \(words) words  \(chars) chars"
    }

    // MARK: - Setup

    private func setup() {
        setupTextView()
        setupScrollView()

        // Ruler is a plain sibling view — no NSScrollView ruler machinery,
        // so no built-in separator or divider lines are drawn.
        addSubview(rulerView)
        addSubview(scrollView)
        addSubview(statusBar)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rulerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rulerView.topAnchor.constraint(equalTo: topAnchor),
            rulerView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            scrollView.leadingAnchor.constraint(equalTo: rulerView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),
        ])

        rulerView.textView = textView
    }

    private func setupTextView() {
        let savedSize = UserDefaults.standard.double(forKey: "fontSize")
        let fontSize: CGFloat = savedSize > 0 ? savedSize : 12
        let font = NSFont(name: "Monaco", size: fontSize)
               ?? NSFont(name: "Menlo", size: fontSize)
               ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

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

// MARK: - Notification name for active pane tracking

extension Notification.Name {
    static let simpleTextEditorDidBecomeActive = Notification.Name("SimpleTextEditorDidBecomeActive")
}
