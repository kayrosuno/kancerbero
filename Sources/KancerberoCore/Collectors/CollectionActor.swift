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

    public init(processes: [KBProcessInfo], interfaces: [KBInterfaceInfo],
                sources: [KBNStatSource], mode: KBMode, privcheck: Int32,
                isRoot: Bool, error: String?, generatedAt: Date,
                monotonicNanoseconds: UInt64) {
        self.processes = processes
        self.interfaces = interfaces
        self.sources = sources
        self.mode = mode
        self.privcheck = privcheck
        self.isRoot = isRoot
        self.error = error
        self.generatedAt = generatedAt
        self.monotonicNanoseconds = monotonicNanoseconds
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

    public init() {}

    public func refresh(timeoutMilliseconds: Int32 = 250) -> KBCollectionSnapshot {
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

        let elapsed = lastSampleNanoseconds == 0
            ? 0
            : Double(now &- lastSampleNanoseconds) / 1_000_000_000.0
        let validInterval = elapsed > 0 && elapsed < 5.0

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
            monotonicNanoseconds: now
        )
    }

    public func interfaceRates() -> [UInt32: KBRates] {
        lastInterfaceRates
    }

    public func stop() {
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
