import Darwin
import Foundation

/// Samples host-wide CPU, memory, swap, load and uptime. Per-core percentages
/// come from 32-bit Mach tick deltas, so the first sample has no baseline and
/// reports zero; the next tick produces real percentages.
public struct HostMetricsSampler {
    private struct CoreTicks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private var previous: [UInt32: CoreTicks] = [:]

    public init() {}

    public mutating func sample(processes: [KBProcessInfo]) -> KBHostMetrics? {
        var raw = kb_host_stats()
        guard kb_host_stats_read(&raw) == 0 else { return nil }

        let coreCount = min(Int(raw.core_count), 256)
        var cores: [KBCoreCPU] = []
        cores.reserveCapacity(coreCount)

        var aggregateUser: UInt64 = 0
        var aggregateSystem: UInt64 = 0
        var aggregateIdle: UInt64 = 0
        var aggregateNice: UInt64 = 0

        var current: [UInt32: CoreTicks] = [:]
        current.reserveCapacity(coreCount)

        // A fixed-size C array is imported as a tuple; walk it with a pointer.
        withUnsafePointer(to: &raw.cores) { base in
            base.withMemoryRebound(to: kb_cpu_core.self, capacity: coreCount) { items in
                for index in 0..<coreCount {
                    let item = items[index]
                    let ticks = CoreTicks(
                        user: UInt32(truncatingIfNeeded: item.user_ticks),
                        system: UInt32(truncatingIfNeeded: item.system_ticks),
                        idle: UInt32(truncatingIfNeeded: item.idle_ticks),
                        nice: UInt32(truncatingIfNeeded: item.nice_ticks)
                    )
                    let coreIndex = UInt32(item.index)
                    current[coreIndex] = ticks

                    let prior = previous[coreIndex]
                    let user = UInt64(ticks.user &- (prior?.user ?? ticks.user))
                    let system = UInt64(ticks.system &- (prior?.system ?? ticks.system))
                    let idle = UInt64(ticks.idle &- (prior?.idle ?? ticks.idle))
                    let nice = UInt64(ticks.nice &- (prior?.nice ?? ticks.nice))
                    let total = user + system + idle + nice

                    aggregateUser += user
                    aggregateSystem += system
                    aggregateIdle += idle
                    aggregateNice += nice

                    let percentages = Self.percentages(idle: idle, total: total,
                                                       user: user, system: system, nice: nice)
                    cores.append(KBCoreCPU(index: Int(coreIndex),
                                           userPercent: percentages.user,
                                           systemPercent: percentages.system,
                                           nicePercent: percentages.nice,
                                           idlePercent: percentages.idle))
                }
            }
        }
        previous = current

        let aggregateTotal = aggregateUser + aggregateSystem + aggregateIdle + aggregateNice
        let totalPercentages = Self.percentages(idle: aggregateIdle,
                                                total: aggregateTotal,
                                                user: aggregateUser,
                                                system: aggregateSystem,
                                                nice: aggregateNice)

        let threadCount = processes.reduce(0) { $0 + ($1.usage?.threads ?? 0) }
        let restricted = processes.reduce(0) { $0 + ($1.usage == nil ? 1 : 0) }

        let bootDate: Date? = raw.boot_time_us > 0
            ? Date(timeIntervalSince1970: Double(raw.boot_time_us) / 1_000_000)
            : nil
        let uptime: Double
        if let bootDate {
            uptime = max(0, Date().timeIntervalSince(bootDate))
        } else {
            uptime = max(0, ProcessInfo.processInfo.systemUptime)
        }

        let cpu = KBCPUStats(
            coreCount: coreCount,
            cores: cores,
            userPercent: totalPercentages.user,
            systemPercent: totalPercentages.system,
            nicePercent: totalPercentages.nice,
            idlePercent: totalPercentages.idle,
            load1: raw.load_valid != 0 ? raw.load1 : 0,
            load5: raw.load_valid != 0 ? raw.load5 : 0,
            load15: raw.load_valid != 0 ? raw.load15 : 0,
            taskCount: processes.count,
            threadCount: threadCount,
            threadsRestricted: restricted,
            uptimeSeconds: uptime,
            bootDate: bootDate
        )

        let memory = KBMemoryStats(
            totalBytes: raw.mem_total,
            freeBytes: raw.mem_free,
            activeBytes: raw.mem_active,
            inactiveBytes: raw.mem_inactive,
            wiredBytes: raw.mem_wired,
            compressedBytes: raw.mem_compressor,
            speculativeBytes: raw.mem_speculative,
            purgeableBytes: raw.mem_purgeable,
            internalBytes: raw.mem_internal,
            externalBytes: raw.mem_external,
            swapTotalBytes: raw.swap_total,
            swapUsedBytes: raw.swap_used,
            swapAvailBytes: raw.swap_avail,
            swapEncrypted: raw.swap_encrypted != 0,
            pageSize: raw.page_size,
            pressurePercent: raw.mem_pressure_percent >= 0
                ? Int(raw.mem_pressure_percent) : nil,
            pressureLevel: raw.mem_pressure_level >= 0
                ? Int(raw.mem_pressure_level) : nil
        )

        return KBHostMetrics(cpu: cpu, memory: memory,
                             gpu: GPUStatsReader.current(),
                             power: PowerStatsReader.current())
    }

