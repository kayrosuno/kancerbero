import Darwin
import Foundation
import KancerberoCore

enum NetworkingFocus: String, CaseIterable, Identifiable, Sendable {
    case download
    case upload
    /// Every connection that survives the other filters.
    case connections
    /// Only connections that moved bytes in the last 10 seconds.
    case active
    case processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: return "Download"
        case .upload: return "Upload"
        case .connections: return "Connections"
        case .active: return "Active"
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

    static let all = Set(allCases)

    /// Accepts 4/v4/ipv4 and 6/v6/ipv6; nil for "all" or an unknown value.
    init?(cliValue: String) {
        switch cliValue.lowercased() {
        case "4", "v4", "ipv4": self = .ipv4
        case "6", "v6", "ipv6": self = .ipv6
        default: return nil
        }
    }
}

/// Processes facet: protocol family/kind. TCP/UDP/RAW group their v4 and v6
/// badges; UNIX and OTHER are single buckets.
/// socket(domain): the address family, independent from the socket type and
/// the protocol. Unknown AF values fall into `.other` (never dropped).
enum ProcessDomain: String, CaseIterable, Identifiable, Hashable, Sendable {
    case inet
    case inet6
    case unix
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inet: return "AF_INET"
        case .inet6: return "AF_INET6"
        case .unix: return "AF_UNIX"
        case .other: return "Other"
        }
    }

    static let all = Set(allCases)

    var isInternet: Bool { self == .inet || self == .inet6 }

    static func category(forFamily family: Int32) -> ProcessDomain {
        switch family {
        case AF_INET: return .inet
        case AF_INET6: return .inet6
        case AF_UNIX: return .unix
        default: return .other
        }
    }

    init?(cliValue: String) {
        switch cliValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "inet", "af_inet", "4", "v4", "ipv4": self = .inet
        case "inet6", "af_inet6", "6", "v6", "ipv6": self = .inet6
        case "unix", "af_unix": self = .unix
        case "other": self = .other
        default: return nil
        }
    }

    /// Tags used by the aggregate fallback (old daemons / restricted scans).
    var legacyTags: Set<ProcessProtocolTag> {
        switch self {
        case .inet: return [.tcp4, .udp4, .raw4]
        case .inet6: return [.tcp6, .udp6, .raw6]
        case .unix: return [.unix]
        case .other: return [.other]
        }
    }

    var checkboxHelp: String {
        switch self {
        case .inet: return "AF_INET (IPv4) sockets"
        case .inet6: return "AF_INET6 (IPv6) sockets"
        case .unix: return "AF_UNIX local sockets"
        case .other: return "Other address families (AF_SYSTEM, AF_NDRV…)"
        }
    }
}

/// socket(protocol): the resolved IPPROTO. IPPROTO_IP/RAW map to RAW; anything
/// else falls into `.other`.
enum ProcessProtocolCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case tcp
    case udp
    case icmp
    case icmpv6
    case sctp
    case gre
    case esp
    case raw
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tcp: return "TCP"
        case .udp: return "UDP"
        case .icmp: return "ICMP"
        case .icmpv6: return "ICMPv6"
        case .sctp: return "SCTP"
        case .gre: return "GRE"
        case .esp: return "ESP"
        case .raw: return "RAW"
        case .other: return "Other"
        }
    }

    static let all = Set(allCases)

    static func category(forNumber number: Int32) -> ProcessProtocolCategory {
        switch number {
        case 6: return .tcp          // IPPROTO_TCP
        case 17: return .udp         // IPPROTO_UDP
        case 1: return .icmp         // IPPROTO_ICMP
        case 58: return .icmpv6      // IPPROTO_ICMPV6
        case 132: return .sctp       // IPPROTO_SCTP
        case 47: return .gre         // IPPROTO_GRE
        case 50: return .esp         // IPPROTO_ESP
        case 0, 255: return .raw     // IPPROTO_IP / IPPROTO_RAW
        default: return .other
        }
    }

    init?(cliValue: String) {
        switch cliValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "tcp", "tcp4", "tcp6": self = .tcp
        case "udp", "udp4", "udp6": self = .udp
        case "icmp", "icmp4": self = .icmp
        case "icmpv6", "icmp6": self = .icmpv6
        case "sctp": self = .sctp
        case "gre": self = .gre
        case "esp": self = .esp
        case "raw", "raw4", "raw6": self = .raw
        case "other": self = .other
        default: return nil
        }
    }

    /// Aggregate tags used by the legacy fallback.
    var legacyTags: Set<ProcessProtocolTag> {
        switch self {
        case .tcp: return [.tcp4, .tcp6]
        case .udp: return [.udp4, .udp6]
        case .raw: return [.raw4, .raw6]
        case .icmp, .icmpv6, .sctp, .gre, .esp: return [.raw4, .raw6]
        case .other: return [.other]
        }
    }
}

