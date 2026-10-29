import Foundation
import KancerberoCore

/// Protocol/transport badge shown in the Processes table. It extends
/// KBConnectionProtocol with RAW buckets from the socket inventory.
enum ProcessProtocolTag: String, CaseIterable, Identifiable, Hashable, Sendable {
    case tcp4
    case tcp6
    case udp4
    case udp6
    case unix
    case raw4
    case raw6
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tcp4: return "TCP4"
        case .tcp6: return "TCP6"
        case .udp4: return "UDP4"
        case .udp6: return "UDP6"
        case .unix: return "UNIX"
        case .raw4: return "RAW4"
        case .raw6: return "RAW6"
        case .other: return "OTHER"
        }
    }

    var sortRank: Int {
        switch self {
        case .tcp4: return 0
        case .tcp6: return 1
        case .udp4: return 2
        case .udp6: return 3
        case .unix: return 4
        case .raw4: return 5
        case .raw6: return 6
        case .other: return 7
        }
    }

    init?(bucket: KBConnectionProtocol) {
        switch bucket {
        case .tcp4: self = .tcp4
        case .tcp6: self = .tcp6
        case .udp4: self = .udp4
        case .udp6: self = .udp6
        case .unix: self = .unix
        case .other: self = .other
        }
    }

    static func tags(from buckets: KBSocketBucketCounts) -> Set<Self> {
        var result: Set<Self> = []
        if buckets.tcp4 > 0 { result.insert(.tcp4) }
        if buckets.tcp6 > 0 { result.insert(.tcp6) }
        if buckets.udp4 > 0 { result.insert(.udp4) }
        if buckets.udp6 > 0 { result.insert(.udp6) }
        if buckets.unix > 0 { result.insert(.unix) }
        if buckets.raw4 > 0 { result.insert(.raw4) }
        if buckets.raw6 > 0 { result.insert(.raw6) }
        if buckets.other > 0 { result.insert(.other) }
        return result
    }
}

struct ProcessInventoryRow: Identifiable, Equatable, Sendable {
    var process: KBProcessInfo
    var protocols: Set<ProcessProtocolTag>
    /// nil when there is no socket scan or it was fully restricted.
    var buckets: KBSocketBucketCounts?
    var socketTypes: KBSocketTypeCounts?
    var socketCount: Int
    var connectionCount: Int
    var listeningCount: Int
    var counters: KBCounters
    var rates: KBRates
    var restricted: Bool
    var truncated: Bool
    /// Unmasked values behind the OTHER protocol badge: socket families
    /// (AF_SYSTEM, AF_NDRV…) and NStat providers that are not TCP/UDP.
    var otherProtocolLabels: [String]
    /// Real protocols behind the RAW badges (ICMP, SCTP, GRE…). Empty when the
    /// scanner did not report them, in which case the RAW4/RAW6 badges stay.
    var rawProtocolLabels: [String]

    var id: KBProcessKey { process.id }

    var totalBytes: UInt64 { counters.rxBytes &+ counters.txBytes }

    var protocolSortRank: Int {
        protocols.map(\.sortRank).min() ?? Int.max
    }

    var hasSocketData: Bool {
        buckets != nil || socketTypes != nil
    }
}

enum ProcessInventoryBuilder {
    private struct NetworkAggregate {
        var processName = ""
        var counters = KBCounters.zero
        var rates = KBRates.zero
        var connections = 0
        var listeners = 0
        var protocols: Set<ProcessProtocolTag> = []
        var otherLabels: Set<String> = []
    }

