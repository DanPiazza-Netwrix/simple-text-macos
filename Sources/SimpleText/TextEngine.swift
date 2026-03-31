// TextEngine.swift — Pure Swift/Foundation text logic. No AppKit import.
// Intentionally framework-free so it can be reused on Windows/Linux.

import Foundation

enum TextEngine {

    static func removeBlankLines(in text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }
}
