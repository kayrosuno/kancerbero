import Darwin
import Foundation

public struct KBCollectionSnapshot: Codable, Sendable {
    public var processes: [KBProcessInfo]
    public var interfaces: [KBInterfaceInfo]
    public var sources: [KBNStatSource]
    public var mode: KBMode
    public var privcheck: Int32
    public var isRoot: Bool
    public var error: String?
    public var generatedAt: Date
    public var monotonicNanoseconds: UInt64
    public var socketInventory: KBSocketInventory?
    public var hostMetrics: KBHostMetrics?

    public init(processes: [KBProcessInfo], interfaces: [KBInterfaceInfo],
                sources: [KBNStatSource], mode: KBMode, privcheck: Int32,
                isRoot: Bool, error: String?, generatedAt: Date,
                monotonicNanoseconds: UInt64,
                socketInventory: KBSocketInventory? = nil,
                hostMetrics: KBHostMetrics? = nil) {
        self.processes = processes
        self.interfaces = interfaces
        self.sources = sources
        self.mode = mode
        self.privcheck = privcheck
        self.isRoot = isRoot
        self.error = error
        self.generatedAt = generatedAt
        self.monotonicNanoseconds = monotonicNanoseconds
        self.socketInventory = socketInventory
        self.hostMetrics = hostMetrics
    }
}

