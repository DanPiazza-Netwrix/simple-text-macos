import AppKit
import Neon
import SwiftTreeSitter

/// Manages Tree-sitter syntax highlighting for an NSTextView using Neon.
/// Each tab that opens a recognized file type gets its own coordinator.
/// Markdown is handled separately by SyntaxHighlighter (regex-based).
@MainActor
final class HighlightCoordinator {

    private let highlighter: TextViewHighlighter

    /// - Parameters:
    ///   - textView: The text view to highlight.
    ///   - languageConfig: A LanguageConfiguration from LanguageRegistry.
    init(textView: NSTextView, languageConfig: LanguageConfiguration) throws {
        let config = TextViewHighlighter.Configuration(
            languageConfiguration: languageConfig,
            attributeProvider: { token in
                highlightAttributes(for: token.name)
            },
            languageProvider: { _ in nil },
            locationTransformer: { _ in nil }
        )
        self.highlighter = try TextViewHighlighter(textView: textView, configuration: config)
    }

    /// Call after the text view's enclosing scroll view is in the window hierarchy
    /// so Neon can observe scroll position for incremental visible-range highlighting.
    func observeScrollView() {
        highlighter.observeEnclosingScrollView()
    }
}