    private static func percentages(idle: UInt64, total: UInt64,
                                    user: UInt64, system: UInt64,
                                    nice: UInt64) -> (user: Double, system: Double,
                                                      nice: Double, idle: Double) {
        guard total > 0 else { return (0, 0, 0, 0) }
        let divisor = Double(total)
        return (
            user: Double(user) / divisor * 100,
            system: Double(system) / divisor * 100,
            nice: Double(nice) / divisor * 100,
            idle: Double(idle) / divisor * 100
        )
    }
}

/// Turns the cumulative per-process CPU, energy and wake-up counters into
/// per-second rates between samples. Keys include the start time, so PID reuse
/// starts a new baseline instead of producing a bogus delta.
public struct ProcessCPUTracker {
    private struct Counters {
        var cpuTime: UInt64
        var energy: UInt64
        var wakeups: UInt64
        var diskRead: UInt64
        var diskWrite: UInt64
    }

    private var previous: [KBProcessKey: Counters] = [:]

    public init() {}

    public mutating func annotate(_ processes: inout [KBProcessInfo],
                                  elapsed: Double,
                                  totalMemoryBytes: UInt64,
                                  coreCount: Int) {
        let validInterval = elapsed > 0 && elapsed < 5 && elapsed.isFinite
        let maxPercent = Double(max(1, coreCount)) * 100
        var baseline: [KBProcessKey: Counters] = [:]
        baseline.reserveCapacity(processes.count)

        for index in processes.indices {
            guard var usage = processes[index].usage else { continue }
            let key = processes[index].id
            let current = usage.cpuTimeNanoseconds
            let energy = usage.energyNanojoules ?? 0
            let wakeups = (usage.interruptWakeups ?? 0) &+ (usage.packageIdleWakeups ?? 0)
            let diskRead = usage.diskBytesRead ?? 0
            let diskWrite = usage.diskBytesWritten ?? 0
            baseline[key] = Counters(cpuTime: current, energy: energy,
                                     wakeups: wakeups,
                                     diskRead: diskRead, diskWrite: diskWrite)

            if let prior = previous[key], validInterval {
                if current >= prior.cpuTime {
                    let seconds = Double(current - prior.cpuTime) / 1_000_000_000
                    usage.cpuPercent = min(maxPercent, max(0, seconds / elapsed * 100))
                } else {
                    usage.cpuPercent = 0
                }
                usage.energyWatts = energy >= prior.energy
                    ? Double(energy - prior.energy) / 1_000_000_000 / elapsed
                    : 0
                usage.wakeupsPerSecond = wakeups >= prior.wakeups
                    ? Double(wakeups - prior.wakeups) / elapsed
                    : 0
                usage.diskBytesReadPerSecond = diskRead >= prior.diskRead
                    ? Double(diskRead - prior.diskRead) / elapsed
                    : 0
                usage.diskBytesWrittenPerSecond = diskWrite >= prior.diskWrite
                    ? Double(diskWrite - prior.diskWrite) / elapsed
                    : 0
            } else {
                usage.cpuPercent = 0
                usage.energyWatts = 0
                usage.wakeupsPerSecond = 0
                usage.diskBytesReadPerSecond = 0
                usage.diskBytesWrittenPerSecond = 0
            }

            if totalMemoryBytes > 0 {
                usage.memoryPercent =
                    Double(usage.residentBytes) / Double(totalMemoryBytes) * 100
            } else {
                usage.memoryPercent = nil
            }
            processes[index].usage = usage
        }

        // Replacing the whole dictionary prunes dead processes.
        previous = baseline
    }
}

