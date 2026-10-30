import Darwin
import Dispatch
import Foundation
import KancerberoCore

private func write(_ text: String, to handle: FileHandle = .standardOutput) {
    if let data = text.data(using: .utf8) {
        handle.write(data)
    }
}

private func fail(_ message: String) -> Never {
    write("error: \(message)\n", to: .standardError)
    exit(1)
}

private func formatBytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
}

private func printVersion() {
    write("kancerbero probe \(KBVersion.current) (core \(KBVersion.coreVersion), schema \(KBVersion.schema))\n")
}

private func printSymbols() {
    let availability = NStatCollector.availability()
    write("NetworkStatistics: \(availability.available ? "available" : "unavailable")\n")
    if !availability.available {
        write("  reason: \(availability.message)\n")
    }
    var privcheck: Int32 = -1
    let rc = kb_sysctl_int("net.statistics_privcheck", &privcheck)
    write("net.statistics_privcheck: \(rc == 0 ? String(privcheck) : "unreadable")\n")
    write("euid: \(geteuid()) root: \(geteuid() == 0 ? "yes" : "no")\n")
}

private func printProcesses(limit: Int) {
    do {
        let items = try ProcessCollector.snapshot()
        write("processes: \(items.count) (showing \(min(limit, items.count)))\n")
        for item in items.sorted(by: { $0.pid < $1.pid }).prefix(limit) {
            let path = item.path.isEmpty ? "-" : item.path
            write(String(format: "%7d %7d uid=%-5u %-24@ %@\n",
                         item.pid, item.ppid, item.uid,
                         item.name as NSString, path as NSString))
        }
    } catch {
        fail(error.localizedDescription)
    }
}

private func formatPercent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.1f%%", value)
}

private func formatDuration(_ nanoseconds: UInt64) -> String {
    let total = nanoseconds / 1_000_000_000
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return String(format: "%d:%02d:%02d", hours, minutes, seconds)
}