/// Owns the collectors off the main actor. One instance is shared by the app
/// (local mode) and, later, by the daemon.
public actor CollectionActor {
    private let nstat = NStatCollector()
    private var nstatStarted = false
    private var lastSourceCounters: [String: KBCounters] = [:]
    private var lastInterfaceCounters: [UInt32: KBCounters] = [:]
    private var lastInterfaceRates: [UInt32: KBRates] = [:]
    private var lastSampleNanoseconds: UInt64 = 0
    private var privcheck: Int32 = -1
    private var socketInventory: KBSocketInventory?
    private var socketScanTask: Task<Void, Never>?
    private var lastSocketScanNanoseconds: UInt64 = 0
    private var hostSampler = HostMetricsSampler()
    private var processCPUTracker = ProcessCPUTracker()

    public init() {}

    public func refresh(timeoutMilliseconds: Int32 = 250,
                        cadence: Double? = nil) -> KBCollectionSnapshot {
        let now = KBInterop.monotonicNanoseconds()
        var errorMessage: String?

        var statisticsPrivcheck: Int32 = -1
        if kb_sysctl_int("net.statistics_privcheck", &statisticsPrivcheck) == 0 {
            privcheck = statisticsPrivcheck
        }

        if !nstatStarted {
            do {
                try nstat.start()
                nstatStarted = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        var sources: [KBNStatSource] = []
        if nstatStarted {
            _ = nstat.poll(timeoutMilliseconds: timeoutMilliseconds)
            sources = nstat.snapshot()
        }

        var processes: [KBProcessInfo] = []
        do {
            processes = try ProcessCollector.snapshot()
        } catch {
            if errorMessage == nil { errorMessage = error.localizedDescription }
        }

        var interfaces: [KBInterfaceInfo] = []
        do {
            interfaces = try InterfaceCollector.snapshot()
        } catch {
            if errorMessage == nil { errorMessage = error.localizedDescription }
        }

        maybeStartSocketScan(processes: processes, sources: sources, now: now)

        let elapsed = lastSampleNanoseconds == 0
            ? 0
            : Double(now &- lastSampleNanoseconds) / 1_000_000_000.0
        let validInterval = RateTiming.isValidGap(elapsed, cadence: cadence)

        let host = hostSampler.sample(processes: processes)
        if let host {
            processCPUTracker.annotate(&processes,
                                       elapsed: validInterval ? elapsed : 0,
                                       totalMemoryBytes: host.memory.totalBytes,
                                       coreCount: host.cpu.coreCount,
                                       cadence: cadence)
        }
        if let sleeping = PowerAssertionsReader.current() {
            for index in processes.indices {
                guard var usage = processes[index].usage else { continue }
                let pid = processes[index].pid
                usage.preventingSleep = sleeping.contains(pid)
                processes[index].usage = usage
            }
        }

        var interfaceRates: [UInt32: KBRates] = [:]
        if validInterval {
            for index in sources.indices {
                let id = sources[index].id
                if let previous = lastSourceCounters[id] {
                    let delta = subtract(sources[index].counters, previous)
                    sources[index].rates = KBRates(
                        rxBytesPerSecond: Double(delta.rxBytes) / elapsed,
                        txBytesPerSecond: Double(delta.txBytes) / elapsed,
                        rxPacketsPerSecond: Double(delta.rxPackets) / elapsed,
                        txPacketsPerSecond: Double(delta.txPackets) / elapsed
                    )
                }
            }
            for item in interfaces {
                if let previous = lastInterfaceCounters[item.id] {
                    let delta = subtract(item.counters, previous)
                    interfaceRates[item.id] = KBRates(
                        rxBytesPerSecond: Double(delta.rxBytes) / elapsed,
                        txBytesPerSecond: Double(delta.txBytes) / elapsed,
                        rxPacketsPerSecond: Double(delta.rxPackets) / elapsed,
                        txPacketsPerSecond: Double(delta.txPackets) / elapsed
                    )
                }
            }
        }

        var sourceCounters: [String: KBCounters] = [:]
        for source in sources { sourceCounters[source.id] = source.counters }
        lastSourceCounters = sourceCounters

        var interfaceCounters: [UInt32: KBCounters] = [:]
        for item in interfaces { interfaceCounters[item.id] = item.counters }
        lastInterfaceCounters = interfaceCounters
        lastInterfaceRates = interfaceRates
        lastSampleNanoseconds = now

        let mode: KBMode
        if nstatStarted {
            mode = .localFullNStat
        } else {
            mode = .localDegraded
        }

        return KBCollectionSnapshot(
            processes: processes,
            interfaces: interfaces,
            sources: sources,
            mode: mode,
            privcheck: privcheck,
            isRoot: geteuid() == 0,
            error: errorMessage,
            generatedAt: Date(),
            monotonicNanoseconds: now,
            socketInventory: socketInventory,
            hostMetrics: host
        )
    }

    /// Socket enumeration is expensive compared to the regular tick, so it runs
    /// in the background at most every 10 seconds. Without root only processes
    /// of the current uid are readable. NStat PIDs missing from the process
    /// inventory are included as synthetic entries: libproc will report them as
    /// restricted when they belong to another uid.
    private func maybeStartSocketScan(processes: [KBProcessInfo],
                                      sources: [KBNStatSource],
                                      now: UInt64) {
        guard socketScanTask == nil else { return }
        let interval: UInt64 = 10_000_000_000
        guard lastSocketScanNanoseconds == 0
                || now &- lastSocketScanNanoseconds >= interval else { return }

        var candidates = processes
        var known = Set(processes.map(\.pid))
        for source in sources where source.pid > 0 && !known.contains(source.pid) {
            known.insert(source.pid)
            candidates.append(KBProcessInfo(pid: source.pid, name: source.processName))
        }
        guard !candidates.isEmpty else { return }

        let euid = geteuid()
        let visible = euid == 0
            ? candidates
            : candidates.filter { $0.uid == 0 || $0.uid == euid }
        guard !visible.isEmpty else { return }

        lastSocketScanNanoseconds = now
        socketScanTask = Task.detached(priority: .utility) { [weak self] in
            let inventory = SocketSummaryCollector.summaries(for: visible)
            await self?.storeSocketInventory(inventory)
        }
    }

    private func storeSocketInventory(_ inventory: KBSocketInventory) {
        socketInventory = inventory
        socketScanTask = nil
    }

    public func interfaceRates() -> [UInt32: KBRates] {
        lastInterfaceRates
    }

    public func stop() {
        socketScanTask?.cancel()
        socketScanTask = nil
        nstat.stop()
        nstatStarted = false
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
