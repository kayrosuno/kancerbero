import Foundation

struct ProcessKillAvailability: Equatable {
    enum Status: Equatable {
        case enabled
        case needsAdministrator
        case disabled
    }

    let status: Status
    let reason: String?

    var isEnabled: Bool { status != .disabled }
}