private func printCPU(interval: Double) {
    var sampler = HostMetricsSampler()
    var energyTracker = ProcessCPUTracker()
    var before = (try? ProcessCollector.snapshot()) ?? []
    energyTracker.annotate(&before, elapsed: 0, totalMemoryBytes: 0, coreCount: 1)
    _ = sampler.sample(processes: before)
    Thread.sleep(forTimeInterval: max(0.1, interval))
    var after = (try? ProcessCollector.snapshot()) ?? []
    guard let metrics = sampler.sample(processes: after) else {
        fail("host metrics unavailable")
    }
    energyTracker.annotate(&after,
                           elapsed: max(0.1, interval),
                           totalMemoryBytes: metrics.memory.totalBytes,
                           coreCount: metrics.cpu.coreCount)

    write("cpu cores=\(metrics.cpu.coreCount) load=\(String(format: "%.2f", metrics.cpu.load1))/\(String(format: "%.2f", metrics.cpu.load5))/\(String(format: "%.2f", metrics.cpu.load15))\n")
    for core in metrics.cpu.cores {
        write(String(format: "  cpu%-3d user=%5.1f%% system=%5.1f%% nice=%5.1f%% idle=%5.1f%% usage=%5.1f%%\n",
                     core.index + 1, core.userPercent, core.systemPercent,
                     core.nicePercent, core.idlePercent, core.usagePercent))
    }
    let cpu = metrics.cpu
    write(String(format: "aggregate user=%.1f%% system=%.1f%% nice=%.1f%% idle=%.1f%% usage=%.1f%%\n",
                 cpu.userPercent, cpu.systemPercent, cpu.nicePercent,
                 cpu.idlePercent, cpu.totalUsagePercent))
    write("tasks=\(cpu.taskCount) threads=\(cpu.threadCount) restricted=\(cpu.threadsRestricted) uptime=\(formatDuration(UInt64(cpu.uptimeSeconds * 1_000_000_000)))\n")
    let memory = metrics.memory
    write("memory used=\(formatBytes(memory.usedBytes)) active=\(formatBytes(memory.activeBytes)) wired=\(formatBytes(memory.wiredBytes)) compressed=\(formatBytes(memory.compressedBytes)) cached=\(formatBytes(memory.cachedBytes)) free=\(formatBytes(memory.barFreeBytes)) total=\(formatBytes(memory.totalBytes))\n")
    write("memoryAM app=\(formatBytes(memory.appMemoryBytes)) cachedFiles=\(formatBytes(memory.cachedFileBytes)) used=\(formatBytes(memory.activityMonitorUsedBytes)) free=\(formatBytes(memory.activityMonitorFreeBytes))\n")
    write("swap used=\(formatBytes(memory.swapUsedBytes)) total=\(formatBytes(memory.swapTotalBytes)) encrypted=\(memory.swapEncrypted ? 1 : 0)\n")
    write("pressure percent=\(memory.pressurePercent.map(String.init) ?? "n/a") level=\(memory.pressureLevel.map(String.init) ?? "n/a") band=\(memory.pressureLabel)\n")
    if let gpu = metrics.gpu {
        let utilization = gpu.utilizationPercent.map { String(format: "%.1f", $0) } ?? "n/a"
        let renderer = gpu.rendererPercent.map { String(format: "%.1f", $0) } ?? "n/a"
        let tiler = gpu.tilerPercent.map { String(format: "%.1f", $0) } ?? "n/a"
        let inUse = gpu.inUseMemoryBytes.map(formatBytes) ?? "n/a"
        let allocated = gpu.allocatedMemoryBytes.map(formatBytes) ?? "n/a"
        write("gpu name=\(gpu.name ?? "unknown") util=\(utilization)% renderer=\(renderer)% tiler=\(tiler)% inuse=\(inUse) alloc=\(allocated)\n")
    } else {
        write("gpu unavailable\n")
    }
    if let top = after.max(by: {
        ($0.usage?.energyWatts ?? 0) < ($1.usage?.energyWatts ?? 0)
    }), let watts = top.usage?.energyWatts {
        write(String(format: "energy top=%@ %.2fW wakeups=%.1f/s\n",
                     top.name, watts, top.usage?.wakeupsPerSecond ?? 0))
    }
    if let power = metrics.power {
        write("power battery=\(power.hasBattery ? 1 : 0) charge=\(power.chargePercent.map(String.init) ?? "n/a") charging=\(power.isCharging ? 1 : 0) plugged=\(power.isPluggedIn ? 1 : 0) minutes=\(power.timeRemainingMinutes.map(String.init) ?? "n/a") source=\(power.source ?? "n/a")\n")
    } else {
        write("power unavailable\n")
    }
    if let sleeping = PowerAssertionsReader.current() {
        write("preventingSleep pids=\(sleeping.sorted().map(String.init).joined(separator: ","))\n")
    }
    if let io = DiskIOReader.current() {
        write("disk read=\(formatBytes(io.bytesRead)) written=\(formatBytes(io.bytesWritten)) readOps=\(io.readOperations) writeOps=\(io.writeOperations)\n")
    }
    if let top = after.max(by: {
        (($0.usage?.diskBytesReadPerSecond ?? 0) + ($0.usage?.diskBytesWrittenPerSecond ?? 0))
            < (($1.usage?.diskBytesReadPerSecond ?? 0) + ($1.usage?.diskBytesWrittenPerSecond ?? 0))
    }), (top.usage?.diskBytesReadPerSecond ?? 0) + (top.usage?.diskBytesWrittenPerSecond ?? 0) > 0 {
        write(String(format: "diskTop %@ read=%.0fB/s write=%.0fB/s writes=%@\n",
                     top.name,
                     top.usage?.diskBytesReadPerSecond ?? 0,
                     top.usage?.diskBytesWrittenPerSecond ?? 0,
                     top.usage?.logicalWrites.map(String.init) ?? "n/a"))
    }
}

