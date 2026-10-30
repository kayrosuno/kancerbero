import Foundation

public enum KBProcessState: String, Codable, Sendable, Hashable {
    case idle = "I"
    case running = "R"
    case sleeping = "S"
    case stopped = "T"
    case zombie = "Z"
    case unknown = "?"

    /// On macOS 27 `pbi_status` is 2 (SRUN) for both running and sleeping
    /// processes, so prefer `pti_numrunning` when task info is available.
    public static func from(status: UInt32, runningThreads: Int) -> KBProcessState {
        switch status {
        case 1: return .idle
        case 2: return runningThreads > 0 ? .running : .sleeping
        case 3: return .sleeping
        case 4: return .stopped
        case 5: return .zombie
        default: return .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .sleeping: return "Sleeping"
        case .stopped: return "Stopped"
        case .zombie: return "Zombie"
        case .unknown: return "Unknown"
        }
    }
}

/// Per-process task counters. `nil` in `KBProcessInfo.usage` means libproc
/// returned no task info for this process (another user without root).
public struct KBProcessUsage: Codable, Sendable, Hashable {
    public var cpuTimeNanoseconds: UInt64
    public var residentBytes: UInt64
    public var virtualBytes: UInt64
    public var threads: Int
    public var runningThreads: Int
    public var priority: Int32
    /// Percentage of one core; may exceed 100 for multithreaded processes.
    public var cpuPercent: Double?
    /// Resident bytes over physical memory, 0...100.
    public var memoryPercent: Double?
    /// Cumulative energy counters from rusage_info_v6.
    public var energyNanojoules: UInt64?
    public var interruptWakeups: UInt64?
    public var packageIdleWakeups: UInt64?
    /// Rates computed between samples by `ProcessCPUTracker`.
    public var energyWatts: Double?
    public var wakeupsPerSecond: Double?
    /// True when the PID holds a PreventUserIdleSystemSleep/PreventSystemSleep assertion.
    public var preventingSleep: Bool?
    /// Cumulative disk counters from rusage_info_v6.
    public var diskBytesRead: UInt64?
    public var diskBytesWritten: UInt64?
    public var logicalWrites: UInt64?
    /// Disk rates computed between samples by `ProcessCPUTracker`.
    public var diskBytesReadPerSecond: Double?
    public var diskBytesWrittenPerSecond: Double?

    public init(cpuTimeNanoseconds: UInt64 = 0, residentBytes: UInt64 = 0,
                virtualBytes: UInt64 = 0, threads: Int = 0,
                runningThreads: Int = 0, priority: Int32 = 0,
                cpuPercent: Double? = nil, memoryPercent: Double? = nil,
                energyNanojoules: UInt64? = nil,
                interruptWakeups: UInt64? = nil,
                packageIdleWakeups: UInt64? = nil,
                energyWatts: Double? = nil,
                wakeupsPerSecond: Double? = nil,
                preventingSleep: Bool? = nil,
                diskBytesRead: UInt64? = nil,
                diskBytesWritten: UInt64? = nil,
                logicalWrites: UInt64? = nil,
                diskBytesReadPerSecond: Double? = nil,
                diskBytesWrittenPerSecond: Double? = nil) {
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.residentBytes = residentBytes
        self.virtualBytes = virtualBytes
        self.threads = threads
        self.runningThreads = runningThreads
        self.priority = priority
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.energyNanojoules = energyNanojoules
        self.interruptWakeups = interruptWakeups
        self.packageIdleWakeups = packageIdleWakeups
        self.energyWatts = energyWatts
        self.wakeupsPerSecond = wakeupsPerSecond
        self.preventingSleep = preventingSleep
        self.diskBytesRead = diskBytesRead
        self.diskBytesWritten = diskBytesWritten
        self.logicalWrites = logicalWrites
        self.diskBytesReadPerSecond = diskBytesReadPerSecond
        self.diskBytesWrittenPerSecond = diskBytesWrittenPerSecond
    }
}

public struct KBCoreCPU: Codable, Sendable, Identifiable, Hashable {
    public var index: Int
    public var userPercent: Double
    public var systemPercent: Double
    public var nicePercent: Double
    public var idlePercent: Double

