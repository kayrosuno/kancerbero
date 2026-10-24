import Foundation

enum KBFormat {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }

    static func rate(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0 B/s" }
        return bytes(UInt64(value)) + "/s"
    }

    static func count(_ value: UInt64) -> String {
        value.formatted()
    }

    static func compactCount(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "—" }
        let value = min(max(fraction, 0), 1)
        return (value * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return timeFormatter.string(from: date)
    }
}
