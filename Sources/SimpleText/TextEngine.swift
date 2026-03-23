// TextEngine.swift — Pure Swift/Foundation text logic. No AppKit import.
// Intentionally framework-free so it can be reused on Windows/Linux.

import Foundation

enum TextEngine {

    static func removeBlankLines(in text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    /// Returns the 1-based (line, column) for a UTF-16 offset (as used by NSRange/NSTextView).
    static func position(in text: String, at utf16Offset: Int) -> (line: Int, column: Int) {
        let ns = text as NSString
        let safeOffset = max(0, min(utf16Offset, ns.length))
        let prefix = ns.substring(to: safeOffset)
        let lines = prefix.components(separatedBy: "\n")
        return (lines.count, (lines.last?.count ?? 0) + 1)
    }

    static func lineCount(in text: String) -> Int {
        (text as NSString).components(separatedBy: "\n").count
    }
}
