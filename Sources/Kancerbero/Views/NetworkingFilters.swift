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

    func matches(_ rawState: String) -> Bool {
        Self.category(for: rawState) == self
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

struct NetworkingProtocolFilter: Equatable, Sendable {
    var transport: NetworkingTransport?
    var ipVersion: NetworkingIPVersion?

    static let none = NetworkingProtocolFilter()

    var isActive: Bool { transport != nil || ipVersion != nil }

    func matches(_ source: KBNStatSource) -> Bool {
        if let transport, source.transport != transport { return false }
        if let ipVersion, source.ipVersion != ipVersion { return false }
        return true
    }
}

extension NetworkingUIState {
    var protocolFilter: NetworkingProtocolFilter {
        NetworkingProtocolFilter(transport: transport, ipVersion: ipVersion)
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
                         state: NetworkingConnectionState? = nil)
        -> [KBNStatSource] {
        var base = filter.isActive ? sources.filter(filter.matches) : sources
        if let state {
            base = base.filter { state.matches($0.tcpState) }
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
        if let transport {
            switch transport {
            case .tcp:
                guard row.protocols.contains(.tcp4) || row.protocols.contains(.tcp6) else {
                    return false
                }
            case .udp:
                guard row.protocols.contains(.udp4) || row.protocols.contains(.udp6) else {
                    return false
                }
            case .other:
                guard row.protocols.contains(.unix)
                        || row.protocols.contains(.raw4)
                        || row.protocols.contains(.raw6)
                        || row.protocols.contains(.other) else {
                    return false
                }
            }
        }
        if let ipVersion {
            switch ipVersion {
            case .ipv4:
                guard row.protocols.contains(.tcp4)
                        || row.protocols.contains(.udp4)
                        || row.protocols.contains(.raw4) else {
                    return false
                }
            case .ipv6:
                guard row.protocols.contains(.tcp6)
                        || row.protocols.contains(.udp6)
                        || row.protocols.contains(.raw6) else {
                    return false
                }
            }
        }
        return true
    }
}
