import Foundation
import SwiftTreeSitter

// Grammar imports — one per language
import TreeSitterJSON
import TreeSitterPython
import TreeSitterSwift
import TreeSitterJavaScript
import TreeSitterTypeScript
import TreeSitterTSX
import TreeSitterGo
import TreeSitterRust
import TreeSitterBash
import TreeSitterHTML
import TreeSitterCSS
import TreeSitterJava
import TreeSitterRuby
import TreeSitterYAML
import TreeSitterPowershell

/// Maps file extensions to Tree-sitter LanguageConfiguration objects.
/// Configurations are created lazily on first use and then cached.
final class LanguageRegistry {

    static let shared = LanguageRegistry()
    private init() {}

    private var cache: [String: LanguageConfiguration] = [:]

    // MARK: - Extension → language name

    private static let extensionMap: [String: String] = [
        // Swift
        "swift": "Swift",
        // Python
        "py": "Python", "pyw": "Python",
        // JavaScript
        "js": "JavaScript", "mjs": "JavaScript", "cjs": "JavaScript",
        // TypeScript
        "ts": "TypeScript", "tsx": "TSX",
        // JSON
        "json": "JSON", "jsonc": "JSON",
        // HTML
        "html": "HTML", "htm": "HTML",
        // CSS
        "css": "CSS",
        // Bash / shell
        "sh": "Bash", "bash": "Bash", "zsh": "Bash",
        // Go
        "go": "Go",
        // Rust
        "rs": "Rust",
        // Java
        "java": "Java",
        // Ruby
        "rb": "Ruby",
        // YAML
        "yaml": "YAML", "yml": "YAML",
        // PowerShell
        "ps1": "PowerShell", "psm1": "PowerShell", "psd1": "PowerShell",
    ]

    // MARK: - Public API

    /// Returns a cached (or freshly created) LanguageConfiguration for the given file URL,
    /// or nil if the extension is unrecognized or the grammar fails to load.
    func configuration(for url: URL) -> LanguageConfiguration? {
        let ext = url.pathExtension.lowercased()
        guard let langName = Self.extensionMap[ext] else { return nil }
        if let cached = cache[langName] { return cached }
        let config = makeConfiguration(for: langName)
        cache[langName] = config   // cache even if nil to avoid retrying a failed load
        return config
    }

    // MARK: - Grammar construction

    private func makeConfiguration(for language: String) -> LanguageConfiguration? {
        do {
            switch language {
            case "Swift":       return try LanguageConfiguration(tree_sitter_swift(),       name: "Swift")
            case "Python":      return try LanguageConfiguration(tree_sitter_python(),      name: "Python")
            case "JavaScript":  return try LanguageConfiguration(tree_sitter_javascript(),  name: "JavaScript")
            case "TypeScript":  return try LanguageConfiguration(tree_sitter_typescript(),  name: "TypeScript")
            case "TSX":         return try LanguageConfiguration(tree_sitter_tsx(),         name: "TSX",        bundleName: "TreeSitterTypeScript_TreeSitterTSX")
            case "JSON":        return try LanguageConfiguration(tree_sitter_json(),        name: "JSON")
            case "HTML":        return try LanguageConfiguration(tree_sitter_html(),        name: "HTML")
            case "CSS":         return try LanguageConfiguration(tree_sitter_css(),         name: "CSS")
            case "Bash":        return try LanguageConfiguration(tree_sitter_bash(),        name: "Bash")
            case "Go":          return try LanguageConfiguration(tree_sitter_go(),          name: "Go")
            case "Rust":        return try LanguageConfiguration(tree_sitter_rust(),        name: "Rust")
            case "Java":        return try LanguageConfiguration(tree_sitter_java(),        name: "Java")
            case "Ruby":        return try LanguageConfiguration(tree_sitter_ruby(),        name: "Ruby")
            case "YAML":        return try LanguageConfiguration(tree_sitter_yaml(),        name: "YAML")
            case "PowerShell":  return try LanguageConfiguration(tree_sitter_powershell(),  name: "Powershell", bundleName: "SimpleText_TreeSitterPowershell")
            default:            return nil
            }
        } catch {
            return nil
        }
    }
}
