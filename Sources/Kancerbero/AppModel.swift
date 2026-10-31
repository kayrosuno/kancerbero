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
    var interval: TimeInterval = KBPreferences.startupInterval {
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
    /// The connected daemon advertises `trashItems`. Older daemons decode the
    /// capability as nil, which reads as false here.
    var daemonSupportsTrash = false
    /// TCC Full Disk Access for this process. Independent from `hasFullDataAccess`
    /// (which describes root/daemon access) and refreshed on demand.
    private(set) var fullDiskAccess: KBFullDiskAccessStatus = .unknown
    var rxHistory: [Double] = []
    var txHistory: [Double] = []
    /// Packet-rate histories, aligned tick-by-tick with the byte histories.
    var rxPacketHistory: [Double] = []
    var txPacketHistory: [Double] = []
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
    /// Recent per-core usage, indexed by `KBCoreCPU.index`. Each row is a
    /// ring-trimmed history used by the Cores card equalizer.
    private(set) var coreUsageHistory: [[Double]] = []
    var loadHistory: [Double] = []
    var threadHistory: [Double] = []
    var memoryUsageHistory: [Double] = []
    /// Stacked composition history as percentages of physical memory. The five
    /// arrays are appended together so their indices stay aligned.
    var memoryAppHistory: [Double] = []
    var memoryWiredHistory: [Double] = []
    var memoryCompressedHistory: [Double] = []
    var memoryCachedHistory: [Double] = []
    var memoryFreeHistory: [Double] = []
    /// Activity Monitor-style memory pressure (0...100) and raw kernel level.
    var memoryPressureHistory: [Int] = []
    var memoryPressureLevelHistory: [Int] = []
    var gpuUsageHistory: [Double] = []
    var energyUsageHistory: [Double] = []
    var wakeupHistory: [Double] = []
    /// Twelve-hour battery charge graph from libsystemstats, as Activity
    /// Monitor's Energy tab shows it. Refreshed at most once a minute.
    var batteryChargeGraph: KBBatteryChargeGraph?
    var diskReadRate: Double = 0
    var diskWriteRate: Double = 0
    var diskReadOpsRate: Double = 0
    var diskWriteOpsRate: Double = 0
    var diskReadHistory: [Double] = []
    var diskWriteHistory: [Double] = []
    var diskReadOpsHistory: [Double] = []
    var diskWriteOpsHistory: [Double] = []
    var diskReadTotalBytes: UInt64 = 0
    var diskWriteTotalBytes: UInt64 = 0
    var diskReadOperationsTotal: UInt64 = 0
    var diskWriteOperationsTotal: UInt64 = 0
    /// Baselines for the disk I/O rates (host-wide, no privileges).
    private var previousDiskIO: DiskIOReading?
    /// Baselines for the per-process disk fallback used with old daemons.
    private var previousProcessIO: [KBProcessKey: (read: UInt64, written: UInt64)] = [:]
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
    private var batteryGraphFetchedAt = Date.distantPast
    private var batteryGraphFetchInFlight = false
    private static let daemonServicePlist = "uno.kayros.kancerbero.daemon.plist"

    private var daemonService: SMAppService {
        .daemon(plistName: Self.daemonServicePlist)
    }
    private var previousSourceCounters: [String: KBCounters] = [:]
    private var previousInterfaceCounters: [UInt32: KBCounters] = [:]
    private var previousTimestamp: UInt64 = 0
    private var daemonConnecting = false
    private var lastDaemonAttempt = Date.distantPast
    private var lastFullDiskAccessProbe = Date.distantPast
    private var fullDiskAccessProbeInFlight = false
    /// Set when a trash attempt was directly denied by macOS. Keeps the state
    /// at `.denied` if the heuristic probe cannot find a test path.
    private var observedFullDiskAccessDenial = false
    /// Incremented whenever the daemon connection is replaced so late callbacks
    /// from the previous connection cannot overwrite the new one.
    private var daemonGeneration = 0
    private var daemonConnectTask: Task<Void, Never>?
    private var resolvingUIDs: Set<UInt32> = []
    private var registrationCheckTask: Task<Void, Never>?
    private static let daemonFingerprintKey = "daemon.registrationFingerprint"
    /// Set when the user explicitly disables the background service, so the
    /// automatic recovery on launch does not override that decision.
    private static let autoRegisterDisabledKey = "daemon.autoRegisterDisabled"
    private let logger = Logger(subsystem: "uno.kayros.kancerbero", category: "daemon.lifecycle")
    private let permissionsLogger = Logger(subsystem: "uno.kayros.kancerbero",
                                           category: "permissions")

    var isRoot: Bool { geteuid() == 0 }

    /// Client for privileged trash requests; nil while the daemon is not in use.
    var daemonTrashClient: DaemonMetricsSource? {
        usingDaemon ? daemonSource : nil
    }

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

    /// Cumulative interface counters over the same interface set as
    /// `systemRates` (no loopback or tunnels). Use the rate deltas, never these
    /// totals, to compute speeds.
    var systemCounters: KBCounters {
        var result = KBCounters.zero
        for item in interfaces where !item.isLoopback && item.kind != .tunnel {
            result = result + item.counters
        }
        return result
    }

    func start() {
        guard task == nil else { return }
        refreshServiceStatus()
        refreshFullDiskAccess(force: true)
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
        refreshBatteryChargeGraph(force: true)
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

    /// Reads the 12-hour battery graph off the main actor. The private
    /// systemstats call is serialized in C; here we also avoid overlapping
    /// refresh tasks. A failed read keeps the last good graph.
    func refreshBatteryChargeGraph(force: Bool = false) {
        guard !batteryGraphFetchInFlight else { return }
        guard force || Date().timeIntervalSince(batteryGraphFetchedAt) > 60 else { return }
        batteryGraphFetchedAt = Date()
        batteryGraphFetchInFlight = true
        Task { [weak self] in
            let graph = await Task.detached(priority: .utility) {
                BatteryChargeGraphReader.current()
            }.value
            guard let self else { return }
            self.batteryGraphFetchInFlight = false
            if let graph {
                self.batteryChargeGraph = graph
            }
        }
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

    /// Refreshes the TCC Full Disk Access state off the main actor. The probe is
    /// heuristic (see `KBFullDiskAccessProbe`) and throttled so repeated view
    /// appearances do not cause extra TCC checks.
    func refreshFullDiskAccess(force: Bool = false) {
        guard !fullDiskAccessProbeInFlight else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastFullDiskAccessProbe) >= 1 else { return }
        lastFullDiskAccessProbe = now
        fullDiskAccessProbeInFlight = true

        Task { [weak self] in
            let status = await Task.detached(priority: .utility) {
                KBFullDiskAccessProbe.current()
            }.value
            guard let self else { return }
            self.fullDiskAccessProbeInFlight = false

            // A real trash denial is stronger evidence than an inconclusive
            // probe on a profile without Safari/Mail/Messages data.
            let resolved: KBFullDiskAccessStatus =
                status == .unknown && self.observedFullDiskAccessDenial ? .denied : status
            if resolved == .granted {
                self.observedFullDiskAccessDenial = false
            }
            if self.fullDiskAccess != resolved {
                self.fullDiskAccess = resolved
                self.permissionsLogger.notice(
                    "full disk access: \(resolved.rawValue, privacy: .public)")
            }
        }
    }

    /// Called when a trash operation is denied by macOS even through the root
    /// helper. The probe may not find a test path, but the denial is definitive.
    func noteFullDiskAccessDenied() {
        observedFullDiskAccessDenial = true
        lastFullDiskAccessProbe = .distantPast
        if fullDiskAccess != .denied {
            fullDiskAccess = .denied
            permissionsLogger.notice("full disk access: denied (observed)")
        }
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
        daemonGeneration += 1
        daemonConnectTask?.cancel()
        daemonConnectTask = nil
        daemonSource?.stop()
        daemonSource = nil
        usingDaemon = false
        daemonIsRoot = false
        daemonSupportsTrash = false
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

    func openFullDiskAccessSettings() {
        // Let the next activation refresh run immediately after Settings closes.
        lastFullDiskAccessProbe = .distantPast
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
                + "?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
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
        daemonGeneration += 1
        daemonConnectTask?.cancel()
        daemonConnectTask = nil
        daemonSource?.stop()
        daemonSource = nil
        usingDaemon = false
        daemonIsRoot = false
        daemonSupportsTrash = false
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
        daemonGeneration += 1
        let generation = daemonGeneration
        daemonConnectTask?.cancel()
        let requestedInterval = interval
        let privileged = serviceStatus == .enabled
        daemonConnectTask = Task { [weak self] in
            let source = DaemonMetricsSource()
            source.onCollection = { [weak self] snapshot in
                Task { @MainActor in
                    guard let self, self.daemonGeneration == generation,
                          !self.isPaused else { return }
                    self.usingDaemon = true
                    self.apply(snapshot)
                }
            }
            source.onInvalidate = { [weak self] in
                Task { @MainActor in
                    guard let self, self.daemonGeneration == generation else { return }
                    self.usingDaemon = false
                    self.daemonVersion = nil
                    self.daemonIsRoot = false
                    self.daemonSupportsTrash = false
                    self.daemonConnectionError = "Daemon connection closed."
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
                guard let self else {
                    source.stop()
                    return
                }
                guard self.daemonGeneration == generation else {
                    source.stop()
                    return
                }
                self.daemonSource = source
                self.daemonVersion = hello.daemonVersion
                self.daemonIsRoot = hello.capabilities.root
                self.daemonSupportsTrash = hello.capabilities.trash ?? false
                self.usingDaemon = true
                self.daemonConnecting = false
                self.daemonConnectionError = nil
                if self.interval != requestedInterval {
                    source.updateInterval(self.interval)
                }
            } catch {
                source.stop()
                let message = error.localizedDescription
                guard let self, self.daemonGeneration == generation else { return }
                self.daemonConnecting = false
                self.daemonConnectionError = message
                self.logger.error("daemon connection failed: \(message, privacy: .public)")
            }
        }
    }

    /// Restarts the installed background service without an administrator prompt
    /// and reconnects. `KeepAlive.SuccessfulExit=false` makes launchd relaunch
    /// the daemon after the self-requested SIGTERM. Used when the running daemon
    /// predates the trash API or when a stale helper must be replaced.
    func restartDaemonService() async {
        let previous = daemonSource
        resetDaemonConnection()
        if let previous {
            await Self.stopDaemon(previous)
        }

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            // The stop request can fail (for example a daemon too old to control
            // services). Retry against the daemon that just answered.
            if usingDaemon, (!daemonSupportsTrash || !daemonIsRoot),
               let stale = daemonSource {
                await Self.stopDaemon(stale)
                resetDaemonConnection()
                continue
            }
            if !usingDaemon && !daemonConnecting {
                connectDaemon()
            }
            if usingDaemon && daemonSupportsTrash && daemonIsRoot {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func resetDaemonConnection() {
        daemonGeneration += 1
        daemonConnectTask?.cancel()
        daemonConnectTask = nil
        daemonSource?.stop()
        daemonSource = nil
        usingDaemon = false
        daemonIsRoot = false
        daemonVersion = nil
        daemonSupportsTrash = false
        daemonConnectionError = nil
        daemonConnecting = false
        lastDaemonAttempt = .distantPast
    }

    /// Sends the self-stop and waits briefly so XPC delivers it before the
    /// connection is invalidated. The daemon usually dies before replying.
    private static func stopDaemon(_ source: DaemonMetricsSource) async {
        let request = KBDaemonActionRequest(label: KancerberoXPCNames.machService,
                                            domain: .system, action: .stop)
        let task = Task.detached(priority: .userInitiated) {
            _ = try? source.performDaemonAction(request)
        }
        try? await Task.sleep(for: .milliseconds(300))
        _ = await task.value
        source.stop()
    }

    private func refreshOnce() async {
        let snapshot = await collector.refresh(cadence: interval)
        apply(snapshot)
    }

    private func apply(_ snapshot: KBCollectionSnapshot) {
        let now = snapshot.monotonicNanoseconds
        let elapsed = previousTimestamp == 0
            ? 0
            : Double(now &- previousTimestamp) / 1_000_000_000.0
        let validInterval = RateTiming.isValidGap(elapsed, cadence: interval)

        if let io = DiskIOReader.current() {
            if validInterval, let previous = previousDiskIO {
                diskReadRate = io.bytesRead >= previous.bytesRead
                    ? Double(io.bytesRead - previous.bytesRead) / elapsed : 0
                diskWriteRate = io.bytesWritten >= previous.bytesWritten
                    ? Double(io.bytesWritten - previous.bytesWritten) / elapsed : 0
                diskReadOpsRate = io.readOperations >= previous.readOperations
                    ? Double(io.readOperations - previous.readOperations) / elapsed : 0
                diskWriteOpsRate = io.writeOperations >= previous.writeOperations
                    ? Double(io.writeOperations - previous.writeOperations) / elapsed : 0
            } else {
                diskReadRate = 0
                diskWriteRate = 0
                diskReadOpsRate = 0
                diskWriteOpsRate = 0
            }
            diskReadTotalBytes = io.bytesRead
            diskWriteTotalBytes = io.bytesWritten
            diskReadOperationsTotal = io.readOperations
            diskWriteOperationsTotal = io.writeOperations
            previousDiskIO = io
        }

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
        if validInterval {
            var ioBaseline: [KBProcessKey: (read: UInt64, written: UInt64)] = [:]
            for index in patchedProcesses.indices {
                guard var usage = patchedProcesses[index].usage else { continue }
                if usage.diskBytesReadPerSecond == nil,
                   (patchedProcesses[index].uid == UInt32(getuid()) || isRoot),
                   let reading = ProcessIOReader.current(pid: patchedProcesses[index].pid) {
                    let key = patchedProcesses[index].id
                    usage.diskBytesRead = reading.read
                    usage.diskBytesWritten = reading.written
                    usage.logicalWrites = reading.writes
                    if let prior = previousProcessIO[key], reading.read >= prior.read {
                        usage.diskBytesReadPerSecond =
                            Double(reading.read - prior.read) / elapsed
                        usage.diskBytesWrittenPerSecond = reading.written >= prior.written
                            ? Double(reading.written - prior.written) / elapsed : 0
                    } else {
                        usage.diskBytesReadPerSecond = 0
                        usage.diskBytesWrittenPerSecond = 0
                    }
                    ioBaseline[key] = (reading.read, reading.written)
                }
                patchedProcesses[index].usage = usage
            }
            previousProcessIO = ioBaseline
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
            // Temperature is host-wide and readable without privileges, so a
            // daemon that predates the thermal fields still gets values.
            if usingDaemon,
               measured.cpu.packageTemperatureCelsius == nil,
               measured.cpu.cores.allSatisfy({ $0.temperatureCelsius == nil }) {
                ThermalStatsReader.fillMissing(&measured.cpu)
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
        refreshBatteryChargeGraph()
    }

    private func recordHistory() {
        let rates = systemRates
        rxHistory.append(rates.rxBytesPerSecond)
        txHistory.append(rates.txBytesPerSecond)
        rxPacketHistory.append(rates.rxPacketsPerSecond)
        txPacketHistory.append(rates.txPacketsPerSecond)
        sampleDates.append(lastUpdate ?? Date())

        if let host = hostMetrics {
            cpuUsageHistory.append(host.cpu.totalUsagePercent)
            cpuUserHistory.append(host.cpu.userPercent)
            cpuSystemHistory.append(host.cpu.systemPercent)
            cpuNiceHistory.append(host.cpu.nicePercent)
            if !host.cpu.cores.isEmpty {
                let usage = host.cpu.cores.map { core -> Double in
                    let value = core.usagePercent
                    return value.isFinite ? min(max(value, 0), 100) : 0
                }
                var next = coreUsageHistory
                if next.count > usage.count {
                    next.removeLast(next.count - usage.count)
                }
                while next.count < usage.count {
                    next.append([])
                }
                for index in usage.indices {
                    next[index].append(usage[index])
                    trim(&next[index], limit: 30)
                }
                coreUsageHistory = next
            }
            loadHistory.append(host.cpu.load1)
            threadHistory.append(Double(host.cpu.threadCount))
            let memory = host.memory
            memoryUsageHistory.append(memory.activityMonitorUsedFraction * 100)
            let total = max(Double(memory.totalBytes), 1)
            memoryAppHistory.append(Double(memory.appMemoryBytes) / total * 100)
            memoryWiredHistory.append(Double(memory.wiredBytes) / total * 100)
            memoryCompressedHistory.append(Double(memory.compressedBytes) / total * 100)
            memoryCachedHistory.append(Double(memory.cachedFileBytes) / total * 100)
            memoryFreeHistory.append(Double(memory.activityMonitorFreeBytes) / total * 100)
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
        diskReadHistory.append(diskReadRate)
        diskWriteHistory.append(diskWriteRate)
        diskReadOpsHistory.append(diskReadOpsRate)
        diskWriteOpsHistory.append(diskWriteOpsRate)

        let limit = 60
        trim(&rxHistory, limit: limit)
        trim(&txHistory, limit: limit)
        trim(&rxPacketHistory, limit: limit)
        trim(&txPacketHistory, limit: limit)
        trim(&sampleDates, limit: limit)
        trim(&cpuUsageHistory, limit: limit)
        trim(&cpuUserHistory, limit: limit)
        trim(&cpuSystemHistory, limit: limit)
        trim(&cpuNiceHistory, limit: limit)
        trim(&loadHistory, limit: limit)
        trim(&threadHistory, limit: limit)
        trim(&memoryUsageHistory, limit: limit)
        trim(&memoryAppHistory, limit: limit)
        trim(&memoryWiredHistory, limit: limit)
        trim(&memoryCompressedHistory, limit: limit)
        trim(&memoryCachedHistory, limit: limit)
        trim(&memoryFreeHistory, limit: limit)
        trim(&memoryPressureHistory, limit: limit)
        trim(&memoryPressureLevelHistory, limit: limit)
        trim(&gpuUsageHistory, limit: limit)
        trim(&energyUsageHistory, limit: limit)
        trim(&wakeupHistory, limit: limit)
        trim(&diskReadHistory, limit: limit)
        trim(&diskWriteHistory, limit: limit)
        trim(&diskReadOpsHistory, limit: limit)
        trim(&diskWriteOpsHistory, limit: limit)
    }

    /// Clears every graph history (Dock icon "Clear History").
    func clearHistories() {
        rxHistory.removeAll()
        txHistory.removeAll()
        rxPacketHistory.removeAll()
        txPacketHistory.removeAll()
        sampleDates.removeAll()
        cpuUsageHistory.removeAll()
        cpuUserHistory.removeAll()
        cpuSystemHistory.removeAll()
        cpuNiceHistory.removeAll()
        coreUsageHistory.removeAll()
        loadHistory.removeAll()
        threadHistory.removeAll()
        memoryUsageHistory.removeAll()
        memoryAppHistory.removeAll()
        memoryWiredHistory.removeAll()
        memoryCompressedHistory.removeAll()
        memoryCachedHistory.removeAll()
        memoryFreeHistory.removeAll()
        memoryPressureHistory.removeAll()
        memoryPressureLevelHistory.removeAll()
        gpuUsageHistory.removeAll()
        energyUsageHistory.removeAll()
        wakeupHistory.removeAll()
        diskReadHistory.removeAll()
        diskWriteHistory.removeAll()
        diskReadOpsHistory.removeAll()
        diskWriteOpsHistory.removeAll()
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
