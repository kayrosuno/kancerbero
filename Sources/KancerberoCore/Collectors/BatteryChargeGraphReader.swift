import Foundation

/// Twelve-hour battery charge history for the Energy tab, read from the same
/// private libsystemstats graph that Activity Monitor uses. Times are seconds
/// before the read, oldest to newest.
public struct KBBatteryChargeGraph: Sendable, Equatable {
    public var chargeTimes: [Double]
    public var chargeLevels: [Double]
    public var stateTimes: [Double]
    /// True while the Mac was on AC power, parallel to `stateTimes`.
    public var onAC: [Bool]

    public init(chargeTimes: [Double], chargeLevels: [Double],
                stateTimes: [Double], onAC: [Bool]) {
        self.chargeTimes = chargeTimes
        self.chargeLevels = chargeLevels
        self.stateTimes = stateTimes
        self.onAC = onAC
    }
}

public enum BatteryChargeGraphReader {
    /// Returns nil when the private symbol is unavailable or the data is
    /// malformed; callers then keep the static capacity bar.
    public static func current() -> KBBatteryChargeGraph? {
        var raw = kb_battery_charge_graph()
        guard kb_battery_charge_graph_read(&raw) != 0 else { return nil }
        defer { kb_battery_charge_graph_free(&raw) }

        let count = raw.charge_count
        guard count > 1 else { return nil }
        let times = buffer(raw.charge_times, count)
        let levels = buffer(raw.charge_levels, count)
        guard times.count == levels.count else { return nil }

        var stateTimes = buffer(raw.state_times, raw.state_count)
        var onAC = buffer(raw.on_ac, raw.state_count).map { $0 != 0 }
        if stateTimes.count != onAC.count {
            stateTimes = []
            onAC = []
        }
        return KBBatteryChargeGraph(chargeTimes: times,
                                    chargeLevels: levels,
                                    stateTimes: stateTimes,
                                    onAC: onAC)
    }

    private static func buffer<T>(_ pointer: UnsafeMutablePointer<T>?,
                                  _ count: Int) -> [T] {
        guard let pointer, count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
}
