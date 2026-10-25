import Foundation
import Observation
import ServiceManagement
import SwiftUI
import KancerberoCore

@MainActor
@Observable
final class AppModel {
    var interfaces: [KBInterfaceInfo] = []
    var interfaceRates: [UInt32: KBRates] = [:]
    var processes: [KBProcessInfo] = []
    var sources: [KBNStatSource] = []
    var mode: KBMode = .localDegraded
    var privcheck: Int32 = -1
    var lastError: String?
    var lastUpdate: Date?
    var isPaused = false
    var interval: TimeInterval = 1.0
    var usingDaemon = false
    var daemonVersion: String?
    var rxHistory: [Double] = []
    var txHistory: [Double] = []
    var systemDaemons: [KBDaemonService] = []
    var localDaemons: [KBDaemonService] = []
    var daemonServicesError: String?
    var daemonLastUpdate: Date?
    var daemonActionInFlight = false
    var daemonActionMessage: String?
    var daemonIsRoot = false
    var socketInventory: KBSocketInventory?
    var processInventory: [ProcessInventoryRow] = []
    var hostMetrics: KBHostMetrics?
    var cpuProcessRows: [CPUProcessRow] = []
    var userNames: [UInt32: String] = [:]
    var cpuUsageHistory: [Double] = []
    var loadHistory: [Double] = []
    var threadHistory: [Double] = []
    var memoryUsageHistory: [Double] = []
    var serviceStatus: SMAppService.Status = .notRegistered
    var serviceError: String?
    var legacyServiceDetected = false

    var daemonEntries: [DaemonListEntry] {
        DaemonDeduplicator.entries(system: systemDaemons, local: localDaemons)
    }

    var allDaemons: [KBDaemonService] {
        daemonEntries.map(\.service)
    }

    var canControlSystem: Bool { usingDaemon && daemonIsRoot }

    var isLive: Bool {
        guard let lastUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < max(3.0, interval * 2.5)
    }

    private let collector = CollectionActor()
    private var daemonSource: DaemonMetricsSource?
    private var task: Task<Void, Never>?
    private static let daemonServicePlist = "uno.kayros.kancerbero.daemon.plist"

    private var daemonService: SMAppService {
        .daemon(plistName: Self.daemonServicePlist)
    }
    private var previousSourceCounters: [String: KBCounters] = [:]
    private var previousInterfaceCounters: [UInt32: KBCounters] = [:]
    private var previousTimestamp: UInt64 = 0
    private var daemonConnecting = false
    private var lastDaemonAttempt = Date.distantPast
    private var resolvingUIDs: Set<UInt32> = []

    var isRoot: Bool { geteuid() == 0 }

    var modeDescription: String {
        if usingDaemon {
            switch mode {
            case .daemonFull: return "Daemon (full access)"
            case .daemonRestricted: return "Daemon (restricted)"
            default: return "Daemon"
            }
        }
        switch mode {
        case .localFullNStat: return "Local (NetworkStatistics)"
        case .localDegraded: return "Local (degraded)"
        case .interfacesOnly: return "Interfaces only"
        default: return "Local"
        }
    }

    var systemRates: KBRates {
        var result = KBRates.zero
        for item in interfaces where !item.isLoopback && item.kind != .tunnel {
            if let rate = interfaceRates[item.id] {
                result.rxBytesPerSecond += rate.rxBytesPerSecond
                result.txBytesPerSecond += rate.txBytesPerSecond
                result.rxPacketsPerSecond += rate.rxPacketsPerSecond
                result.txPacketsPerSecond += rate.txPacketsPerSecond
            }
        }
        return result
    }

    func start() {
        guard task == nil else { return }
        refreshServiceStatus()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshServiceStatus()
                if !self.isPaused && !self.usingDaemon {
                    await self.refreshOnce()
                }
                if !self.usingDaemon && !self.daemonConnecting,
                   Date().timeIntervalSince(self.lastDaemonAttempt) > 30 {
                    self.lastDaemonAttempt = Date()
                    self.connectDaemon()
                }
                let interval = self.isPaused ? 0.5 : self.interval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
        connectDaemon()
    }

