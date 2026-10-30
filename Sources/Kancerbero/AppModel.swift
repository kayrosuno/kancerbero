import AppKit
import Foundation
import Observation
import os
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
    var isPaused = false {
        didSet {
            guard oldValue != isPaused else { return }
            if !isPaused && !usingDaemon {
                wakeRefreshLoop()
            }
        }
    }
    var interval: TimeInterval = 1.0 {
        didSet {
            guard oldValue != interval else { return }
            // Keep the collected history: samples carry their own timestamps,
            // so the chart's time axis stays correct across cadence changes.
            daemonSource?.updateInterval(interval)
            if !usingDaemon {
                wakeRefreshLoop()
            }
        }
    }
    var usingDaemon = false
    var daemonVersion: String?
    var rxHistory: [Double] = []
    var txHistory: [Double] = []
    /// Timestamps of the traffic samples, parallel to `rxHistory`/`txHistory`.
    var sampleDates: [Date] = []
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
    var cpuUserHistory: [Double] = []
    var cpuSystemHistory: [Double] = []
    var cpuNiceHistory: [Double] = []
    var loadHistory: [Double] = []
    var threadHistory: [Double] = []
    var memoryUsageHistory: [Double] = []
    /// Activity Monitor-style memory pressure (0...100) and raw kernel level.
    var memoryPressureHistory: [Int] = []
    var memoryPressureLevelHistory: [Int] = []
    var gpuUsageHistory: [Double] = []
    var energyUsageHistory: [Double] = []
    var wakeupHistory: [Double] = []
    /// Baselines for the local energy fallback used with old daemons.
    private var previousProcessEnergy: [KBProcessKey: (energy: UInt64, wakeups: UInt64)] = [:]
    var serviceStatus: SMAppService.Status = .notRegistered
    var serviceError: String?
    var serviceActionInFlight = false
    var legacyAgentDetected = false
    var legacyDaemonDetected = false
    /// Whether a `KancerberoDaemon` process is visible in the process table.
    /// `SMAppService.Status.enabled` only means "registered and eligible to
    /// run"; a job whose signature is rejected never becomes a process.
    var daemonProcessRunning = false
    var daemonProcessPID: Int32?
    /// Last XPC connection failure, surfaced in System status instead of being
    /// silently swallowed by the retry loop.
    var daemonConnectionError: String?
    /// True when the daemon snapshot is missing processes that macOS sees
    /// (typically because an older daemon truncated the list).
    var daemonProcessesIncomplete = false
    var daemonReportedProcessCount = 0
    var daemonLocalProcessCount = 0

    var legacyServiceDetected: Bool {
        legacyAgentDetected || legacyDaemonDetected
    }

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
    private var sleepTask: Task<Void, Never>?
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
    private var registrationCheckTask: Task<Void, Never>?
    private static let daemonFingerprintKey = "daemon.registrationFingerprint"
    /// Set when the user explicitly disables the background service, so the
    /// automatic recovery on launch does not override that decision.
    private static let autoRegisterDisabledKey = "daemon.autoRegisterDisabled"
    private let logger = Logger(subsystem: "uno.kayros.kancerbero", category: "daemon.lifecycle")

    var isRoot: Bool { geteuid() == 0 }

    var isConnectingToDaemon: Bool { daemonConnecting }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? KBVersion.current
    }

    var appBundlePath: String {
        Bundle.main.bundleURL.path
    }

    var appIsInApplications: Bool {
        appBundlePath.hasPrefix("/Applications/")
    }

    private var daemonBundleDirectory: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
    }

    private var daemonExecutableURL: URL {
        daemonBundleDirectory.appendingPathComponent("KancerberoDaemon")
    }

    /// Identity of the registration inputs: the daemon executable and its
    /// launchd plist. SMAppService must be re-registered when either changes,
    /// so the app stores this value after registering and compares it later.
    private var daemonFingerprint: String {
        func stamp(_ url: URL) -> String {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            else { return "0:0:0" }
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.int64Value ?? 0
            let mtime = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
            return "\(size):\(inode):\(mtime)"
        }
        let plist = daemonBundleDirectory.appendingPathComponent(Self.daemonServicePlist)
        return "\(stamp(daemonExecutableURL))|\(stamp(plist))"
    }

    var daemonHelperPresent: Bool {
        FileManager.default.isExecutableFile(
            atPath: daemonBundleDirectory.appendingPathComponent("KancerberoDaemon").path)
    }

    var daemonPlistPresent: Bool {
        FileManager.default.fileExists(
            atPath: daemonBundleDirectory.appendingPathComponent(Self.daemonServicePlist).path)
    }

    var hasFullDataAccess: Bool {
        (usingDaemon && daemonIsRoot) || isRoot
    }

    var legacyRemovalCommands: String {
        var commands: [String] = []
        if legacyAgentDetected { commands.append("./scripts/uninstall-agent.sh") }
        if legacyDaemonDetected { commands.append("sudo ./scripts/uninstall-daemon.sh") }
        return commands.joined(separator: "\n")
    }

    private var legacyServiceMessage: String {
        let commands = legacyRemovalCommands
        guard !commands.isEmpty else { return "" }
        return "A legacy background service is installed. Remove it first:\n\(commands)"
    }

    private var helperMissingMessage: String {
        "The background helper is missing from this app bundle. Reinstall a complete signed build in /Applications."
    }

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
                if Task.isCancelled { return }
                let interval = self.isPaused ? 0.5 : self.interval
                await self.sleepForRefreshInterval(interval)
            }
        }
        connectDaemon()
        scheduleRegistrationHealthCheck()
    }

    /// Sleeps in an unstructured task so an interval or pause change can cancel
    /// just the sleep without cancelling the polling loop.
    private func sleepForRefreshInterval(_ seconds: TimeInterval) async {
        let sleeper = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                // Cancelled by wakeRefreshLoop or stop().
            }
        }
        sleepTask = sleeper
        await sleeper.value
        sleepTask = nil
    }

    private func wakeRefreshLoop() {
        sleepTask?.cancel()
    }

    func refreshServiceStatus() {
        serviceStatus = daemonService.status
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        legacyAgentDetected = FileManager.default.fileExists(
            atPath: "\(home)/Library/LaunchAgents/uno.kayros.kancerbero.agent.plist")
        legacyDaemonDetected = FileManager.default.fileExists(
            atPath: "/Library/LaunchDaemons/uno.kayros.kancerbero.daemon.plist")
        updateDaemonProcessState()
    }

    /// The daemon runs as root, so `launchctl print system/<label>` is not
    /// available to an unprivileged app. The process table is: libproc exposes
    /// the name of every process without privileges.
    private func updateDaemonProcessState() {
        let executablePath = daemonExecutableURL.path
        let match = processes.first {
            $0.name == "KancerberoDaemon" || (!executablePath.isEmpty && $0.path == executablePath)
        }
        daemonProcessPID = match?.pid
        daemonProcessRunning = match != nil
    }

    func registerDaemonService() async {
        guard !serviceActionInFlight else { return }
        serviceActionInFlight = true
        defer { serviceActionInFlight = false }
        UserDefaults.standard.set(false, forKey: Self.autoRegisterDisabledKey)
        await registerDaemonServiceInternal()
    }

    private func registerDaemonServiceInternal() async {
        serviceError = nil
        if legacyServiceDetected {
            serviceError = legacyServiceMessage
            return
        }
        guard daemonHelperPresent && daemonPlistPresent else {
            serviceError = helperMissingMessage
            return
        }
        let plistName = Self.daemonServicePlist
        var alreadyRegistered = false
        do {
            try await Task.detached(priority: .userInitiated) {
                try SMAppService.daemon(plistName: plistName).register()
            }.value
        } catch {
            let nsError = error as NSError
            // kSMErrorAlreadyRegistered = 12: the existing registration may be
            // stale, so don't record this bundle as registered; the health
            // check will re-register if the daemon is not running.
            if nsError.code == 12 {
                alreadyRegistered = true
            } else {
                serviceError = nsError.localizedDescription
                logger.error("register failed: \(nsError.localizedDescription, privacy: .public)")
            }
        }
        if !alreadyRegistered && serviceError == nil {
            UserDefaults.standard.set(daemonFingerprint, forKey: Self.daemonFingerprintKey)
            UserDefaults.standard.set(false, forKey: Self.autoRegisterDisabledKey)
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
        guard !serviceActionInFlight else { return }
        serviceActionInFlight = true
        defer { serviceActionInFlight = false }
        // Explicit user action: don't let the launch-time recovery re-enable it.
        UserDefaults.standard.set(true, forKey: Self.autoRegisterDisabledKey)
        await unregisterDaemonServiceInternal()
    }

    private func unregisterDaemonServiceInternal() async {
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
                logger.error("unregister failed: \(nsError.localizedDescription, privacy: .public)")
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.daemonFingerprintKey)
        refreshServiceStatus()
    }

    /// Removes and re-adds the service registration so macOS can ask for
    /// approval again. Privileged collection pauses until it is approved.
    func repairDaemonService() async {
        guard !serviceActionInFlight else { return }
        serviceActionInFlight = true
        defer { serviceActionInFlight = false }
        if legacyServiceDetected {
            serviceError = legacyServiceMessage
            return
        }
        guard daemonHelperPresent && daemonPlistPresent else {
            serviceError = helperMissingMessage
            return
        }
        await unregisterDaemonServiceInternal()
        await registerDaemonServiceInternal()
    }

    /// SMAppService requires the registration to be refreshed when the daemon
    /// executable or its plist changes. After an in-place app update the old
    /// registration can stay "enabled" in Login Items while launchd refuses to
    /// spawn the new binary. Check once per launch, after the first connection
    /// attempt, and repair without user action when the daemon is not running.
    private func scheduleRegistrationHealthCheck() {
        registrationCheckTask?.cancel()
        registrationCheckTask = Task { [weak self] in
            // Wait for the first connection attempt to settle: when the
            // registered daemon is missing or was rejected, the XPC handshake
            // can block for ~20 s.
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if !self.daemonConnecting { break }
            }
            guard let self, !Task.isCancelled else { return }
            await self.evaluateDaemonRegistration()
        }
    }

    private func evaluateDaemonRegistration() async {
        #if !DEBUG
        guard appIsInApplications,
              !serviceActionInFlight,
              !legacyServiceDetected,
              daemonHelperPresent,
              daemonPlistPresent,
              !daemonConnecting,
              !usingDaemon else { return }
        refreshServiceStatus()

        // The service identity changed in this version (and a user may install
        // over an older registration), so register it once on launch unless the
        // user explicitly disabled it.
        if serviceStatus == .notRegistered,
           !UserDefaults.standard.bool(forKey: Self.autoRegisterDisabledKey) {
            logger.notice("background service not registered; registering")
            await registerDaemonService()
            return
        }

        guard serviceStatus == .enabled, !usingDaemon else { return }
        let stored = UserDefaults.standard.string(forKey: Self.daemonFingerprintKey)
        let current = daemonFingerprint
        guard stored != current else { return }
        // If the daemon is already running and answering, keep the existing
        // registration and only record the new fingerprint.
        guard !daemonProcessRunning || daemonConnectionError != nil else {
            UserDefaults.standard.set(current, forKey: Self.daemonFingerprintKey)
            return
        }
        // Record first: a failed repair must not loop on every launch.
        UserDefaults.standard.set(current, forKey: Self.daemonFingerprintKey)
        logger.notice("daemon registration is stale; re-registering")
        await repairDaemonService()
        #endif
    }

    func retryDaemonConnection() {
        serviceError = nil
        refreshServiceStatus()
        guard !daemonConnecting, !usingDaemon else { return }
        if serviceStatus != .enabled && !legacyServiceDetected {
            serviceError = "Enable and approve the background service first."
            return
        }
        lastDaemonAttempt = .distantPast
        connectDaemon()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
    }

    func copyLegacyRemovalCommands() {
        let commands = legacyRemovalCommands
        guard !commands.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands, forType: .string)
    }

    func stop() {
        sleepTask?.cancel()
        sleepTask = nil
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
                    self?.daemonConnectionError = "Daemon connection closed."
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
                self.daemonConnectionError = nil
                if self.interval != requestedInterval {
                    source.updateInterval(self.interval)
                }
            } catch {
                source.stop()
                let message = error.localizedDescription
                self?.daemonConnecting = false
                self?.daemonConnectionError = message
                self?.logger.error("daemon connection failed: \(message, privacy: .public)")
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
        var patchedProcesses = snapshot.processes
        if validInterval {
            var baseline: [KBProcessKey: (energy: UInt64, wakeups: UInt64)] = [:]
            for index in patchedProcesses.indices {
                guard var usage = patchedProcesses[index].usage else { continue }
                if usage.energyWatts == nil,
                   (patchedProcesses[index].uid == UInt32(getuid()) || isRoot),
                   let reading = ProcessEnergyReader.current(pid: patchedProcesses[index].pid) {
                    let key = patchedProcesses[index].id
                    usage.energyNanojoules = reading.energy
                    usage.interruptWakeups = reading.wakeups
                    usage.packageIdleWakeups = 0
                    if let prior = previousProcessEnergy[key],
                       reading.energy >= prior.energy {
                        usage.energyWatts = Double(reading.energy - prior.energy)
                            / 1_000_000_000 / elapsed
                        usage.wakeupsPerSecond = reading.wakeups >= prior.wakeups
                            ? Double(reading.wakeups - prior.wakeups) / elapsed
                            : 0
                    } else {
                        usage.energyWatts = 0
                        usage.wakeupsPerSecond = 0
                    }
                    baseline[key] = (reading.energy, reading.wakeups)
                }
                patchedProcesses[index].usage = usage
            }
            previousProcessEnergy = baseline
        }
        if patchedProcesses.contains(where: {
            $0.usage != nil && $0.usage?.preventingSleep == nil
        }), let sleeping = PowerAssertionsReader.current() {
            for index in patchedProcesses.indices {
                guard var usage = patchedProcesses[index].usage else { continue }
                let pid = patchedProcesses[index].pid
                usage.preventingSleep = sleeping.contains(pid)
                patchedProcesses[index].usage = usage
            }
        }

        // A daemon built before the full KERN_PROC_ALL enumeration can report
        // far fewer processes. Merge the identities macOS sees so every table
        // matches Activity Monitor/btop; missing counters stay restricted.
        if usingDaemon {
            let reported = patchedProcesses.count
            let metadata = ProcessCollector.metadataSnapshot()
            let existing = Set(patchedProcesses.map(\.pid))
            let missing = metadata.filter { !existing.contains($0.pid) }
            daemonReportedProcessCount = reported
            daemonLocalProcessCount = metadata.count
            daemonProcessesIncomplete = !missing.isEmpty && !metadata.isEmpty
            if !missing.isEmpty {
                patchedProcesses.append(contentsOf: missing)
                patchedProcesses.sort { $0.pid < $1.pid }
            }
        } else {
            daemonProcessesIncomplete = false
            daemonReportedProcessCount = patchedProcesses.count
            daemonLocalProcessCount = patchedProcesses.count
        }
        processes = patchedProcesses
        updateDaemonProcessState()
        self.sources = sources
        socketInventory = snapshot.socketInventory
        // Pressure, GPU and battery are host-wide and readable without
        // privileges: fill them in when the daemon predates these fields.
        var host = snapshot.hostMetrics
        if var measured = host,
           measured.memory.pressurePercent == nil
            || measured.memory.pressureLevel == nil
            || measured.gpu == nil
            || measured.power == nil {
            let local = MemoryPressureReader.current()
            if measured.memory.pressurePercent == nil {
                measured.memory.pressurePercent = local.percent
            }
            if measured.memory.pressureLevel == nil {
                measured.memory.pressureLevel = local.level
            }
            if measured.gpu == nil {
                measured.gpu = GPUStatsReader.current()
            }
            if measured.power == nil {
                measured.power = PowerStatsReader.current()
            }
            host = measured
        }
        if var measured = host {
            measured.cpu.taskCount = patchedProcesses.count
            measured.cpu.threadCount = patchedProcesses.reduce(0) {
                $0 + ($1.usage?.threads ?? 0)
            }
            measured.cpu.threadsRestricted = patchedProcesses.reduce(0) {
                $0 + ($1.usage == nil ? 1 : 0)
            }
            host = measured
        }
        hostMetrics = host
        cpuProcessRows = patchedProcesses.map { CPUProcessRow(process: $0) }
        resolveUserNames(for: patchedProcesses.map(\.uid))
        processInventory = ProcessInventoryBuilder.build(
            processes: patchedProcesses,
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
        sampleDates.append(lastUpdate ?? Date())

        if let host = hostMetrics {
            cpuUsageHistory.append(host.cpu.totalUsagePercent)
            cpuUserHistory.append(host.cpu.userPercent)
            cpuSystemHistory.append(host.cpu.systemPercent)
            cpuNiceHistory.append(host.cpu.nicePercent)
            loadHistory.append(host.cpu.load1)
            threadHistory.append(Double(host.cpu.threadCount))
            memoryUsageHistory.append(host.memory.usedFraction * 100)
            if let pressure = host.memory.pressurePercent {
                memoryPressureHistory.append(pressure)
                memoryPressureLevelHistory.append(host.memory.pressureLevel ?? 0)
            }
            if let utilization = host.gpu?.utilizationPercent {
                gpuUsageHistory.append(utilization)
            }
        }

        energyUsageHistory.append(processes.reduce(0.0) {
            $0 + ($1.usage?.energyWatts ?? 0)
        })
        wakeupHistory.append(processes.reduce(0.0) {
            $0 + ($1.usage?.wakeupsPerSecond ?? 0)
        })

        let limit = 60
        trim(&rxHistory, limit: limit)
        trim(&txHistory, limit: limit)
        trim(&sampleDates, limit: limit)
        trim(&cpuUsageHistory, limit: limit)
        trim(&cpuUserHistory, limit: limit)
        trim(&cpuSystemHistory, limit: limit)
        trim(&cpuNiceHistory, limit: limit)
        trim(&loadHistory, limit: limit)
        trim(&threadHistory, limit: limit)
        trim(&memoryUsageHistory, limit: limit)
        trim(&memoryPressureHistory, limit: limit)
        trim(&memoryPressureLevelHistory, limit: limit)
        trim(&gpuUsageHistory, limit: limit)
        trim(&energyUsageHistory, limit: limit)
        trim(&wakeupHistory, limit: limit)
    }

    private func trim<Element>(_ values: inout [Element], limit: Int) {
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