    public var id: Int { index }
    public var usagePercent: Double {
        min(100, max(0, userPercent + systemPercent + nicePercent))
    }

    public init(index: Int, userPercent: Double = 0, systemPercent: Double = 0,
                nicePercent: Double = 0, idlePercent: Double = 0) {
        self.index = index
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.nicePercent = nicePercent
        self.idlePercent = idlePercent
    }
}

public struct KBCPUStats: Codable, Sendable, Hashable {
    public var coreCount: Int
    public var cores: [KBCoreCPU]
    public var userPercent: Double
    public var systemPercent: Double
    public var nicePercent: Double
    public var idlePercent: Double
    public var load1: Double
    public var load5: Double
    public var load15: Double
    public var taskCount: Int
    public var threadCount: Int
    public var threadsRestricted: Int
    public var uptimeSeconds: Double
    public var bootDate: Date?

    public var totalUsagePercent: Double {
        min(100, max(0, userPercent + systemPercent + nicePercent))
    }

    public init(coreCount: Int = 0, cores: [KBCoreCPU] = [],
                userPercent: Double = 0, systemPercent: Double = 0,
                nicePercent: Double = 0, idlePercent: Double = 0,
                load1: Double = 0, load5: Double = 0, load15: Double = 0,
                taskCount: Int = 0, threadCount: Int = 0,
                threadsRestricted: Int = 0, uptimeSeconds: Double = 0,
                bootDate: Date? = nil) {
        self.coreCount = coreCount
        self.cores = cores
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.nicePercent = nicePercent
        self.idlePercent = idlePercent
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
        self.taskCount = taskCount
        self.threadCount = threadCount
        self.threadsRestricted = threadsRestricted
        self.uptimeSeconds = uptimeSeconds
        self.bootDate = bootDate
    }
}

public struct KBMemoryStats: Codable, Sendable, Hashable {
    public var totalBytes: UInt64
    public var freeBytes: UInt64
    public var activeBytes: UInt64
    public var inactiveBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var speculativeBytes: UInt64
    public var purgeableBytes: UInt64
    public var internalBytes: UInt64
    public var externalBytes: UInt64
    public var swapTotalBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapAvailBytes: UInt64
    public var swapEncrypted: Bool
    public var pageSize: UInt64
    /// Memory pressure percentage (0...100, higher = more pressure), matching
    /// Activity Monitor: `100 - memorystatus_get_level()`.
    public var pressurePercent: Int?
    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2/3 warning, 4 critical.
    public var pressureLevel: Int?

    public enum PressureBand: Sendable {
        case low
        case medium
        case high
        case unknown
    }

    public var pressureBand: PressureBand {
        guard let pressureLevel else { return .unknown }
        switch pressureLevel {
        case 1: return .low
        case 2, 3: return .medium
        default: return pressureLevel >= 4 ? .high : .unknown
        }
    }

    public var pressureLabel: String {
        switch pressureBand {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .unknown: return "Unknown"
        }
    }

    /// htop-style used memory: app/active + wired + compressed.
    public var usedBytes: UInt64 {
        activeBytes + wiredBytes + compressedBytes
    }

    /// Inactive pages are reclaimable file cache.
    public var cachedBytes: UInt64 {
        inactiveBytes
    }

    /// Remainder that keeps the segmented bar at or below the physical total.
    public var barFreeBytes: UInt64 {
        let committed = usedBytes + cachedBytes
        return committed < totalBytes ? totalBytes - committed : 0
    }

    public var availableBytes: UInt64 {
        barFreeBytes + cachedBytes
    }

    /// Activity Monitor's "App Memory": internal pages minus purgeable pages.
    public var appMemoryBytes: UInt64 {
        internalBytes > purgeableBytes ? internalBytes - purgeableBytes : 0
    }

    /// Activity Monitor's "Cached Files": external plus purgeable pages.
    public var cachedFileBytes: UInt64 {
        externalBytes + purgeableBytes
    }

    /// Activity Monitor's "Memory Used": app + wired + compressed.
    public var activityMonitorUsedBytes: UInt64 {
        appMemoryBytes + wiredBytes + compressedBytes
    }

