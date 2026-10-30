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
}
