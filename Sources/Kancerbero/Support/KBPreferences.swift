import Foundation
import SwiftUI

enum KBPreferences {
    static let tabAnimationsKey = "tabAnimationsEnabled"
    static let tabAnimationsDefault = true

    static let statusBarTextAnimationsKey = "statusBarTextAnimationsEnabled"
    static let statusBarTextAnimationsDefault = false

    static let startupIntervalKey = "startupSamplingInterval"
    static let startupIntervalDefault: TimeInterval = 2.0

    static let dockIconStyleKey = "dockIconStyle"
    static let dockIconStyleDefault = DockIconStyle.applicationIcon.rawValue

    /// Window (seconds) in which a connection that moved data still counts as
    /// active. The list is the set of supported values; the default is 10 and
    /// the effective minimum is 5.
    static let activeWindowKey = "activeConnectionWindowSeconds"
    static let activeWindowDefault = 10
    static let activeWindowOptions = [5, 10, 20, 30, 60, 120]

    /// Falls back to the default when the stored value is absent or not one of
    /// the supported windows.
    static func activeWindow(stored: Int) -> Int {
        activeWindowOptions.contains(stored) ? stored : activeWindowDefault
    }

    /// Window currently stored in UserDefaults; `integer(forKey:)` returns 0
    /// when the key is absent, which also maps to the default.
    static var activeWindowSeconds: Int {
        activeWindow(stored: UserDefaults.standard.integer(forKey: activeWindowKey))
    }

    /// Cadence the app starts with. The toolbar selector adjusts the current
    /// session only; this preference decides the next launch.
    static var startupInterval: TimeInterval {
        guard let stored = UserDefaults.standard.object(forKey: startupIntervalKey) as? Double,
              stored.isFinite, stored > 0 else {
            return startupIntervalDefault
        }
        return stored
    }

    /// The stored preference is subordinate to the system accessibility setting.
    static func enabled(stored: Bool, reduceMotion: Bool) -> Bool {
        stored && !reduceMotion
    }

    static func tabAnimation(stored: Bool, reduceMotion: Bool,
                             duration: Double) -> Animation? {
        enabled(stored: stored, reduceMotion: reduceMotion)
            ? .snappy(duration: duration)
            : nil
    }

    /// Shared duration for collapsing/expanding dashboard cards.
    static func collapseAnimation(stored: Bool, reduceMotion: Bool) -> Animation? {
        tabAnimation(stored: stored, reduceMotion: reduceMotion, duration: 0.25)
    }
}
