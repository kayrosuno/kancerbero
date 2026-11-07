import AppKit
import Foundation

/// App-wide appearance override chosen from the title bar. `system` keeps the
/// previous behavior: every window follows macOS.
enum KBAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum KBAppearance {
    static func storedMode(
        defaults: UserDefaults = .standard
    ) -> KBAppearanceMode {
        guard let raw = defaults.string(
            forKey: KBPreferences.appearanceModeKey),
              let mode = KBAppearanceMode(rawValue: raw) else {
            return .system
        }
        return mode
    }

    /// Setting `NSApp.appearance` changes every window and menu, including
    /// the secondary System status, Filter rules and Settings windows.
    @MainActor
    static func apply(_ mode: KBAppearanceMode) {
        NSApplication.shared.appearance = mode.appearance
    }

    @MainActor
    static func applyStored() {
        apply(storedMode())
    }
}