private func printApps() {
    let inventory = AppInventoryCollector.snapshot()
    write("apps: \(inventory.bundles.count)\n")
    for bundle in inventory.bundles {
        write(String(format: "  %-28@ %-12@ %-8@ %-6@ %@\n",
                     bundle.name as NSString,
                     (bundle.bundleIdentifier ?? "—") as NSString,
                     bundle.kind.rawValue as NSString,
                     bundle.scope.title as NSString,
                     bundle.path as NSString))
    }
    guard let wanted = ProcessInfo.processInfo.environment["KB_APPS_LEFTOVERS"] else {
        return
    }
    guard let bundle = inventory.bundles.first(where: {
        $0.path == wanted || $0.bundleIdentifier == wanted
    }) else {
        write("leftovers: bundle not found\n")
        return
    }
    let leftovers = AppLeftoversCollector.leftovers(for: bundle)
    write("leftovers for \(bundle.name): \(leftovers.count)\n")
    for item in leftovers {
        write(String(format: "  %-18@ %10lld %@%@\n",
                     item.kind.title as NSString,
                     item.sizeBytes ?? 0,
                     item.requiresPrivilege ? "[admin] " : "",
                     item.path as NSString))
    }
}

private func printProcessesCPU(limit: Int, interval: Double) {
    var sampler = HostMetricsSampler()
    var tracker = ProcessCPUTracker()
    let started = DispatchTime.now().uptimeNanoseconds
    var processes = (try? ProcessCollector.snapshot()) ?? []
    let firstHost = sampler.sample(processes: processes)
    tracker.annotate(&processes, elapsed: 0,
                     totalMemoryBytes: firstHost?.memory.totalBytes ?? 0,
                     coreCount: firstHost?.cpu.coreCount ?? 1)

    Thread.sleep(forTimeInterval: max(0.1, interval))
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    processes = (try? ProcessCollector.snapshot()) ?? []
    let host = sampler.sample(processes: processes)
    tracker.annotate(&processes, elapsed: elapsed,
                     totalMemoryBytes: host?.memory.totalBytes ?? 0,
                     coreCount: host?.cpu.coreCount ?? 1)

    write(String(format: "%7@ %-16@ %-2@ %5@ %5@ %5@ %8@ %7@ %10@ %10@ %-10@ %@\n",
                 "PID" as NSString, "USER" as NSString, "S" as NSString,
                 "PRI" as NSString, "NI" as NSString, "THR" as NSString,
                 "CPU%" as NSString, "MEM%" as NSString,
                 "RSS" as NSString, "VSZ" as NSString, "TIME+" as NSString,
                 "COMMAND" as NSString))
    let sorted = processes.sorted {
        ($0.usage?.cpuPercent ?? -1) > ($1.usage?.cpuPercent ?? -1)
    }
    for item in sorted.prefix(limit) {
        let usage = item.usage
        let state = item.state?.rawValue ?? "?"
        let priority = usage.map { String($0.priority) } ?? "—"
        let nice = item.nice.map { String($0) } ?? "—"
        let threads = usage.map { String($0.threads) } ?? "—"
        let cpuPercent = formatPercent(usage?.cpuPercent)
        let memoryPercent = formatPercent(usage?.memoryPercent)
        let resident = usage.map { formatBytes($0.residentBytes) } ?? "—"
        let virtual = usage.map { formatBytes($0.virtualBytes) } ?? "—"
        let time = usage.map { formatDuration($0.cpuTimeNanoseconds) } ?? "—"
        let user = UserCollector.name(for: item.uid) ?? "\(item.uid)"
        write(String(format: "%7d %-16@ %-2@ %5@ %5@ %5@ %8@ %7@ %10@ %10@ %-10@ %@\n",
                     item.pid, user as NSString, state as NSString,
                     priority as NSString, nice as NSString, threads as NSString,
                     cpuPercent as NSString, memoryPercent as NSString,
                     resident as NSString, virtual as NSString, time as NSString,
                     item.name as NSString))
    }
}

