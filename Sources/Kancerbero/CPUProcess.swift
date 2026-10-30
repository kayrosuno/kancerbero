import Foundation
import KancerberoCore

/// Row for the CPU tab. Sort keys are non-optional so restricted processes
/// (no task info) sort consistently at the end instead of producing `nil`
/// comparators.
struct CPUProcessRow: Identifiable, Hashable {
    let process: KBProcessInfo

    var id: KBProcessKey { process.id }

    var cpuPercent: Double? { process.usage?.cpuPercent }
    var memoryPercent: Double? { process.usage?.memoryPercent }

    var cpuSortValue: Double { cpuPercent ?? -1 }
    var memorySortValue: Double { memoryPercent ?? -1 }
    var residentSortValue: UInt64 { process.usage?.residentBytes ?? 0 }
    var virtualSortValue: UInt64 { process.usage?.virtualBytes ?? 0 }
    var prioritySortValue: Int32 { process.usage?.priority ?? Int32.max }
    var niceSortValue: Int32 { process.nice ?? 0 }
    var threadsSortValue: Int { process.usage?.threads ?? 0 }
    var timeSortValue: UInt64 { process.usage?.cpuTimeNanoseconds ?? 0 }
    var stateSortValue: String { process.state?.rawValue ?? "?" }
    var userSortValue: UInt32 { process.uid }
    var commandSortValue: String { process.name.isEmpty ? process.path : process.name }

    var energyWatts: Double? { process.usage?.energyWatts }
    var wakeupsPerSecond: Double? { process.usage?.wakeupsPerSecond }
    var preventingSleep: Bool { process.usage?.preventingSleep ?? false }
    var energySortValue: Double { energyWatts ?? -1 }
    var wakeupSortValue: Double { wakeupsPerSecond ?? -1 }
    var sleepSortValue: Int { preventingSleep ? 1 : 0 }
    var diskBytesRead: UInt64? { process.usage?.diskBytesRead }
    var diskBytesWritten: UInt64? { process.usage?.diskBytesWritten }
    var logicalWrites: UInt64? { process.usage?.logicalWrites }
    var diskReadRate: Double? { process.usage?.diskBytesReadPerSecond }
    var diskWriteRate: Double? { process.usage?.diskBytesWrittenPerSecond }
    var diskSortValue: Double { (diskReadRate ?? 0) + (diskWriteRate ?? 0) }
    var diskReadSortValue: Double { diskReadRate ?? -1 }
    var diskWriteSortValue: Double { diskWriteRate ?? -1 }
    var diskBytesReadSortValue: UInt64 { diskBytesRead ?? 0 }
    var diskBytesWrittenSortValue: UInt64 { diskBytesWritten ?? 0 }
    var logicalWritesSortValue: UInt64 { logicalWrites ?? 0 }

    var priorityText: String {
        process.usage.map { String($0.priority) } ?? "—"
    }

    var niceText: String {
        process.nice.map { String($0) } ?? "—"
    }

    var threadsText: String {
        process.usage.map { String($0.threads) } ?? "—"
    }

    var residentText: String {
        process.usage.map { KBFormat.bytes($0.residentBytes) } ?? "—"
    }

    var virtualText: String {
        process.usage.map { KBFormat.bytes($0.virtualBytes) } ?? "—"
    }

    var cpuText: String {
        guard let cpuPercent else { return "—" }
        return String(format: "%.1f%%", cpuPercent)
    }

    var memoryText: String {
        guard let memoryPercent else { return "—" }
        return String(format: "%.1f%%", memoryPercent)
    }

    var energyText: String {
        guard let energyWatts else { return "—" }
        return String(format: "%.2f W", energyWatts)
    }

    var wakeupsText: String {
        guard let wakeupsPerSecond else { return "—" }
        return String(format: "%.1f/s", wakeupsPerSecond)
    }

    var sleepText: String {
        preventingSleep ? "Yes" : "—"
    }

    var diskReadRateText: String {
        diskReadRate.map { KBFormat.byteRate($0) } ?? "—"
    }

    var diskWriteRateText: String {
        diskWriteRate.map { KBFormat.byteRate($0) } ?? "—"
    }

    var diskBytesReadText: String {
        guard let diskBytesRead else { return "—" }
        return diskBytesRead == 0 ? "0 B" : KBFormat.bytes(diskBytesRead)
    }

    var diskBytesWrittenText: String {
        guard let diskBytesWritten else { return "—" }
        return diskBytesWritten == 0 ? "0 B" : KBFormat.bytes(diskBytesWritten)
    }

    var logicalWritesText: String {
        logicalWrites.map { $0.formatted() } ?? "—"
    }

    var timeText: String {
        guard let usage = process.usage else { return "—" }
        return KBFormat.cpuDuration(usage.cpuTimeNanoseconds)
    }

    var stateText: String {
        process.state?.rawValue ?? "—"
    }

    var stateHelp: String {
        process.state?.displayName ?? "Unavailable"
    }

    /// Compact htop-style columns kept within SwiftUI's 10-column Table limit.
    var priorityNiceText: String {
        "\(priorityText)/\(niceText)"
    }

    var stateThreadsText: String {
        "\(stateText)/\(threadsText)"
    }

    var commandText: String {
        if !process.name.isEmpty { return process.name }
        if !process.path.isEmpty { return (process.path as NSString).lastPathComponent }
        return "PID \(process.pid)"
    }

    func matches(_ query: String, userNames: [UInt32: String]) -> Bool {
        process.matchesSearch(query, userNames: userNames)
    }
}
