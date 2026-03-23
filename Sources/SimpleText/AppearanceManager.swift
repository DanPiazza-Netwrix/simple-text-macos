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

    private(set) var mode: Mode = .dark
    weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
        apply(.dark)
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
    }
}
