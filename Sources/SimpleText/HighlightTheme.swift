import AppKit

// MARK: - VS Code Dark+ / Light+ colors for tree-sitter captures
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

private let vsKeyword    = vscodeColor(dark: 0x569CD6, light: 0x0000FF)
private let vsString     = vscodeColor(dark: 0xCE9178, light: 0xA31515)
private let vsComment    = vscodeColor(dark: 0x6A9955, light: 0x008000)
private let vsFunction   = vscodeColor(dark: 0xDCDCAA, light: 0x795E26)
private let vsType       = vscodeColor(dark: 0x4EC9B0, light: 0x267F99)
private let vsVariable   = vscodeColor(dark: 0x9CDCFE, light: 0x001080)
private let vsNumber     = vscodeColor(dark: 0xB5CEA8, light: 0x098658)
private let vsConstant   = vscodeColor(dark: 0x4FC1FF, light: 0x0070C1)
private let vsProperty   = vscodeColor(dark: 0x9CDCFE, light: 0x001080)
private let vsTag        = vscodeColor(dark: 0x569CD6, light: 0x800000)
private let vsEscape     = vscodeColor(dark: 0xD7BA7D, light: 0xFF0000)
private let vsAttribute  = vscodeColor(dark: 0x9CDCFE, light: 0x9CDCFE)

/// Maps a tree-sitter highlight capture name to NSAttributedString attributes.
/// Uses prefix matching so sub-scopes like "keyword.control" match "keyword".
func highlightAttributes(for tokenName: String) -> [NSAttributedString.Key: Any] {
    let base = tokenName.split(separator: ".").first.map(String.init) ?? tokenName
    switch base {
    case "keyword":     return [.foregroundColor: vsKeyword]
    case "string":      return [.foregroundColor: vsString]
    case "comment":     return [.foregroundColor: vsComment]
    case "function":    return [.foregroundColor: vsFunction]
    case "method":      return [.foregroundColor: vsFunction]
    case "type":        return [.foregroundColor: vsType]
    case "class":       return [.foregroundColor: vsType]
    case "struct":      return [.foregroundColor: vsType]
    case "interface":   return [.foregroundColor: vsType]
    case "namespace":   return [.foregroundColor: vsType]
    case "module":      return [.foregroundColor: vsType]
    case "constructor": return [.foregroundColor: vsType]
    case "variable":    return [.foregroundColor: vsVariable]
    case "parameter":   return [.foregroundColor: vsVariable]
    case "label":       return [.foregroundColor: vsVariable]
    case "number":      return [.foregroundColor: vsNumber]
    case "float":       return [.foregroundColor: vsNumber]
    case "constant":    return [.foregroundColor: vsConstant]
    case "boolean":     return [.foregroundColor: vsConstant]
    case "null":        return [.foregroundColor: vsConstant]
    case "property":    return [.foregroundColor: vsProperty]
    case "field":       return [.foregroundColor: vsProperty]
    case "attribute":   return [.foregroundColor: vsAttribute]
    case "tag":         return [.foregroundColor: vsTag]
    case "escape":      return [.foregroundColor: vsEscape]
    case "include":     return [.foregroundColor: vsKeyword]
    case "import":      return [.foregroundColor: vsKeyword]
    case "operator":    return [.foregroundColor: NSColor.labelColor]
    default:            return [:]
    }
}