    static func build(processes: [KBProcessInfo],
                      sources: [KBNStatSource],
                      socketInventory: KBSocketInventory?) -> [ProcessInventoryRow] {
        var network: [Int32: NetworkAggregate] = [:]
        for source in sources where source.pid > 0 {
            var aggregate = network[source.pid] ?? NetworkAggregate()
            aggregate.counters = aggregate.counters + source.counters
            aggregate.rates.rxBytesPerSecond += source.rates.rxBytesPerSecond
            aggregate.rates.txBytesPerSecond += source.rates.txBytesPerSecond
            aggregate.rates.rxPacketsPerSecond += source.rates.rxPacketsPerSecond
            aggregate.rates.txPacketsPerSecond += source.rates.txPacketsPerSecond
            aggregate.connections += 1
            if source.tcpState == "Listen" {
                aggregate.listeners += 1
            }
            if let tag = ProcessProtocolTag(bucket: source.protocolBucket) {
                aggregate.protocols.insert(tag)
            }
            if source.protocolBucket == .other {
                aggregate.otherLabels.insert(otherLabel(for: source))
            }
            if aggregate.processName.isEmpty {
                aggregate.processName = source.processName
            }
            network[source.pid] = aggregate
        }

        var socketsByPID: [Int32: KBProcessSocketSummary] = [:]
        for summary in socketInventory?.summaries ?? [] {
            if let existing = socketsByPID[summary.key.pid],
               existing.key.startTimeUS > summary.key.startTimeUS {
                continue
            }
            socketsByPID[summary.key.pid] = summary
        }

        var processesByPID: [Int32: KBProcessInfo] = [:]
        for process in processes {
            processesByPID[process.pid] = process
        }

        var pids = Set(network.keys)
        for (pid, summary) in socketsByPID where summary.uniqueSockets > 0 {
            pids.insert(pid)
        }

        var rows: [ProcessInventoryRow] = []
        rows.reserveCapacity(pids.count)

        for pid in pids {
            let networkAggregate = network[pid]
            let socketSummary = socketsByPID[pid]
            let socketCount = socketSummary?.uniqueSockets ?? 0
            guard networkAggregate != nil || socketCount > 0 else { continue }

            let name = processesByPID[pid]?.name
                ?? (networkAggregate?.processName.isEmpty == false
                    ? networkAggregate!.processName
                    : "PID \(pid)")
            let process = processesByPID[pid]
                ?? KBProcessInfo(pid: pid, name: name)

            var protocols = networkAggregate?.protocols ?? []
            let hasSocketCounts = socketSummary.map {
                !$0.restricted || $0.uniqueSockets > 0
            } ?? false
            let buckets = hasSocketCounts ? socketSummary?.buckets : nil
            let types = hasSocketCounts ? socketSummary?.types : nil
            if let buckets {
                protocols.formUnion(ProcessProtocolTag.tags(from: buckets))
            }

            var otherLabels = networkAggregate?.otherLabels ?? []
            if let families = socketSummary?.otherFamilies {
                for family in families {
                    otherLabels.insert(KBSocketFamily.name(for: family))
                }
            }
            if protocols.contains(.other) && otherLabels.isEmpty {
                otherLabels.insert("OTHER")
            }

            let rawLabels = (socketSummary?.otherProtocols ?? [])
                .map { KBIPProtocol.name(for: Int32($0)) }
                .sorted()

            rows.append(ProcessInventoryRow(
                process: process,
                protocols: protocols,
                buckets: buckets,
                socketTypes: types,
                socketCount: socketCount,
                connectionCount: networkAggregate?.connections ?? 0,
                listeningCount: networkAggregate?.listeners ?? 0,
                counters: networkAggregate?.counters ?? .zero,
                rates: networkAggregate?.rates ?? .zero,
                restricted: socketSummary?.restricted ?? false,
                truncated: socketSummary?.truncated ?? false,
                otherProtocolLabels: otherLabels.sorted(),
                rawProtocolLabels: rawLabels
            ))
        }

        rows.sort { lhs, rhs in
            if lhs.totalBytes != rhs.totalBytes {
                return lhs.totalBytes > rhs.totalBytes
            }
            if lhs.socketCount != rhs.socketCount {
                return lhs.socketCount > rhs.socketCount
            }
            let byName = lhs.process.name
                .localizedCaseInsensitiveCompare(rhs.process.name)
            if byName != .orderedSame {
                return byName == .orderedAscending
            }
            return lhs.process.pid < rhs.process.pid
        }
        return rows
    }

    /// Unmasked label for a flow that falls into the OTHER protocol bucket:
    /// the transport when the flow is TCP/UDP but its IP version is unknown,
    /// otherwise the raw NStat provider, otherwise the address family that kept
    /// it out of IPv4/IPv6.
    private static func otherLabel(for source: KBNStatSource) -> String {
        let provider = source.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        switch source.transport {
        case .tcp, .udp:
            // Sin familia 4/6 el flujo no entra en TCP4/TCP6, pero el transporte
            // sí se conoce: AF_UNSPEC no aportaría nada.
            return source.transport.title
        case .other:
            if !provider.isEmpty { return provider }
            let family = source.local.family != 0 ? source.local.family : source.remote.family
            return family == 0 ? "OTHER" : KBSocketFamily.name(for: UInt32(family))
        }
    }
}

extension KBProcessInfo {
    /// Shared by the CPU and Networking process tables.
    func matchesSearch(_ query: String, userNames: [UInt32: String]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        if String(pid).contains(needle) { return true }
        if name.lowercased().contains(needle) { return true }
        if path.lowercased().contains(needle) { return true }
        let user = userNames[uid] ?? String(uid)
        return user.lowercased().contains(needle)
    }
}