private func printInterfaces() {
    do {
        let items = try InterfaceCollector.snapshot()
        write("interfaces: \(items.count)\n")
        for item in items.sorted(by: { $0.index < $1.index }) {
            let state = item.isUp ? (item.isRunning ? "up" : "up,not-running") : "down"
            write(String(format: "%-8@ idx=%-3u %-14@ %-16@ rx=%-12@ tx=%-12@ mtu=%u\n",
                         item.name as NSString, item.index, state as NSString,
                         item.kind.displayName as NSString,
                         formatBytes(item.counters.rxBytes) as NSString,
                         formatBytes(item.counters.txBytes) as NSString,
                         item.mtu))
        }
    } catch {
        fail(error.localizedDescription)
    }
}

private struct Aggregate {
    var name: String = ""
    var rx: UInt64 = 0
    var tx: UInt64 = 0
    var connections: Int = 0
}

private func printSockets(pid: Int32) {
    do {
        let sockets = try SocketCollector.snapshot(pid: pid)
        write("sockets: \(sockets.count) (pid \(pid))\n")
        for item in sockets {
            write(String(format: "  fd=%-4d %-6@ %-22@ -> %-22@ %@\n",
                         item.fd,
                         item.protocolLabel as NSString,
                         item.local.display as NSString,
                         item.remote.display as NSString,
                         item.stateName as NSString))
        }
    } catch {
        fail(error.localizedDescription)
    }
}

private func printSocketSummary(_ inventory: KBSocketInventory) {
    write("sockets-summary: processes=\(inventory.summaries.count) scanned=\(inventory.scannedProcesses) restricted=\(inventory.restrictedProcesses) duration=\(String(format: "%.1f", inventory.durationMilliseconds))ms\n")
    for item in inventory.summaries where item.uniqueSockets > 0 || item.restricted {
        let b = item.buckets
        let t = item.types
        let protos = (item.otherProtocols ?? [])
            .map { KBIPProtocol.name(for: Int32($0)) }
            .sorted()
        write(String(format: "  pid=%-7d sockets=%-4d tcp4=%d tcp6=%d udp4=%d udp6=%d unix=%d raw4=%d raw6=%d other=%d types=[stream=%d dgram=%d raw=%d seq=%d other=%d] inet-protos=[%@] restricted=%d truncated=%d\n",
                     item.key.pid, item.uniqueSockets,
                     b.tcp4, b.tcp6, b.udp4, b.udp6, b.unix, b.raw4, b.raw6, b.other,
                     t.stream, t.dgram, t.raw, t.seqpacket, t.otherType,
                     (protos.isEmpty ? "-" : protos.joined(separator: ",")) as NSString,
                     item.restricted ? 1 : 0, item.truncated ? 1 : 0))
    }
}

private func printFiles(pid: Int32) {
    do {
        let files = try OpenFileCollector.snapshot(pid: pid)
        write("open files: \(files.count) (pid \(pid))\n")
        for item in files.prefix(60) {
            write(String(format: "  fd=%-4d %-14@ %10llu  %@\n",
                         item.fd, item.typeName as NSString,
                         item.size, item.path as NSString))
        }
    } catch {
        fail(error.localizedDescription)
    }
}

private func printSources() {
    let collector = NStatCollector()
    do {
        try collector.start()
    } catch {
        fail(error.localizedDescription)
    }
    defer { collector.stop() }
    Thread.sleep(forTimeInterval: 1.5)
    _ = collector.poll(timeoutMilliseconds: 800)
    let sources = collector.snapshot()
    write("sources: \(sources.count)\n")
    for source in sources.sorted(by: { ($0.pid, $0.local.display) < ($1.pid, $1.local.display) }) {
        write(String(format: "id=%-5llu pid=%-7d %-12@ %-5@ %-22@ -> %-22@ %-11@ uuid=%@ if=%@\n",
                     source.sourceID,
                     source.pid,
                     (source.processName.isEmpty ? "?" : source.processName) as NSString,
                     source.provider as NSString,
                     source.local.display as NSString,
                     source.remote.display as NSString,
                     source.tcpState as NSString,
                     (source.uuid.isEmpty ? "-" : source.uuid) as NSString,
                     source.interfaceName as NSString))
    }
}

