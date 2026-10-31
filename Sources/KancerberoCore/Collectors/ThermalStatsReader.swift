import Darwin
import Foundation

/// Package and per-core CPU temperatures from the IOHID event system.
/// Apple silicon exposes temperature sensors but not a public core-to-sensor
/// map, so per-core values are approximated the same way btop does: the
/// available sensor groups are mapped proportionally onto the logical cores.
public struct KBThermalReading: Sendable, Hashable {
    public var packageCelsius: Double?
    public var coreCelsius: [Int: Double]
    public var source: String?
    public var sensorCount: Int

    public init(packageCelsius: Double? = nil,
                coreCelsius: [Int: Double] = [:],
                source: String? = nil,
                sensorCount: Int = 0) {
        self.packageCelsius = packageCelsius
        self.coreCelsius = coreCelsius
        self.source = source
        self.sensorCount = sensorCount
    }
}

/// Readable without privileges, so it also fills the gap when a connected
/// daemon predates the temperature fields.
public enum ThermalStatsReader {
    public static func current(coreCount: Int,
                               minIntervalMilliseconds: UInt32 = 1_000)
        -> KBThermalReading? {
        // IOHID temperature services belong to the user's HID session. A
        // system-domain LaunchDaemon should not open one; the app fills the
        // temperature locally when it receives the daemon snapshot.
        guard geteuid() != 0 else { return nil }
        var raw = kb_thermal_stats()
        let requested = UInt32(max(0, min(coreCount, 256)))
        guard kb_thermal_stats_read(&raw, requested, minIntervalMilliseconds) == 0,
              raw.valid != 0 else {
            return nil
        }

        let package = raw.package_valid != 0 && raw.package_celsius > 0
            && raw.package_celsius < 150
            ? raw.package_celsius : nil

        var temperatures: [Int: Double] = [:]
        let mappedCount = min(Int(raw.core_count), 256)
        withUnsafePointer(to: &raw.core_celsius) { base in
            base.withMemoryRebound(to: Double.self, capacity: 256) { values in
                for index in 0..<mappedCount {
                    let value = values[index]
                    guard value > 0, value < 150 else { continue }
                    temperatures[index] = value
                }
            }
        }

        return KBThermalReading(
            packageCelsius: package,
            coreCelsius: temperatures,
            source: sourceLabel(raw.source),
            sensorCount: Int(raw.sensor_count)
        )
    }

    /// Fills only the fields an older daemon did not report.
    public static func fillMissing(_ cpu: inout KBCPUStats,
                                   minIntervalMilliseconds: UInt32 = 1_000) {
        let count = cpu.coreCount > 0 ? cpu.coreCount : cpu.cores.count
        guard let reading = current(coreCount: count,
                                    minIntervalMilliseconds: minIntervalMilliseconds)
        else { return }
        if cpu.packageTemperatureCelsius == nil {
            cpu.packageTemperatureCelsius = reading.packageCelsius
        }
        if cpu.temperatureSource == nil {
            cpu.temperatureSource = reading.source
        }
        for index in cpu.cores.indices where cpu.cores[index].temperatureCelsius == nil {
            let core = cpu.cores[index]
            cpu.cores[index].temperatureCelsius =
                reading.coreCelsius[core.index] ?? reading.coreCelsius[index]
        }
    }

    private static func sourceLabel(_ raw: Int32) -> String? {
        switch raw {
        case 1: return "eACC/pACC"
        case 2: return "PMU tdie"
        case 3: return "SOC MTR"
        default: return nil
        }
    }
}
