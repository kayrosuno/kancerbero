import SwiftUI

/// Decimal (base 10, like Finder) or binary (base 2, IEC labels) byte units
/// for the Disk section.
enum KBByteUnitSystem: String, CaseIterable, Identifiable, Sendable {
    case decimal
    case binary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decimal: return "Decimal"
        case .binary: return "Binary"
        }
    }

    var base: Double {
        self == .decimal ? 1000 : 1024
    }

    var units: [String] {
        switch self {
        case .decimal: return ["B", "KB", "MB", "GB", "TB", "PB"]
        case .binary: return ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        }
    }

    /// Screenshot/session override; it never writes to UserDefaults.
    static func fromCommandLine(
        _ arguments: [String] = CommandLine.arguments
    ) -> KBByteUnitSystem? {
        guard let index = arguments.firstIndex(of: "--disk-units"),
              index + 1 < arguments.count,
              let value = KBByteUnitSystem(rawValue: arguments[index + 1].lowercased())
        else { return nil }
        return value
    }
}

extension KBByteUnitSystem: GraphModeOption {}

private struct ByteUnitSystemEnvironmentKey: EnvironmentKey {
    /// Binary preserves the formatting of the shared, non-Disk components.
    static let defaultValue: KBByteUnitSystem = .binary
}

extension EnvironmentValues {
    var byteUnitSystem: KBByteUnitSystem {
        get { self[ByteUnitSystemEnvironmentKey.self] }
        set { self[ByteUnitSystemEnvironmentKey.self] = newValue }
    }
}