private func printDaemons(domain: KBDaemonDomain) {
    let snapshot = DaemonsCollector(domain: domain).snapshot()
    write("daemons domain=\(domain.rawValue) source=\(snapshot.source) count=\(snapshot.services.count) error=\(snapshot.error ?? "-")\n")
    for service in snapshot.services.prefix(25) {
        write(String(format: "  %-52@ pid=%-7@ state=%-9@ program=%-46@ plist=%@\n",
                     service.label as NSString,
                     (service.pid.map { String($0) } ?? "—") as NSString,
                     service.state.rawValue as NSString,
                     (service.program.isEmpty ? "—" : service.program) as NSString,
                     (service.plistPath.isEmpty ? "—" : (service.plistPath as NSString).lastPathComponent) as NSString))
    }
}

private func printDiskVolumes() {
    let snapshot = DiskInventoryCollector().snapshot()
    write("disk inventory source=\(snapshot.source) roots=\(snapshot.items.count) error=\(snapshot.error ?? "-")\n")

    func visit(_ item: KBDiskItem, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        let used = item.usedBytes.map(formatBytes) ?? "-"
        let free = item.freeBytes.map(formatBytes) ?? "-"
        let available = item.availableBytes.map(formatBytes) ?? "-"
        write("\(indent)\(item.deviceIdentifier) \(item.kind.rawValue) \"\(item.name)\" fs=\(item.fileSystem ?? "-") size=\(formatBytes(item.sizeBytes)) used=\(used) free=\(free) available=\(available) mount=\(item.mountPoint ?? "-") roles=\(item.roles.joined(separator: ","))\n")
        for child in item.children {
            visit(child, depth: depth + 1)
        }
    }

    for item in snapshot.items {
        visit(item, depth: 0)
    }
}

private func printDiskInfo(_ identifier: String) {
    let snapshot = DiskInventoryCollector().snapshot()
    guard let item = snapshot.allItems.first(where: { $0.deviceIdentifier == identifier }) else {
        fail("disk not found: \(identifier)")
    }

    write("identifier: \(item.deviceIdentifier)\n")
    write("kind: \(item.kind.rawValue)\n")
    write("name: \(item.name)\n")
    write("filesystem: \(item.fileSystem ?? "-")\n")
    write("content: \(item.content ?? "-")\n")
    write("mount: \(item.mountPoint ?? "-")\n")
    write("size: \(formatBytes(item.sizeBytes))\n")
    write("used: \(item.usedBytes.map(formatBytes) ?? "-")\n")
    write("free: \(item.freeBytes.map(formatBytes) ?? "-")\n")
    write("available: \(item.availableBytes.map(formatBytes) ?? "-")\n")
    write("volume-uuid: \(item.volumeUUID ?? "-")\n")
    write("media-uuid: \(item.mediaUUID ?? "-")\n")
    write("group-uuid: \(item.volumeGroupUUID ?? "-")\n")
    write("roles: \(item.roles.joined(separator: ","))\n")
    write("internal: \(item.isInternal.map { $0 ? "yes" : "no" } ?? "-")\n")
    write("removable: \(item.isRemovable.map { $0 ? "yes" : "no" } ?? "-")\n")
    write("writable: \(item.isWritable.map { $0 ? "yes" : "no" } ?? "-")\n")
    write("encrypted: \(item.isEncrypted.map { $0 ? "yes" : "no" } ?? "-")\n")
    write("model: \(item.deviceModel ?? "-")\n")
    write("protocol: \(item.deviceProtocol ?? "-")\n")
    write("bus: \(item.busName ?? "-")\n")
    write("parent: \(item.parentID ?? "-")\n")
}

