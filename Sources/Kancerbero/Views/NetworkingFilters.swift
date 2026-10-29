import Foundation
import KancerberoCore

enum NetworkingFocus: String, CaseIterable, Identifiable, Sendable {
    case download
    case upload
    case connections
    case processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: return "Download"
        case .upload: return "Upload"
        case .connections: return "Connections"
        case .processes: return "Processes"
        }
    }
}

enum NetworkingTransport: String, CaseIterable, Identifiable, Sendable {
    case tcp
    case udp
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tcp: return "TCP"
        case .udp: return "UDP"
        case .other: return "Other"
        }
    }

    /// Returns nil for "all" or an unknown value.
    init?(cliValue: String) {
        switch cliValue.lowercased() {
        case "tcp": self = .tcp
        case "udp": self = .udp
        case "other": self = .other
        default: return nil
        }
    }
}

enum NetworkingIPVersion: String, CaseIterable, Identifiable, Sendable {
    case ipv4
    case ipv6

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ipv4: return "IPv4"
        case .ipv6: return "IPv6"
        }
    }

    /// Accepts 4/v4/ipv4 and 6/v6/ipv6; nil for "all" or an unknown value.
    init?(cliValue: String) {
        switch cliValue.lowercased() {
        case "4", "v4", "ipv4": self = .ipv4
        case "6", "v6", "ipv6": self = .ipv6
        default: return nil
        }
    }
}

enum NetworkingConnectionState: String, CaseIterable, Identifiable, Hashable, Sendable {
    case established
    case listening
    case connecting
    case closing
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .established: return "Established"
        case .listening: return "Listening"
        case .connecting: return "Connecting (SYN)"
        case .closing: return "Closing (Close/Fin/Time Wait)"
        case .other: return "Other"
        }
    }

    /// Every case pressed means "no filter"; an empty group matches nothing.
    static let all = Set(allCases)

    /// "all" and unknown values return nil (no filter), matching Transport/IP.
    init?(cliValue: String) {
        switch cliValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "established", "estab": self = .established
        case "listening", "listen": self = .listening
        case "connecting", "syn": self = .connecting
        case "closing", "close", "timewait", "time-wait", "fin": self = .closing
        case "other": self = .other
        default: return nil
        }
    }

    /// Empty states (UDP) match no category. Every non-empty unrecognized
    /// state (Closed, Unknown, …) belongs to `other`.
    static func category(for rawState: String) -> NetworkingConnectionState? {
        let value = normalized(rawState)
        guard !value.isEmpty else { return nil }
        switch value {
        case "ESTABLISHED":
            return .established
        case "LISTEN", "LISTENING":
            return .listening
        case "SYN", "SYNSENT", "SYNRECEIVED", "SYNRCVD":
            return .connecting
        case "CLOSEWAIT", "CLOSING", "FINWAIT1", "FINWAIT2", "LASTACK", "TIMEWAIT":
            return .closing
        default:
            return .other
        }
    }

    /// "TSI_SYN_SENT", "SynSent", "syn sent" → "SYNSENT".
    private static func normalized(_ rawState: String) -> String {
        var value = rawState
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        value = value.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if value.hasPrefix("TSI") { value.removeFirst(3) }
        return value
    }
}

extension NetworkingConnectionState {
    /// Checkbox tooltip; the titles alone do not explain the categories.
    var checkboxHelp: String {
        switch self {
        case .established:
            return "TCP connections that completed the handshake"
        case .listening:
            return "Sockets waiting for incoming connections"
        case .connecting:
            return "Handshake in progress (SYN sent or received)"
        case .closing:
            return "Close wait, FIN wait, closing, time wait and last ack"
        case .other:
            return "Any other TCP state not classified above"
        }
    }
}

/// Facet filter over Transport and IP. Every case pressed means "no filter";
/// an empty group matches nothing (same semantics as the Daemons chips).
struct NetworkingProtocolFilter: Equatable, Sendable {
    static let allTransports = Set(NetworkingTransport.allCases)
    static let allIPVersions = Set(NetworkingIPVersion.allCases)

    var transports: Set<NetworkingTransport> = NetworkingProtocolFilter.allTransports
    var ipVersions: Set<NetworkingIPVersion> = NetworkingProtocolFilter.allIPVersions

    static let none = NetworkingProtocolFilter()

    var isTransportFiltered: Bool { transports != Self.allTransports }
    var isIPFiltered: Bool { ipVersions != Self.allIPVersions }
    var isActive: Bool { isTransportFiltered || isIPFiltered }

    func matches(_ source: KBNStatSource) -> Bool {
        if isTransportFiltered, !transports.contains(source.transport) { return false }
        if isIPFiltered {
            guard let version = source.ipVersion,
                  ipVersions.contains(version) else { return false }
        }
        return true
    }
}

