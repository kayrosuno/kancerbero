import Foundation

enum KBFormat {
    private static let bitUnits = ["bps", "Kbps", "Mbps", "Gbps", "Tbps"]

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }

    static func bytes(_ value: Int64) -> String {
        bytes(UInt64(max(0, value)))
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

    private static let packetUnits = ["pkt/s", "K pkt/s", "M pkt/s", "G pkt/s"]

    /// Packets per second -> human-readable decimal packet rate.
    static func packetsRate(_ packetsPerSecond: Double) -> String {
        guard packetsPerSecond.isFinite, packetsPerSecond >= 0.05 else {
            return "0 pkt/s"
        }
        var value = packetsPerSecond
        var unit = 0
        while value >= 999.95, unit < packetUnits.count - 1 {
            value /= 1000
            unit += 1
        }
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return "\(number) \(packetUnits[unit])"
    }

    /// Cumulative byte totals; unlike `bytes`, zero renders as "0 B".
    static func totalBytes(_ value: UInt64) -> String {
        value == 0 ? "0 B" : bytes(value)
    }

    /// Compact cumulative packet totals ("1,2 M").
    static func compactTotal(_ value: UInt64) -> String {
        guard value >= 1_000 else { return value.formatted() }
        let units = ["K", "M", "G", "T", "P"]
        var scaled = Double(value)
        var unit = -1
        while scaled >= 999.95, unit < units.count - 1 {
            scaled /= 1000
            unit += 1
        }
        let number = scaled.formatted(.number.precision(.fractionLength(0...1)))
        return "\(number) \(units[unit])"
    }

    /// Bytes per second -> human-readable byte rate ("1,2 MB/s").
    static func byteRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 1 else { return "0 B/s" }
        let value = UInt64(max(0, min(bytesPerSecond, Double(UInt64.max))))
        return bytes(value) + "/s"
    }

    /// Operations per second ("12,3/s", "1,2K/s").
    static func opsRate(_ operationsPerSecond: Double) -> String {
        guard operationsPerSecond.isFinite, operationsPerSecond >= 0.05 else {
            return "0/s"
        }
        if operationsPerSecond >= 1000 {
            return (operationsPerSecond / 1000)
                .formatted(.number.precision(.fractionLength(0...1))) + "K/s"
        }
        return operationsPerSecond
            .formatted(.number.precision(.fractionLength(0...1))) + "/s"
    }

    static func count(_ value: UInt64) -> String {
        value.formatted()
    }

    /// Compact duration for chart axes: "30s", "60s", "2m", "2m30s".
    static func shortDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0s" }
        let total = Int(seconds.rounded())
        if total < 120 { return "\(total)s" }
        let minutes = total / 60
        let rest = total % 60
        return rest == 0 ? "\(minutes)m" : "\(minutes)m\(rest)s"
    }

    static func compactCount(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "—" }
        let value = min(max(fraction, 0), 1)
        return (value * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    /// htop-style CPU percentage, already normalised per core. Values above
    /// 100% are valid for multithreaded processes.
    static func usagePercent(_ percent: Double) -> String {
        guard percent.isFinite else { return "—" }
        return max(0, percent).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    static func load(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2)))
    }

    /// Sensor temperature. Compact form fits the core rows ("61°"); the full
    /// form carries the unit for popovers and tooltips.
    static func temperature(_ celsius: Double?, compact: Bool = false) -> String {
        guard let celsius, celsius.isFinite, celsius > 0, celsius < 150 else {
            return "—"
        }
        let number = celsius.formatted(
            .number.precision(.fractionLength(compact ? 0 : 1)))
        return compact ? "\(number)°" : "\(number) °C"
    }

    /// Accumulated CPU time for htop's TIME+ column.
    static func cpuDuration(_ nanoseconds: UInt64) -> String {
        let total = nanoseconds / 1_000_000_000
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func uptime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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