    func refreshServiceStatus() {
        serviceStatus = daemonService.status
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        legacyServiceDetected =
            FileManager.default.fileExists(
                atPath: "\(home)/Library/LaunchAgents/uno.kayros.kancerbero.agent.plist")
            || FileManager.default.fileExists(
                atPath: "/Library/LaunchDaemons/uno.kayros.kancerbero.daemon.plist")
    }

    func registerDaemonService() async {
        serviceError = nil
        if legacyServiceDetected {
            serviceError = "Remove the legacy agent first: scripts/uninstall-agent.sh"
            return
        }
        let plistName = Self.daemonServicePlist
        do {
            try await Task.detached(priority: .userInitiated) {
                try SMAppService.daemon(plistName: plistName).register()
            }.value
        } catch {
            let nsError = error as NSError
            // kSMErrorAlreadyRegistered = 12
            if nsError.code != 12 {
                serviceError = nsError.localizedDescription
            }
        }
        refreshServiceStatus()
        if serviceStatus == .requiresApproval {
            openLoginItemsSettings()
        }
        if serviceStatus == .enabled {
            lastDaemonAttempt = .distantPast
            connectDaemon()
        }
    }

    func unregisterDaemonService() async {
        daemonSource?.stop()
        daemonSource = nil
        usingDaemon = false
        daemonIsRoot = false
        serviceError = nil
        let plistName = Self.daemonServicePlist
        do {
            try await Task.detached(priority: .userInitiated) {
                try SMAppService.daemon(plistName: plistName).unregister()
            }.value
        } catch {
            let nsError = error as NSError
            // kSMErrorJobNotFound = 6
            if nsError.code != 6 {
                serviceError = nsError.localizedDescription
            }
        }
        refreshServiceStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func stop() {
        task?.cancel()
        task = nil
        daemonSource?.stop()
        daemonSource = nil
        usingDaemon = false
        daemonIsRoot = false
        Task { await collector.stop() }
    }

    func refreshNow() {
        Task { await refreshOnce() }
    }

    func refreshDaemons() async {
        let uid = getuid()
        let useDaemon = usingDaemon
        let source = daemonSource

        let localTask = Task.detached(priority: .utility) {
            () -> ([KBDaemonService], String?) in
            let gui = DaemonsCollector(domain: .gui, uid: uid).snapshot()
            let user = DaemonsCollector(domain: .user, uid: uid).snapshot()
            return (gui.services + user.services, gui.error ?? user.error)
        }

        let systemTask = Task.detached(priority: .utility) {
            () -> ([KBDaemonService], String?) in
            if useDaemon, let source {
                do {
                    let snapshot = try source.requestDaemonServices()
                    return (snapshot.services, nil)
                } catch let caught {
                    let fallback = DaemonsCollector(domain: .system, uid: uid).snapshot()
                    return (fallback.services, fallback.error ?? caught.localizedDescription)
                }
            }
            let fallback = DaemonsCollector(domain: .system, uid: uid).snapshot()
            return (fallback.services, fallback.error)
        }

        let local = await localTask.value
        localDaemons = local.0
        // Let the table settle between the two updates; the system list is
        // larger and used to trigger a re-entrant NSTableView layout warning.
        try? await Task.sleep(for: .milliseconds(250))
        let system = await systemTask.value
        systemDaemons = system.0
        daemonServicesError = local.1 ?? system.1
        daemonLastUpdate = Date()
    }

    func performDaemonAction(_ request: KBDaemonActionRequest) async -> KBDaemonActionResult {
        daemonActionInFlight = true
        defer { daemonActionInFlight = false }

        let result: KBDaemonActionResult
        if request.domain == .system {
            guard usingDaemon, canControlSystem, let source = daemonSource else {
                let message = usingDaemon
                    ? "The daemon is not running as root; system services are read-only."
                    : "Install the root daemon to control system services."
                daemonActionMessage = message
                return KBDaemonActionResult(ok: false, message: message)
            }
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try source.performDaemonAction(request)
                }.value
            } catch {
                result = KBDaemonActionResult(ok: false, message: error.localizedDescription)
            }
        } else {
            result = await Task.detached(priority: .userInitiated) {
                let run = LaunchctlRunner.action(request)
                let snapshot = DaemonsCollector(domain: request.domain).snapshot()
                let message = run.ok
                    ? "\(request.action.rawValue) \(request.label)"
                    : (run.stderr.isEmpty
                       ? "launchctl failed"
                       : run.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                return KBDaemonActionResult(ok: run.ok, message: message, snapshot: snapshot)
            }.value
        }

        daemonActionMessage = result.ok
            ? "\(request.action.rawValue.capitalized) \(request.label)"
            : result.message
        await refreshDaemons()
        return result
    }