extension NetworkingUIState {
    var protocolFilter: NetworkingProtocolFilter {
        NetworkingProtocolFilter(transports: transports, ipVersions: ipVersions)
    }
}

extension NetworkingTransport {
    /// Protocol badges a process must carry to be included by this transport.
    var processTags: Set<ProcessProtocolTag> {
        switch self {
        case .tcp: return [.tcp4, .tcp6]
        case .udp: return [.udp4, .udp6]
        case .other: return [.unix, .raw4, .raw6, .other]
        }
    }
}

extension NetworkingIPVersion {
    /// Protocol badges a process must carry to be included by this family.
    var processTags: Set<ProcessProtocolTag> {
        switch self {
        case .ipv4: return [.tcp4, .udp4, .raw4]
        case .ipv6: return [.tcp6, .udp6, .raw6]
        }
    }
}

extension KBNStatSource {
    var transport: NetworkingTransport {
        let proto = provider.lowercased()
        if proto.contains("tcp") { return .tcp }
        if proto.contains("udp") { return .udp }
        return .other
    }

    /// Honest address family: neither endpoint reporting 4 or 6 is unknown,
    /// not IPv4 (unlike `connectionProtocol`, which falls back to tcp4/udp4).
    var ipVersion: NetworkingIPVersion? {
        if local.family == 6 || remote.family == 6 { return .ipv6 }
        if local.family == 4 || remote.family == 4 { return .ipv4 }
        return nil
    }

    var protocolBucket: KBConnectionProtocol {
        guard let ipVersion else { return .other }
        switch (transport, ipVersion) {
        case (.tcp, .ipv4): return .tcp4
        case (.tcp, .ipv6): return .tcp6
        case (.udp, .ipv4): return .udp4
        case (.udp, .ipv6): return .udp6
        default: return .other
        }
    }
}

@MainActor
extension AppModel {
    func filteredInterfaces(_ focus: NetworkingFocus?) -> [KBInterfaceInfo] {
        guard let focus else { return interfaces }
        let sourcedNames = Set(sources.map(\.interfaceName).filter { !$0.isEmpty })
        switch focus {
        case .download:
            return interfaces.filter {
                !$0.isLoopback && $0.kind != .tunnel
                    && (interfaceRates[$0.id]?.rxBytesPerSecond ?? 0) > 0
            }
        case .upload:
            return interfaces.filter {
                !$0.isLoopback && $0.kind != .tunnel
                    && (interfaceRates[$0.id]?.txBytesPerSecond ?? 0) > 0
            }
        case .connections, .processes:
            return interfaces.filter { sourcedNames.contains($0.name) }
        }
    }

    func filteredSources(_ focus: NetworkingFocus?,
                         matching filter: NetworkingProtocolFilter = .none,
                         states: Set<NetworkingConnectionState> = NetworkingConnectionState.all,
                         search: String = "")
        -> [KBNStatSource] {
        var base = filter.isActive ? sources.filter(filter.matches) : sources
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            base = base.filter {
                $0.processName.localizedCaseInsensitiveContains(needle)
                    || String($0.pid).contains(needle)
            }
        }
        if states != NetworkingConnectionState.all {
            base = base.filter {
                guard let category = NetworkingConnectionState.category(for: $0.tcpState)
                else { return false }
                return states.contains(category)
            }
        }
        guard let focus else { return base }
        switch focus {
        case .download:
            return base.filter { $0.rates.rxBytesPerSecond > 0 }
        case .upload:
            return base.filter { $0.rates.txBytesPerSecond > 0 }
        case .connections:
            return base.filter { ($0.counters.rxBytes &+ $0.counters.txBytes) > 0 }
        case .processes:
            return base.filter { $0.pid > 0 }
        }
    }

    func filteredProcessRows(_ focus: NetworkingFocus?,
                             matching filter: NetworkingProtocolFilter = .none,
                             search: String = "")
        -> [ProcessInventoryRow] {
        processInventory.filter { row in
            guard filter.matches(row) else { return false }
            guard row.process.matchesSearch(search, userNames: userNames) else { return false }
            switch focus {
            case .download:
                return row.rates.rxBytesPerSecond > 0
            case .upload:
                return row.rates.txBytesPerSecond > 0
            case .connections:
                return row.connectionCount > 0
            case .processes, nil:
                return true
            }
        }
    }
}

extension NetworkingProtocolFilter {
    func matches(_ row: ProcessInventoryRow) -> Bool {
        if isTransportFiltered {
            let wanted = transports.reduce(into: Set<ProcessProtocolTag>()) {
                $0.formUnion($1.processTags)
            }
            guard !row.protocols.isDisjoint(with: wanted) else { return false }
        }
        if isIPFiltered {
            let wanted = ipVersions.reduce(into: Set<ProcessProtocolTag>()) {
                $0.formUnion($1.processTags)
            }
            guard !row.protocols.isDisjoint(with: wanted) else { return false }
        }
        return true
    }
}
