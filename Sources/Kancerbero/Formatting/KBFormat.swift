import Foundation

enum KBFormat {
    private static let bitUnits = ["bps", "Kbps", "Mbps", "Gbps", "Tbps"]

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }

    /// Bytes per second -> human-readable decimal bit rate (1 Kbps = 1000 bps).
    static func bitRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "0 bps" }

        var value = bytesPerSecond * 8
        var unit = 0
        // Promote before formatting so 999.96 does not render as "1000 bps".
        while value >= 999.95, unit < bitUnits.count - 1 {
            value /= 1000
            unit += 1
        }

        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return "\(number) \(bitUnits[unit])"
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