/// Processes facet: socket type from the libproc inventory.
enum ProcessSocketType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case stream
    case dgram
    case raw
    case seqpacket
    case other

    var id: String { rawValue }

    /// Lowercase, matching the Sockets column text.
    var title: String { rawValue }

    static let all = Set(allCases)

    init?(cliValue: String) {
        self.init(rawValue: cliValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased())
    }

    func count(in types: KBSocketTypeCounts) -> Int {
        switch self {
        case .stream: return types.stream
        case .dgram: return types.dgram
        case .raw: return types.raw
        case .seqpacket: return types.seqpacket
        case .other: return types.otherType
        }
    }

    static func category(forTypeNumber type: Int32) -> ProcessSocketType {
        switch type {
        case SOCK_STREAM: return .stream
        case SOCK_DGRAM: return .dgram
        case SOCK_RAW: return .raw
        case SOCK_SEQPACKET: return .seqpacket
        default: return .other
        }
    }

    var checkboxHelp: String {
        switch self {
        case .stream: return "SOCK_STREAM sockets (TCP, UNIX stream)"
        case .dgram: return "SOCK_DGRAM sockets (UDP, UNIX datagram)"
        case .raw: return "SOCK_RAW sockets"
        case .seqpacket: return "SOCK_SEQPACKET sockets"
        case .other:
            return "Sockets whose type is not stream, dgram, raw or seqpacket"
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

    /// Empty states (UDP) match no category; the Connections matcher leaves
    /// them to the Transport filter. Every non-empty unrecognized state
    /// (Closed, Unknown, …) belongs to `other`.
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
            return "TCP states not classified above"
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
extension KBInterfaceInfo {
    /// Up / Dormant / Down, shared by the Interfaces table and its search.
    nonisolated var stateDescription: String {
        if !isUp { return "Down" }
        return isRunning ? "Up" : "Dormant"
    }
}

extension ProcessInventoryRow {
    /// Address families behind the process's sockets, sorted AF_INET,
    /// AF_INET6, AF_UNIX and then the rest.
    var domainLabels: [String] {
        if let signatures = socketSignatures, !signatures.isEmpty {
            let families = signatures.map {
                KBSocketFamily.name(for: UInt32(max($0.family, 0)))
            }
            return sortedLabels(Set(families), rank: Self.domainRank)
        }
        var labels: Set<String> = []
        if protocols.contains(.tcp4) || protocols.contains(.udp4) || protocols.contains(.raw4) {
            labels.insert("AF_INET")
        }
        if protocols.contains(.tcp6) || protocols.contains(.udp6) || protocols.contains(.raw6) {
            labels.insert("AF_INET6")
        }
        if protocols.contains(.unix) {
            labels.insert("AF_UNIX")
        }
        if protocols.contains(.other) {
            let families = otherProtocolLabels.filter { $0.hasPrefix("AF_") }
            labels.formUnion(families.isEmpty ? ["Other"] : families)
        }
        return sortedLabels(labels, rank: Self.domainRank)
    }

    /// IP protocols only; AF_UNIX/other domains have no IPPROTO and are shown
    /// in the Domain column instead.
    var protocolLabels: [String] {
        if let signatures = socketSignatures, !signatures.isEmpty {
            let labels = signatures.compactMap { signature -> String? in
                guard ProcessDomain.category(forFamily: signature.family).isInternet else {
                    return nil
                }
                return KBIPProtocol.name(for: signature.protocolNumber)
            }
            return sortedLabels(Set(labels), rank: Self.protocolRank)
        }
        var labels: Set<String> = []
        if protocols.contains(.tcp4) || protocols.contains(.tcp6) {
            labels.insert("TCP")
        }
        if protocols.contains(.udp4) || protocols.contains(.udp6) {
            labels.insert("UDP")
        }
        if protocols.contains(.raw4) || protocols.contains(.raw6) {
            if rawProtocolLabels.isEmpty {
                labels.insert("RAW")
            } else {
                labels.formUnion(rawProtocolLabels)
            }
        }
        return sortedLabels(labels, rank: Self.protocolRank)
    }

    /// Compact labels for the table column (INET, INET6, UNIX, SYSTEM…); the
    /// tooltip keeps the full AF_* names.
    var domainBadgeLabels: [String] {
        domainLabels.map { label in
            label.hasPrefix("AF_") ? String(label.dropFirst(3)) : label
        }
    }

    var domainSortRank: Int {
        domainLabels.first.map(Self.domainRank) ?? Int.max
    }

    var protocolSortRank: Int {
        protocolLabels.first.map(Self.protocolRank) ?? Int.max
    }

    static func domainRank(_ label: String) -> Int {
        switch label {
        case "AF_INET": return 0
        case "AF_INET6": return 1
        case "AF_UNIX": return 2
        default: return 3
        }
    }

    static func protocolRank(_ label: String) -> Int {
        switch label {
        case "TCP": return 0
        case "UDP": return 1
        case "ICMP": return 2
        case "ICMPv6": return 3
        case "SCTP": return 4
        case "GRE": return 5
        case "ESP": return 6
        case "RAW": return 7
        default: return 8
        }
    }

    private func sortedLabels(_ labels: Set<String>,
                              rank: (String) -> Int) -> [String] {
        labels.sorted { lhs, rhs in
            let lhsRank = rank(lhs)
            let rhsRank = rank(rhs)
            return lhsRank == rhsRank ? lhs < rhs : lhsRank < rhsRank
        }
    }

    /// One `AF_* · SOCK_* · IPPROTO_*` line per distinct signature.
    var signatureDetails: [String] {
        guard let signatures = socketSignatures, !signatures.isEmpty else { return [] }
        return signatures.map { signature in
            let family = KBSocketFamily.name(for: UInt32(max(signature.family, 0)))
            let type = KBSocketType.name(for: signature.type)
            let proto = signature.protocolNumber == 0
                ? "IPPROTO_0"
                : KBIPProtocol.name(for: signature.protocolNumber)
            return "\(family) · \(type) · \(proto)"
        }
    }

    /// True when one distinct socket signature satisfies all selected facets.
    /// A protocol selection only matches IP sockets: AF_UNIX/other domains have
    /// no IPPROTO, so they are excluded when the group is not fully selected.
    func matchesSocketFacets(domains: Set<ProcessDomain>,
                             protocols: Set<ProcessProtocolCategory>,
                             types: Set<ProcessSocketType>) -> Bool {
        // Preserve the "an empty group matches nothing" convention.
        if domains.isEmpty || protocols.isEmpty || types.isEmpty { return false }

        if let signatures = socketSignatures, !signatures.isEmpty {
            return signatures.contains { signature in
                let domain = ProcessDomain.category(forFamily: signature.family)
                guard domains.contains(domain) else { return false }
                let type = ProcessSocketType.category(forTypeNumber: signature.type)
                guard types.contains(type) else { return false }
                if protocols != ProcessProtocolCategory.all {
                    guard domain.isInternet else { return false }
                    let proto = ProcessProtocolCategory.category(
                        forNumber: signature.protocolNumber)
                    guard protocols.contains(proto) else { return false }
                }
                return true
            }
        }
        return matchesLegacySocketFacets(domains: domains,
                                         protocols: protocols,
                                         types: types)
    }

    /// Approximate matching for rows without signatures (old daemon, fully
    /// restricted scan, or scanned with zero sockets). Aggregates cannot prove
    /// same-socket pairing, so this preserves the previous behavior.
    private func matchesLegacySocketFacets(domains: Set<ProcessDomain>,
                                           protocols: Set<ProcessProtocolCategory>,
                                           types: Set<ProcessSocketType>) -> Bool {
        if domains != ProcessDomain.all {
            let wanted = domains.reduce(into: Set<ProcessProtocolTag>()) {
                $0.formUnion($1.legacyTags)
            }
            guard !self.protocols.isDisjoint(with: wanted) else { return false }
        }
        if types != ProcessSocketType.all {
            guard let counts = socketTypes,
                  types.contains(where: { $0.count(in: counts) > 0 })
            else { return false }
        }
        if protocols != ProcessProtocolCategory.all {
            let matched = protocols.contains { category in
                switch category {
                case .tcp: return !self.protocols.isDisjoint(with: [.tcp4, .tcp6])
                case .udp: return !self.protocols.isDisjoint(with: [.udp4, .udp6])
                case .raw: return legacyRawMatch(255)
                case .icmp: return legacyRawMatch(1)
                case .icmpv6: return legacyRawMatch(58)
                case .sctp: return legacyRawMatch(132)
                case .gre: return legacyRawMatch(47)
                case .esp: return legacyRawMatch(50)
                case .other:
                    if self.protocols.contains(.other) { return true }
                    return rawProtocolNumbers.contains {
                        ProcessProtocolCategory.category(forNumber: $0) == .other
                    }
                }
            }
            guard matched else { return false }
        }
        return true
    }

    private func legacyRawMatch(_ number: Int32) -> Bool {
        guard !protocols.isDisjoint(with: [.raw4, .raw6]) else { return false }
        // Truly old scanners did not report otherProtocols: over-include
        // rather than silently hiding rows.
        return rawProtocolNumbers.isEmpty || rawProtocolNumbers.contains(number)
    }
}

extension AppModel {
    func filteredInterfaces(_ focus: NetworkingFocus?,
                            search: String = "") -> [KBInterfaceInfo] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = needle.isEmpty ? interfaces : interfaces.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.kind.displayName.localizedCaseInsensitiveContains(needle)
                || $0.stateDescription.localizedCaseInsensitiveContains(needle)
        }
        guard let focus else { return base }
        let sourcedNames = Set(sources.map(\.interfaceName).filter { !$0.isEmpty })
        switch focus {
        case .download:
            return base.filter {
                !$0.isLoopback && $0.kind != .tunnel
                    && (interfaceRates[$0.id]?.rxBytesPerSecond ?? 0) > 0
            }
        case .upload:
            return base.filter {
                !$0.isLoopback && $0.kind != .tunnel
                    && (interfaceRates[$0.id]?.txBytesPerSecond ?? 0) > 0
            }
        case .active:
            let activeNames = Set(sources.lazy
                .filter { self.activeSourceIDs.contains($0.id) }
                .map(\.interfaceName)
                .filter { !$0.isEmpty })
            return base.filter { activeNames.contains($0.name) }
        case .connections, .processes:
            return base.filter { sourcedNames.contains($0.name) }
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
                // Sources without a TCP state (UDP) are left to the Transport
                // filter: unchecking Other must not hide them.
                guard let category = NetworkingConnectionState.category(for: $0.tcpState)
                else { return true }
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
            return base
        case .active:
            return base.filter { self.activeSourceIDs.contains($0.id) }
        case .processes:
            return base.filter { $0.pid > 0 }
        }
    }

    func filteredProcessRows(_ focus: NetworkingFocus?,
                             domains: Set<ProcessDomain> = ProcessDomain.all,
                             protocols: Set<ProcessProtocolCategory> = ProcessProtocolCategory.all,
                             socketTypes: Set<ProcessSocketType> = ProcessSocketType.all,
                             search: String = "")
        -> [ProcessInventoryRow] {
        let activePIDs: Set<Int32> = focus == .active
            ? Set(sources.lazy.filter { self.activeSourceIDs.contains($0.id) }.map(\.pid))
            : []
        let facetsFiltered = domains != ProcessDomain.all
            || protocols != ProcessProtocolCategory.all
            || socketTypes != ProcessSocketType.all
        return processInventory.filter { row in
            if facetsFiltered,
               !row.matchesSocketFacets(domains: domains,
                                        protocols: protocols,
                                        types: socketTypes) {
                return false
            }
            guard row.process.matchesSearch(search, userNames: userNames) else { return false }
            switch focus {
            case .download:
                return row.rates.rxBytesPerSecond > 0
            case .upload:
                return row.rates.txBytesPerSecond > 0
            case .connections:
                return row.connectionCount > 0
            case .active:
                return activePIDs.contains(row.process.pid)
            case .processes, nil:
                return true
            }
        }
    }
}