/// Host-wide memory pressure. It needs no privileges, so it also fills the
/// gap when a connected daemon predates the pressure fields.
public enum MemoryPressureReader {
    public static func current() -> (percent: Int?, level: Int?) {
        var percent: Int32 = -1
        var level: Int32 = -1
        guard kb_memory_pressure_read(&percent, &level) == 0 else {
            return (nil, nil)
        }
        return (percent >= 0 ? Int(percent) : nil,
                level >= 0 ? Int(level) : nil)
    }
}

/// GPU utilisation from IOAccelerator PerformanceStatistics. Readable without
/// privileges, so it also fills the gap when a connected daemon predates the
/// GPU fields.
public enum GPUStatsReader {
    public static func current() -> KBGPUStats? {
        var raw = kb_gpu_stats()
        guard kb_gpu_stats_read(&raw) == 0 else {
            return nil
        }
        let name = withUnsafeBytes(of: &raw.name) { bytes -> String in
            guard let pointer = bytes.baseAddress?
                .assumingMemoryBound(to: CChar.self) else { return "" }
            return String(cString: pointer)
        }
        return KBGPUStats(
            name: name.isEmpty ? nil : name,
            utilizationPercent: raw.utilization_percent >= 0
                ? raw.utilization_percent : nil,
            rendererPercent: raw.renderer_percent >= 0
                ? raw.renderer_percent : nil,
            tilerPercent: raw.tiler_percent >= 0
                ? raw.tiler_percent : nil,
            inUseMemoryBytes: raw.in_use_memory > 0
                ? raw.in_use_memory : nil,
            allocatedMemoryBytes: raw.alloc_memory > 0
                ? raw.alloc_memory : nil
        )
    }
}

/// Battery state, readable without privileges so it also fills the gap when a
/// connected daemon predates the power fields.
public enum PowerStatsReader {
    public static func current() -> KBPowerStats? {
        var raw = kb_power_stats()
        guard kb_power_stats_read(&raw) == 0 else { return nil }
        let source = withUnsafeBytes(of: &raw.source) { bytes -> String in
            guard let pointer = bytes.baseAddress?
                .assumingMemoryBound(to: CChar.self) else { return "" }
            return String(cString: pointer)
        }
        return KBPowerStats(
            hasBattery: raw.has_battery != 0,
            isPluggedIn: raw.is_plugged_in != 0,
            isCharging: raw.is_charging != 0,
            isCharged: raw.is_charged != 0,
            chargePercent: raw.charge_percent >= 0 ? Int(raw.charge_percent) : nil,
            timeRemainingMinutes: raw.time_remaining_min > 0
                ? Int(raw.time_remaining_min) : nil,
            source: source.isEmpty ? nil : source
        )
    }
}

/// PIDs that currently hold a PreventUserIdleSystemSleep/PreventSystemSleep
/// assertion. `nil` when the system refuses the query.
public enum PowerAssertionsReader {
    public static func current() -> Set<Int32>? {
        var pids: UnsafeMutablePointer<Int32>?
        var count = 0
        guard kb_prevent_sleep_pids(&pids, &count) == 0 else { return nil }
        defer {
            if let pids {
                free(UnsafeMutableRawPointer(pids))
            }
        }
        guard let pids, count > 0 else { return [] }
        return Set(UnsafeBufferPointer(start: pids, count: count))
    }
}

/// Per-process cumulative energy and wake-up counters from rusage_info_v6.
public enum ProcessEnergyReader {
    public static func current(pid: Int32) -> (energy: UInt64, wakeups: UInt64)? {
        var energy: UInt64 = 0
        var interrupt: UInt64 = 0
        var idle: UInt64 = 0
        guard kb_process_energy_read(pid, &energy, &interrupt, &idle) == 0 else {
            return nil
        }
        return (energy, interrupt &+ idle)
    }
}

/// Per-process cumulative disk counters from rusage_info_v6.
public enum ProcessIOReader {
    public static func current(pid: Int32) -> (read: UInt64, written: UInt64,
                                               writes: UInt64)? {
        var read: UInt64 = 0
        var written: UInt64 = 0
        var writes: UInt64 = 0
        guard kb_process_io_read(pid, &read, &written, &writes) == 0 else {
            return nil
        }
        return (read, written, writes)
    }
}
