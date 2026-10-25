import SwiftUI

enum KBPreferences {
    static let tabAnimationsKey = "tabAnimationsEnabled"
    static let tabAnimationsDefault = true

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