private func printDiskScan(path: String, top: Int, includeHidden: Bool) {
    var options = KBDiskScanOptions()
    options.largestFilesLimit = max(top, 10)
    options.includeHiddenInLargestFiles = includeHidden

    let snapshot = DiskScanner.scan(rootPath: path, options: options) { _ in }
    write("scan root=\(snapshot.root.path) bytes=\(formatBytes(snapshot.root.allocatedBytes)) logical=\(formatBytes(snapshot.root.logicalBytes)) files=\(snapshot.root.fileCount) folders=\(snapshot.root.folderCount) denied=\(snapshot.deniedPaths.count) duration=\(String(format: "%.2f", snapshot.duration))s cancelled=\(snapshot.cancelled) error=\(snapshot.error ?? "-")\n")

    write("folders:\n")
    for child in snapshot.root.children.prefix(max(top, 1)) {
        let percent = snapshot.root.allocatedBytes > 0
            ? Double(child.allocatedBytes) / Double(snapshot.root.allocatedBytes) * 100
            : 0
        write(String(format: "  %6.1f%% %12@ files=%-8d folders=%-8d %@\n",
                     percent,
                     formatBytes(child.allocatedBytes) as NSString,
                     child.fileCount,
                     child.folderCount,
                     child.path as NSString))
    }

    write("largest files:\n")
    for file in snapshot.largestFiles.prefix(max(top, 1)) {
        write(String(format: "  %12@ logical=%-12@ %@\n",
                     formatBytes(file.allocatedBytes) as NSString,
                     formatBytes(file.logicalBytes) as NSString,
                     file.path as NSString))
    }

    if !snapshot.deniedPaths.isEmpty {
        write("denied:\n")
        for denied in snapshot.deniedPaths.prefix(20) {
            write("  \(denied)\n")
        }
    }
}


