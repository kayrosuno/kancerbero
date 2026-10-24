import Foundation
import Observation
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
    private var previousSourceCounters: [String: KBCounters] = [:]
    private var previousInterfaceCounters: [UInt32: KBCounters] = [:]
    private var previousTimestamp: UInt64 = 0
    private var daemonConnecting = false
    private var lastDaemonAttempt = Date.distantPast

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
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
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
                    try source.start(interval: requestedInterval)
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
        let limit = 60
        if rxHistory.count > limit { rxHistory.removeFirst(rxHistory.count - limit) }
        if txHistory.count > limit { txHistory.removeFirst(txHistory.count - limit) }
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
