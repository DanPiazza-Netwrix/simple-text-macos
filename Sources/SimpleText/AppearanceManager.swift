import AppKit

final class AppearanceManager {

    enum Mode {
        case system, dark, light

        var toggled: Mode {
            switch self {
            case .system, .light: return .dark
            case .dark:           return .light
            }
        }

        var menuTitle: String {
            switch self {
            case .system, .light: return "Use Dark Mode"
            case .dark:           return "Use Light Mode"
            }
        }
    }

    private static let defaultsKey = "appearanceMode"

    private(set) var mode: Mode = .dark
    weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
        let saved: Mode
        switch UserDefaults.standard.string(forKey: Self.defaultsKey) {
        case "light":  saved = .light
        case "system": saved = .system
        default:       saved = .dark
        }
        apply(saved)
    }

    func toggle() {
        apply(mode.toggled)
    }

    func apply(_ newMode: Mode) {
        mode = newMode
        switch newMode {
        case .system: window?.appearance = nil
        case .dark:   window?.appearance = NSAppearance(named: .darkAqua)
        case .light:  window?.appearance = NSAppearance(named: .aqua)
        }
        let key: String
        switch newMode {
        case .dark:   key = "dark"
        case .light:  key = "light"
        case .system: key = "system"
        }
        UserDefaults.standard.set(key, forKey: Self.defaultsKey)
    }
}