    func detail(for process: KBProcessInfo) async -> KBProcessDetail {
        let pid = process.pid
        if usingDaemon, let source = daemonSource {
            if let detail = try? await Task.detached(priority: .userInitiated, operation: {
                try source.requestDetail(pid: pid)
            }).value {
                return detail
            }
        }
        return await Task.detached {
            do {
                let sockets = try SocketCollector.snapshot(pid: pid)
                let files = try OpenFileCollector.snapshot(pid: pid)
                let openFiles = files.map {
                    KBOpenFileSample(fd: $0.fd, type: $0.typeName, path: $0.path,
                                     size: Int64(clamping: $0.size))
                }
                return KBProcessDetail(process: process, sockets: sockets, openFiles: openFiles)
            } catch {
                return KBProcessDetail(process: process, restricted: true,
                                       source: "libproc", processGone: true)
            }
        }.value
    }

    private func connectDaemon() {
        guard !daemonConnecting else { return }
        daemonConnecting = true
        lastDaemonAttempt = Date()
        let requestedInterval = interval
        let privileged = serviceStatus == .enabled
        Task { [weak self] in
            let source = DaemonMetricsSource()
            source.onCollection = { [weak self] snapshot in
                Task { @MainActor in
                    guard let self, !self.isPaused else { return }
                    self.usingDaemon = true
                    self.apply(snapshot)
                }
            }
            source.onInvalidate = { [weak self] in
                Task { @MainActor in
                    self?.usingDaemon = false
                    self?.daemonVersion = nil
                    self?.daemonIsRoot = false
                }
            }
            do {
                let hello = try await Task.detached(priority: .utility) {
                    do {
                        return try source.start(interval: requestedInterval,
                                                privileged: privileged)
                    } catch {
                        if privileged {
                            return try source.start(interval: requestedInterval,
                                                    privileged: false)
                        }
                        throw error
                    }
                }.value
                guard let self else { return }
                self.daemonSource = source
                self.daemonVersion = hello.daemonVersion
                self.daemonIsRoot = hello.capabilities.root
                self.usingDaemon = true
                self.daemonConnecting = false
            } catch {
                source.stop()
                self?.daemonConnecting = false
            }
        }
    }

    private func refreshOnce() async {
        let snapshot = await collector.refresh()
        apply(snapshot)
    }

