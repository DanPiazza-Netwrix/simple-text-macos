import AppKit

// MARK: - VS Code–matched colors (Dark+ / Light+)
// These are intentional hardcoded values — they mirror VS Code's default theme exactly.
// Dynamic providers switch between the dark and light palette based on effective appearance.

private func vscodeColor(dark: UInt32, light: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = isDark ? dark : light
        return NSColor(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >>  8) & 0xFF) / 255,
            blue:  CGFloat( hex        & 0xFF) / 255,
            alpha: 1
        )
    }
}

private let vsHeading  = vscodeColor(dark: 0x569cd6, light: 0x800000)  // blue  / maroon
private let vsCode     = vscodeColor(dark: 0xce9178, light: 0xa31515)  // salmon / dark-red
private let vsLinkText = vscodeColor(dark: 0x569cd6, light: 0x0070c1)  // blue  / VS blue
private let vsLinkURL  = vscodeColor(dark: 0xce9178, light: 0xa31515)  // same as code

/// Applies Markdown syntax highlighting to an NSTextView via NSTextStorageDelegate.
/// Uses NSLayoutManager temporary attributes — these are purely visual overlays that
/// are never tracked by the undo manager and never saved to file.
/// Only active for .md / .markdown files — lifecycle managed by EditorViewController.
final class SyntaxHighlighter: NSObject, NSTextStorageDelegate {

    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init()
    }

    /// Call once after setting textView.string on initial file load.
    /// (didProcessEditing only fires on edits, not on programmatic string assignment.)
    func highlightAll() {
        guard let tv = textView,
              let ts = tv.textStorage,
              let lm = tv.layoutManager else { return }
        applyHighlighting(string: ts.string, layoutManager: lm, font: tv.font)
    }

    // MARK: - NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        // Only re-highlight when actual characters changed.
        guard editedMask.contains(.editedCharacters) else { return }
        guard let tv = textView,
              let lm = tv.layoutManager else { return }
        applyHighlighting(string: textStorage.string, layoutManager: lm, font: tv.font)
    }

    // MARK: - Core

    private func applyHighlighting(string str: String, layoutManager lm: NSLayoutManager, font: NSFont?) {
        guard let font else { return }
        let full = NSRange(location: 0, length: (str as NSString).length)
        guard full.length > 0 else { return }

        // 1. Reset all temporary attributes over the full range.
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.font,            forCharacterRange: full)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: full)

        let mono   = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        let codeBg = NSColor.secondaryLabelColor.withAlphaComponent(0.08)

        // 2. Fenced code blocks  (``` … ```)  — applied first so later inline
        //    passes don't re-color content inside a code block.
        Self.reFencedCode.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0 else { return }
            lm.addTemporaryAttributes([.font: mono,
                                       .foregroundColor: vsCode,
                                       .backgroundColor: codeBg], forCharacterRange: r)
        }

        // 3. Block-level patterns
        Self.reHeading.enumerateMatches(in: str, range: full) { [weak self] m, _, _ in
            guard let self, let r = m?.range, r.length > 0 else { return }
            lm.addTemporaryAttributes([.foregroundColor: vsHeading,
                                       .font: self.withTrait(.bold, base: font)], forCharacterRange: r)
        }

        Self.reBlockquote.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0 else { return }
            lm.addTemporaryAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, forCharacterRange: r)
        }

        Self.reHRule.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0 else { return }
            lm.addTemporaryAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, forCharacterRange: r)
        }

        // 4. Inline patterns (bold+italic before bold/italic so *** matches first)
        Self.reBoldItalic.enumerateMatches(in: str, range: full) { [weak self] m, _, _ in
            guard let self, let r = m?.range, r.length > 0 else { return }
            lm.addTemporaryAttribute(.font, value: withTrait([.bold, .italic], base: font), forCharacterRange: r)
        }

        Self.reBold.enumerateMatches(in: str, range: full) { [weak self] m, _, _ in
            guard let self, let r = m?.range, r.length > 0 else { return }
            lm.addTemporaryAttribute(.font, value: withTrait(.bold, base: font), forCharacterRange: r)
        }

        Self.reItalic.enumerateMatches(in: str, range: full) { [weak self] m, _, _ in
            guard let self, let r = m?.range, r.length > 0 else { return }
            lm.addTemporaryAttribute(.font, value: withTrait(.italic, base: font), forCharacterRange: r)
        }

        Self.reInlineCode.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0 else { return }
            lm.addTemporaryAttributes([.font: mono,
                                       .foregroundColor: vsCode,
                                       .backgroundColor: codeBg], forCharacterRange: r)
        }

        Self.reStrikethrough.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0 else { return }
            lm.addTemporaryAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                                       .strikethroughStyle: NSUnderlineStyle.single.rawValue], forCharacterRange: r)
        }

        // Links: [text] and (url) colored per VS Code
        Self.reLink.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let match = m, match.numberOfRanges == 3 else { return }
            let textRange = match.range(at: 1)
            let urlRange  = match.range(at: 2)
            if textRange.location != NSNotFound {
                lm.addTemporaryAttribute(.foregroundColor, value: vsLinkText, forCharacterRange: textRange)
            }
            if urlRange.location != NSNotFound {
                lm.addTemporaryAttribute(.foregroundColor, value: vsLinkURL, forCharacterRange: urlRange)
            }
        }
    }

    // MARK: - Font helpers

    private func withTrait(_ traits: NSFontDescriptor.SymbolicTraits, base: NSFont) -> NSFont {
        // withSymbolicTraits is non-optional on macOS (unlike iOS)
        let desc = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: desc, size: base.pointSize) ?? base
    }

    // MARK: - Pre-compiled patterns

    private static let reFencedCode    = re("```[\\s\\S]*?```",           .dotMatchesLineSeparators)
    private static let reHeading       = re("^#{1,6}\\s.+$",              .anchorsMatchLines)
    private static let reBlockquote    = re("^>[ \\t]?.+$",               .anchorsMatchLines)
    private static let reHRule         = re("^([-*_] *){3,}$",            .anchorsMatchLines)
    private static let reBoldItalic    = re("(\\*{3}|_{3}).+?\\1")
    private static let reBold          = re("(\\*{2}|_{2}).+?\\1")
    private static let reItalic        = re("(?<![*_])([*_])(?!\\s).+?(?<!\\s)\\1(?![*_])")
    private static let reInlineCode    = re("`[^`\\n]+`")
    private static let reStrikethrough = re("~~.+?~~")
    private static let reLink          = re("\\[([^\\]]+)\\]\\(([^)]+)\\)")

    private static func re(_ pattern: String,
                           _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are literals written by us, safe to force-unwrap.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: options)
    }
}