    public var activityMonitorUsedFraction: Double {
        totalBytes > 0
            ? min(1, Double(activityMonitorUsedBytes) / Double(totalBytes))
            : 0
    }

    public var activityMonitorFreeBytes: UInt64 {
        let committed = activityMonitorUsedBytes + cachedFileBytes
        return committed < totalBytes ? totalBytes - committed : 0
    }

    public var usedFraction: Double {
        totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : 0
    }

    public var swapUsedFraction: Double {
        swapTotalBytes > 0 ? min(1, Double(swapUsedBytes) / Double(swapTotalBytes)) : 0
    }

    public init(totalBytes: UInt64 = 0, freeBytes: UInt64 = 0,
                activeBytes: UInt64 = 0, inactiveBytes: UInt64 = 0,
                wiredBytes: UInt64 = 0, compressedBytes: UInt64 = 0,
                speculativeBytes: UInt64 = 0, purgeableBytes: UInt64 = 0,
                internalBytes: UInt64 = 0, externalBytes: UInt64 = 0,
                swapTotalBytes: UInt64 = 0, swapUsedBytes: UInt64 = 0,
                swapAvailBytes: UInt64 = 0, swapEncrypted: Bool = false,
                pageSize: UInt64 = 0,
                pressurePercent: Int? = nil, pressureLevel: Int? = nil) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.speculativeBytes = speculativeBytes
        self.purgeableBytes = purgeableBytes
        self.internalBytes = internalBytes
        self.externalBytes = externalBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapAvailBytes = swapAvailBytes
        self.swapEncrypted = swapEncrypted
        self.pageSize = pageSize
        self.pressurePercent = pressurePercent
        self.pressureLevel = pressureLevel
    }
}

public struct KBHostMetrics: Codable, Sendable, Hashable {
    public var cpu: KBCPUStats
    public var memory: KBMemoryStats
    /// Present when IOAccelerator exposes PerformanceStatistics.
    public var gpu: KBGPUStats?
    /// Battery state from IOPowerSources.
    public var power: KBPowerStats?

    public init(cpu: KBCPUStats = KBCPUStats(), memory: KBMemoryStats = KBMemoryStats(),
                gpu: KBGPUStats? = nil, power: KBPowerStats? = nil) {
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.power = power
    }
}

/// Battery charge, charging state and power source.
public struct KBPowerStats: Codable, Sendable, Hashable {
    public var hasBattery: Bool
    public var isPluggedIn: Bool
    public var isCharging: Bool
    public var isCharged: Bool
    public var chargePercent: Int?
    public var timeRemainingMinutes: Int?
    public var source: String?

    public init(hasBattery: Bool = false,
                isPluggedIn: Bool = false,
                isCharging: Bool = false,
                isCharged: Bool = false,
                chargePercent: Int? = nil,
                timeRemainingMinutes: Int? = nil,
                source: String? = nil) {
        self.hasBattery = hasBattery
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.chargePercent = chargePercent
        self.timeRemainingMinutes = timeRemainingMinutes
        self.source = source
    }

    public var chargeFraction: Double {
        Double(chargePercent ?? 0) / 100
    }
}

/// GPU utilisation from IOAccelerator PerformanceStatistics. Percentages are
/// nil when the driver does not publish them.
public struct KBGPUStats: Codable, Sendable, Hashable {
    public var name: String?
    public var utilizationPercent: Double?
    public var rendererPercent: Double?
    public var tilerPercent: Double?
    public var inUseMemoryBytes: UInt64?
    public var allocatedMemoryBytes: UInt64?

    public init(name: String? = nil,
                utilizationPercent: Double? = nil,
                rendererPercent: Double? = nil,
                tilerPercent: Double? = nil,
                inUseMemoryBytes: UInt64? = nil,
                allocatedMemoryBytes: UInt64? = nil) {
        self.name = name
        self.utilizationPercent = utilizationPercent
        self.rendererPercent = rendererPercent
        self.tilerPercent = tilerPercent
        self.inUseMemoryBytes = inUseMemoryBytes
        self.allocatedMemoryBytes = allocatedMemoryBytes
    }
}