    private func apply(_ snapshot: KBCollectionSnapshot) {
        let now = snapshot.monotonicNanoseconds
        let elapsed = previousTimestamp == 0
            ? 0
            : Double(now &- previousTimestamp) / 1_000_000_000.0
        let validInterval = elapsed > 0 && elapsed < 5.0

        var sources = snapshot.sources
        var rates: [UInt32: KBRates] = [:]

        if validInterval {
            for index in sources.indices {
                let id = sources[index].id
                if let previous = previousSourceCounters[id] {
                    let delta = subtract(sources[index].counters, previous)
                    sources[index].rates = KBRates(
                        rxBytesPerSecond: Double(delta.rxBytes) / elapsed,
                        txBytesPerSecond: Double(delta.txBytes) / elapsed,
                        rxPacketsPerSecond: Double(delta.rxPackets) / elapsed,
                        txPacketsPerSecond: Double(delta.txPackets) / elapsed
                    )
                }
            }
            for item in snapshot.interfaces {
                if let previous = previousInterfaceCounters[item.id] {
                    let delta = subtract(item.counters, previous)
                    rates[item.id] = KBRates(
                        rxBytesPerSecond: Double(delta.rxBytes) / elapsed,
                        txBytesPerSecond: Double(delta.txBytes) / elapsed,
                        rxPacketsPerSecond: Double(delta.rxPackets) / elapsed,
                        txPacketsPerSecond: Double(delta.txPackets) / elapsed
                    )
                }
            }
        }

        sources.sort {
            ($0.counters.rxBytes + $0.counters.txBytes) > ($1.counters.rxBytes + $1.counters.txBytes)
        }

        var sourceCounters: [String: KBCounters] = [:]
        for source in sources { sourceCounters[source.id] = source.counters }
        previousSourceCounters = sourceCounters

        var interfaceCounters: [UInt32: KBCounters] = [:]
        for item in snapshot.interfaces { interfaceCounters[item.id] = item.counters }
        previousInterfaceCounters = interfaceCounters
        previousTimestamp = now

        interfaces = snapshot.interfaces
        interfaceRates = rates
        processes = snapshot.processes
        self.sources = sources
        socketInventory = snapshot.socketInventory
        hostMetrics = snapshot.hostMetrics
        cpuProcessRows = snapshot.processes.map { CPUProcessRow(process: $0) }
        resolveUserNames(for: snapshot.processes.map(\.uid))
        processInventory = ProcessInventoryBuilder.build(
            processes: snapshot.processes,
            sources: sources,
            socketInventory: snapshot.socketInventory
        )
        if !usingDaemon {
            mode = snapshot.mode
        } else if snapshot.mode == .localFullNStat {
            mode = isRoot ? .daemonFull : .daemonRestricted
        } else {
            mode = snapshot.mode
        }
        privcheck = snapshot.privcheck
        lastError = snapshot.error
        lastUpdate = snapshot.generatedAt
        recordHistory()
    }

    private func recordHistory() {
        let rates = systemRates
        rxHistory.append(rates.rxBytesPerSecond)
        txHistory.append(rates.txBytesPerSecond)

        if let host = hostMetrics {
            cpuUsageHistory.append(host.cpu.totalUsagePercent)
            loadHistory.append(host.cpu.load1)
            threadHistory.append(Double(host.cpu.threadCount))
            memoryUsageHistory.append(host.memory.usedFraction * 100)
        }

        let limit = 60
        trim(&rxHistory, limit: limit)
        trim(&txHistory, limit: limit)
        trim(&cpuUsageHistory, limit: limit)
        trim(&loadHistory, limit: limit)
        trim(&threadHistory, limit: limit)
        trim(&memoryUsageHistory, limit: limit)
    }

    private func trim(_ values: inout [Double], limit: Int) {
        if values.count > limit {
            values.removeFirst(values.count - limit)
        }
    }

    /// `getpwuid_r` can block on directory-service accounts, so resolve only
    /// unknown uids on a detached task and cache both hits and misses.
    private func resolveUserNames(for uids: [UInt32]) {
        let known = Set(userNames.keys)
        let missing = Set(uids).subtracting(known).subtracting(resolvingUIDs)
        guard !missing.isEmpty else { return }
        let targets = Array(missing)
        resolvingUIDs.formUnion(targets)

        Task { [weak self] in
            let resolved = await Task.detached(priority: .utility) {
                var names: [UInt32: String] = [:]
                for uid in targets {
                    if let name = UserCollector.name(for: uid) {
                        names[uid] = name
                    }
                }
                return names
            }.value

            guard let self else { return }
            for uid in targets {
                self.userNames[uid] = resolved[uid] ?? String(uid)
            }
            self.resolvingUIDs.subtract(targets)
        }
    }

    func userName(for uid: UInt32) -> String {
        userNames[uid] ?? String(uid)
    }

    private func subtract(_ current: KBCounters, _ previous: KBCounters) -> KBCounters {
        KBCounters(
            rxBytes: current.rxBytes >= previous.rxBytes ? current.rxBytes - previous.rxBytes : current.rxBytes,
            txBytes: current.txBytes >= previous.txBytes ? current.txBytes - previous.txBytes : current.txBytes,
            rxPackets: current.rxPackets >= previous.rxPackets ? current.rxPackets - previous.rxPackets : current.rxPackets,
            txPackets: current.txPackets >= previous.txPackets ? current.txPackets - previous.txPackets : current.txPackets
        )
    }
}