private func printNStat(seconds: Int) {
    let collector = NStatCollector()
    do {
        try collector.start()
    } catch {
        fail(error.localizedDescription)
    }
    defer { collector.stop() }

    write("nstat: sampling \(seconds)s (1s interval)\n")
    for second in 0..<seconds {
        Thread.sleep(forTimeInterval: 1.0)
        let pollStart = Date()
        let ok = collector.poll(timeoutMilliseconds: 400)
        let elapsed = Date().timeIntervalSince(pollStart)
        let sources = collector.snapshot()

        var byPID: [Int32: Aggregate] = [:]
        for source in sources {
            let pid = source.epid != 0 ? source.epid : source.pid
            var aggregate = byPID[pid] ?? Aggregate(name: source.processName, rx: 0, tx: 0, connections: 0)
            if aggregate.name.isEmpty && !source.processName.isEmpty {
                aggregate.name = source.processName
            }
            aggregate.rx &+= source.counters.rxBytes
            aggregate.tx &+= source.counters.txBytes
            aggregate.connections += 1
            byPID[pid] = aggregate
        }

        write(String(format: "t=%ds poll=%@ %.0fms sources=%d processes=%d\n",
                     second + 1, ok ? "ok" : "partial", elapsed * 1000, sources.count, byPID.count))
        let top = byPID.sorted { ($0.value.rx + $0.value.tx) > ($1.value.rx + $1.value.tx) }.prefix(8)
        for (pid, aggregate) in top {
            write(String(format: "  %-24@ pid=%-7d conns=%-3d rx=%-12@ tx=%-12@\n",
                         (aggregate.name.isEmpty ? "?" : aggregate.name) as NSString,
                         pid, aggregate.connections,
                         formatBytes(aggregate.rx) as NSString,
                         formatBytes(aggregate.tx) as NSString))
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "all"
let remainder = Array(arguments.dropFirst())

func integerOption(_ name: String, default defaultValue: Int) -> Int {
    guard let index = remainder.firstIndex(of: name), index + 1 < remainder.count,
          let value = Int(remainder[index + 1]) else {
        return defaultValue
    }
    return value
}

func doubleOption(_ name: String, default defaultValue: Double) -> Double {
    guard let index = remainder.firstIndex(of: name), index + 1 < remainder.count,
          let value = Double(remainder[index + 1]) else {
        return defaultValue
    }
    return value
}

switch command {
case "version":
    printVersion()
case "symbols":
    printSymbols()
case "procs":
    if remainder.contains("--cpu") {
        printProcessesCPU(limit: integerOption("--limit", default: 20),
                          interval: doubleOption("--interval", default: 1))
    } else {
        printProcesses(limit: integerOption("--limit", default: 20))
    }
case "cpu":
    printCPU(interval: doubleOption("--interval", default: 1))
case "apps":
    printApps()
case "ifaces":
    printInterfaces()
case "sockets":
    guard let pid = Int32(remainder.first ?? "") else {
        fail("usage: KancerberoProbe sockets <pid>")
    }
    printSockets(pid: pid)
case "sockets-summary":
    let allProcesses: [KBProcessInfo]
    do {
        allProcesses = try ProcessCollector.snapshot()
    } catch {
        fail(error.localizedDescription)
    }
    let processes: [KBProcessInfo]
    if remainder.isEmpty {
        processes = allProcesses
    } else {
        let wanted = Set(remainder.compactMap { Int32($0) })
        let byPID = Dictionary(uniqueKeysWithValues: allProcesses.map { ($0.pid, $0) })
        processes = wanted.map { byPID[$0] ?? KBProcessInfo(pid: $0) }
    }
    printSocketSummary(SocketSummaryCollector.summaries(for: processes))
case "files":
    guard let pid = Int32(remainder.first ?? "") else {
        fail("usage: KancerberoProbe files <pid>")
    }
    printFiles(pid: pid)
case "daemons":
    let raw = remainder.first ?? "system"
    printDaemons(domain: KBDaemonDomain(rawValue: raw) ?? .system)
case "disk":
    let subcommand = remainder.first ?? "volumes"
    switch subcommand {
    case "volumes":
        printDiskVolumes()
    case "info":
        guard remainder.count >= 2 else {
            fail("usage: disk info <deviceIdentifier>")
        }
        printDiskInfo(remainder[1])
    case "scan":
        guard remainder.count >= 2 else {
            fail("usage: disk scan <path> [--top N] [--hidden]")
        }
        printDiskScan(path: remainder[1],
                      top: integerOption("--top", default: 20),
                      includeHidden: remainder.contains("--hidden"))
    default:
        fail("usage: disk <volumes|info <device>|scan <path>>")
    }
case "daemon-action":
    guard remainder.count >= 3,
          let domain = KBDaemonDomain(rawValue: remainder[0]),
          let action = KBDaemonAction(rawValue: remainder[1]) else {
        fail("usage: daemon-action <system|gui|user> <start|stop|restart|enable|disable|load|unload> <label> [plist]")
    }
    let plist = remainder.count > 3 ? remainder[3] : nil
    let result = LaunchctlRunner.action(KBDaemonActionRequest(
        label: remainder[2], domain: domain, action: action, plistPath: plist))
    write("status=\(result.status) ok=\(result.ok) timedOut=\(result.timedOut)\n")
    write("stdout: \(result.stdout)\n")
    write("stderr: \(result.stderr)\n")
case "sources":
    printSources()
case "nstat":
    printNStat(seconds: integerOption("--seconds", default: 5))
case "all":
    printVersion()
    printSymbols()
    printProcesses(limit: integerOption("--limit", default: 10))
    printInterfaces()
    printNStat(seconds: integerOption("--seconds", default: 3))
default:
    fail("unknown command '\(command)'. Use: version|symbols|procs [--cpu]|cpu|apps|ifaces|sockets <pid>|sockets-summary [pid...]|files <pid>|daemons|disk|nstat|all")
}
