import Darwin
import Foundation

public enum KBVersion {
    public static let current = "0.1.0"
    public static let schema = 1
    public static var coreVersion: String {
        String(cString: kb_version())
    }
}

public struct KBProcessKey: Hashable, Codable, Sendable, Identifiable {
    public var pid: Int32
    public var startTimeUS: UInt64

    public var id: String { "\(pid):\(startTimeUS)" }

    public init(pid: Int32, startTimeUS: UInt64) {
        self.pid = pid
        self.startTimeUS = startTimeUS
    }
}

public struct KBCounters: Codable, Sendable, Hashable {
    public var rxBytes: UInt64
    public var txBytes: UInt64
    public var rxPackets: UInt64
    public var txPackets: UInt64

    public init(rxBytes: UInt64 = 0, txBytes: UInt64 = 0,
                rxPackets: UInt64 = 0, txPackets: UInt64 = 0) {
        self.rxBytes = rxBytes
        self.txBytes = txBytes
        self.rxPackets = rxPackets
        self.txPackets = txPackets
    }

    public static let zero = KBCounters()

    public static func + (lhs: KBCounters, rhs: KBCounters) -> KBCounters {
        KBCounters(rxBytes: lhs.rxBytes &+ rhs.rxBytes,
                   txBytes: lhs.txBytes &+ rhs.txBytes,
                   rxPackets: lhs.rxPackets &+ rhs.rxPackets,
                   txPackets: lhs.txPackets &+ rhs.txPackets)
    }

    /// Non-negative delta between cumulative counters. A decrease (counter
    /// reset or a crossed sample) contributes zero; returning the full
    /// cumulative value would turn it into a one-tick GB/s spike.
    public func positiveDelta(from previous: KBCounters) -> KBCounters {
        KBCounters(
            rxBytes: rxBytes >= previous.rxBytes ? rxBytes - previous.rxBytes : 0,
            txBytes: txBytes >= previous.txBytes ? txBytes - previous.txBytes : 0,
            rxPackets: rxPackets >= previous.rxPackets ? rxPackets - previous.rxPackets : 0,
            txPackets: txPackets >= previous.txPackets ? txPackets - previous.txPackets : 0
        )
    }
}

public struct KBRates: Codable, Sendable, Hashable {
    public var rxBytesPerSecond: Double
    public var txBytesPerSecond: Double
    public var rxPacketsPerSecond: Double
    public var txPacketsPerSecond: Double

    public init(rxBytesPerSecond: Double = 0, txBytesPerSecond: Double = 0,
                rxPacketsPerSecond: Double = 0, txPacketsPerSecond: Double = 0) {
        self.rxBytesPerSecond = rxBytesPerSecond
        self.txBytesPerSecond = txBytesPerSecond
        self.rxPacketsPerSecond = rxPacketsPerSecond
        self.txPacketsPerSecond = txPacketsPerSecond
    }

    public static let zero = KBRates()
}

public enum KBInterfaceKind: String, Codable, Sendable, CaseIterable {
    case wifi
    case wired
    case cellular
    case loopback
    case tunnel
    case bridge
    case virtual
    case other

    public var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .wired: return "Ethernet"
        case .cellular: return "Cellular"
        case .loopback: return "Loopback"
        case .tunnel: return "Tunnel"
        case .bridge: return "Bridge"
        case .virtual: return "Virtual"
        case .other: return "Other"
        }
    }
}

public enum KBMode: String, Codable, Sendable {
    case daemonFull
    case daemonRestricted
    case localFullNStat
    case localDegraded
    case interfacesOnly
}

public enum KBConnectionProtocol: String, Codable, CaseIterable, Identifiable, Hashable,
                                    Sendable {
    case tcp4
    case tcp6
    case udp4
    case udp6
    case unix
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tcp4: return "TCP4"
        case .tcp6: return "TCP6"
        case .udp4: return "UDP4"
        case .udp6: return "UDP6"
        case .unix: return "UNIX"
        case .other: return "OTHER"
        }
    }
}

public struct KBEndpoint: Codable, Sendable, Hashable {
    public var family: UInt8
    public var address: String
    public var port: UInt16
    public var scopeID: UInt32

    public init(family: UInt8 = 0, address: String = "", port: UInt16 = 0, scopeID: UInt32 = 0) {
        self.family = family
        self.address = address
        self.port = port
        self.scopeID = scopeID
    }

    public var display: String {
        switch family {
        case 4:
            return "\(address):\(port)"
        case 6:
            let zone = scopeID == 0 ? "" : "%\(scopeID)"
            return "[\(address)\(zone)]:\(port)"
        default:
            return address.isEmpty ? "*" : address
        }
    }
}

public struct KBProcessInfo: Codable, Sendable, Identifiable, Hashable {
    public var pid: Int32
    public var ppid: Int32
    public var uid: UInt32
    public var startTimeUS: UInt64
    public var name: String
    public var path: String
    public var state: KBProcessState?
    public var nice: Int32?
    public var usage: KBProcessUsage?

    public var id: KBProcessKey { KBProcessKey(pid: pid, startTimeUS: startTimeUS) }

    public init(pid: Int32, ppid: Int32 = 0, uid: UInt32 = 0,
                startTimeUS: UInt64 = 0, name: String = "", path: String = "",
                state: KBProcessState? = nil, nice: Int32? = nil,
                usage: KBProcessUsage? = nil) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.startTimeUS = startTimeUS
        self.name = name
        self.path = path
        self.state = state
        self.nice = nice
        self.usage = usage
    }
}

public struct KBNStatSource: Codable, Sendable, Identifiable, Hashable {
    public var sourceID: UInt64
    public var pid: Int32
    public var epid: Int32
    public var processName: String
    public var provider: String
    public var tcpState: String
    public var interfaceName: String
    public var interfaceType: String
    /// Process UUID from NetworkStatistics; it is not unique per flow.
    public var uuid: String
    public var local: KBEndpoint
    public var remote: KBEndpoint
    public var counters: KBCounters
    public var rxWiFi: UInt64
    public var txWiFi: UInt64
    public var rxWired: UInt64
    public var txWired: UInt64
    public var rxCellular: UInt64
    public var txCellular: UInt64
    public var rxDuplicates: UInt64
    public var rxOutOfOrder: UInt64
    public var txRetransmits: UInt64
    public var rtt: Double
    public var startNanoseconds: UInt64
    public var rates: KBRates = .zero

    public var id: String {
        if sourceID != 0 { return String(sourceID) }
        return "\(pid)-\(local.display)-\(remote.display)-\(provider)"
    }

    public var connectionProtocol: KBConnectionProtocol {
        let proto = provider.lowercased()
        let isTCP = proto.contains("tcp")
        let isUDP = proto.contains("udp")
        guard isTCP || isUDP else { return .other }
        if local.family == 6 || remote.family == 6 {
            return isTCP ? .tcp6 : .udp6
        }
        return isTCP ? .tcp4 : .udp4
    }
}

public struct KBInterfaceInfo: Codable, Sendable, Identifiable, Hashable {
    public var index: UInt32
    public var name: String
    public var flags: UInt32
    public var type: UInt32
    public var counters: KBCounters
    public var rxErrors: UInt64
    public var txErrors: UInt64
    public var rxDrops: UInt64
    public var collisions: UInt64
    public var mtu: UInt32
    public var baudrate: UInt64

    public var id: UInt32 { index }

    public var isUp: Bool { (flags & UInt32(IFF_UP)) != 0 }
    public var isRunning: Bool { (flags & UInt32(IFF_RUNNING)) != 0 }
    public var isLoopback: Bool { (flags & UInt32(IFF_LOOPBACK)) != 0 }

    public var kind: KBInterfaceKind {
        if isLoopback { return .loopback }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("gif") { return .tunnel }
        if name.hasPrefix("bridge") { return .bridge }
        if name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("anpi") { return .wifi }
        if name.hasPrefix("pdp_ip") { return .cellular }
        if name.hasPrefix("en") || name.hasPrefix("eth") { return .wired }
        return .other
    }

    public init(index: UInt32, name: String, flags: UInt32 = 0, type: UInt32 = 0,
                counters: KBCounters = .zero, rxErrors: UInt64 = 0, txErrors: UInt64 = 0,
                rxDrops: UInt64 = 0, collisions: UInt64 = 0, mtu: UInt32 = 0, baudrate: UInt64 = 0) {
        self.index = index
        self.name = name
        self.flags = flags
        self.type = type
        self.counters = counters
        self.rxErrors = rxErrors
        self.txErrors = txErrors
        self.rxDrops = rxDrops
        self.collisions = collisions
        self.mtu = mtu
        self.baudrate = baudrate
    }
}

public struct KBProcessSample: Codable, Sendable, Identifiable {
    public var key: KBProcessKey
    public var pid: Int32
    public var uid: UInt32
    public var name: String
    public var path: String
    public var counters: KBCounters
    public var rates: KBRates
    public var connectionCount: Int

    public var id: KBProcessKey { key }

    public init(key: KBProcessKey, pid: Int32, uid: UInt32 = 0,
                name: String = "", path: String = "", counters: KBCounters = .zero,
                rates: KBRates = .zero, connectionCount: Int = 0) {
        self.key = key
        self.pid = pid
        self.uid = uid
        self.name = name
        self.path = path
        self.counters = counters
        self.rates = rates
        self.connectionCount = connectionCount
    }
}

public struct KBInterfaceSample: Codable, Sendable, Identifiable {
    public var interfaceInfo: KBInterfaceInfo
    public var rates: KBRates

    public var id: UInt32 { interfaceInfo.id }

    public init(interfaceInfo: KBInterfaceInfo, rates: KBRates = .zero) {
        self.interfaceInfo = interfaceInfo
        self.rates = rates
    }
}

public struct KBSystemTotals: Codable, Sendable {
    public var counters: KBCounters
    public var rates: KBRates

    public init(counters: KBCounters = .zero, rates: KBRates = .zero) {
        self.counters = counters
        self.rates = rates
    }
}

public struct KBSnapshot: Codable, Sendable {
    public var sequence: UInt64
    public var generatedAt: Date
    public var monotonicNanoseconds: UInt64
    public var mode: KBMode
    public var interval: TimeInterval
    public var processes: [KBProcessSample]
    public var connections: [KBNStatSource]
    public var interfaces: [KBInterfaceSample]
    public var system: KBSystemTotals

    public init(sequence: UInt64, generatedAt: Date, monotonicNanoseconds: UInt64,
                mode: KBMode, interval: TimeInterval,
                processes: [KBProcessSample] = [], connections: [KBNStatSource] = [],
                interfaces: [KBInterfaceSample] = [], system: KBSystemTotals = KBSystemTotals()) {
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.monotonicNanoseconds = monotonicNanoseconds
        self.mode = mode
        self.interval = interval
        self.processes = processes
        self.connections = connections
        self.interfaces = interfaces
        self.system = system
    }
}

public struct KBOpenFileSample: Codable, Sendable, Identifiable, Hashable {
    public var fd: Int32
    public var type: String
    public var path: String
    public var size: Int64
    public var socket: KBNStatSource?

    public var id: Int32 { fd }

    public init(fd: Int32, type: String, path: String = "", size: Int64 = 0,
                socket: KBNStatSource? = nil) {
        self.fd = fd
        self.type = type
        self.path = path
        self.size = size
        self.socket = socket
    }
}

public struct KBProcessDetail: Codable, Sendable {
    public var process: KBProcessInfo
    public var sockets: [KBSocketInfo]
    public var openFiles: [KBOpenFileSample]
    public var restricted: Bool
    public var source: String
    public var generatedAt: Date
    public var processGone: Bool

    public init(process: KBProcessInfo, sockets: [KBSocketInfo] = [],
                openFiles: [KBOpenFileSample] = [], restricted: Bool = false,
                source: String = "libproc", generatedAt: Date = Date(),
                processGone: Bool = false) {
        self.process = process
        self.sockets = sockets
        self.openFiles = openFiles
        self.restricted = restricted
        self.source = source
        self.generatedAt = generatedAt
        self.processGone = processGone
    }
}

public struct KBCapabilities: Codable, Sendable {
    public var nstat: Bool
    public var root: Bool
    public var statisticsPrivcheck: Int
    public var libprocAllUsers: Bool
    public var interfaceSplits: Bool
    /// The daemon handles `trashItems`. Optional so an older daemon decodes as nil.
    public var trash: Bool?

    public init(nstat: Bool = false, root: Bool = false, statisticsPrivcheck: Int = 0,
                libprocAllUsers: Bool = false, interfaceSplits: Bool = false,
                trash: Bool? = nil) {
        self.nstat = nstat
        self.root = root
        self.statisticsPrivcheck = statisticsPrivcheck
        self.libprocAllUsers = libprocAllUsers
        self.interfaceSplits = interfaceSplits
        self.trash = trash
    }
}

public struct KBDiagnostics: Codable, Sendable {
    public var appVersion: String
    public var coreVersion: String
    public var schemaVersion: Int
    public var systemVersion: String
    public var architecture: String
    public var sourceCount: Int
    public var tickDurationMilliseconds: Double
    public var droppedTicks: UInt64
    public var lastError: String?

    public init(appVersion: String = KBVersion.current, coreVersion: String = KBVersion.coreVersion,
                schemaVersion: Int = KBVersion.schema,
                systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: String = "arm64", sourceCount: Int = 0,
                tickDurationMilliseconds: Double = 0, droppedTicks: UInt64 = 0,
                lastError: String? = nil) {
        self.appVersion = appVersion
        self.coreVersion = coreVersion
        self.schemaVersion = schemaVersion
        self.systemVersion = systemVersion
        self.architecture = architecture
        self.sourceCount = sourceCount
        self.tickDurationMilliseconds = tickDurationMilliseconds
        self.droppedTicks = droppedTicks
        self.lastError = lastError
    }
}

public enum KBTCPState {
    public static func name(_ state: Int32) -> String {
        switch state {
        case 0: return "Closed"
        case 1: return "Listen"
        case 2: return "SynSent"
        case 3: return "SynReceived"
        case 4: return "Established"
        case 5: return "CloseWait"
        case 6: return "FinWait1"
        case 7: return "Closing"
        case 8: return "LastAck"
        case 9: return "FinWait2"
        case 10: return "TimeWait"
        default: return "Unknown"
        }
    }
}

/// Darwin address family names, from <sys/socket.h>. 26 and 39 are unassigned
/// and fall through to the numeric label.
public enum KBSocketFamily {
    public static func name(for family: UInt32) -> String {
        switch family {
        case 0: return "AF_UNSPEC"
        case 1: return "AF_UNIX"
        case 2: return "AF_INET"
        case 3: return "AF_IMPLINK"
        case 4: return "AF_PUP"
        case 5: return "AF_CHAOS"
        case 6: return "AF_NS"
        case 7: return "AF_ISO"
        case 8: return "AF_ECMA"
        case 9: return "AF_DATAKIT"
        case 10: return "AF_CCITT"
        case 11: return "AF_SNA"
        case 12: return "AF_DECnet"
        case 13: return "AF_DLI"
        case 14: return "AF_LAT"
        case 15: return "AF_HYLINK"
        case 16: return "AF_APPLETALK"
        case 17: return "AF_ROUTE"
        case 18: return "AF_LINK"
        case 19: return "AF_XTP"
        case 20: return "AF_COIP"
        case 21: return "AF_CNT"
        case 22: return "AF_RTIP"
        case 23: return "AF_IPX"
        case 24: return "AF_SIP"
        case 25: return "AF_PIP"
        case 27: return "AF_NDRV"
        case 28: return "AF_ISDN"
        case 29: return "AF_KEY"
        case 30: return "AF_INET6"
        case 31: return "AF_NATM"
        case 32: return "AF_SYSTEM"
        case 33: return "AF_NETBIOS"
        case 34: return "AF_PPP"
        case 35: return "AF_HDRCMPLT"
        case 36: return "AF_RESERVED_36"
        case 37: return "AF_IEEE80211"
        case 38: return "AF_UTUN"
        case 40: return "AF_VSOCK"
        default: return "AF_\(family)"
        }
    }
}

/// IP protocol names for sockets that are neither TCP nor UDP.
public enum KBIPProtocol {
    public static func name(for number: Int32) -> String {
        switch number {
        case 0: return "RAW"
        case 1: return "ICMP"
        case 2: return "IGMP"
        case 4: return "IPIP"
        case 6: return "TCP"
        case 17: return "UDP"
        case 33: return "DCCP"
        case 41: return "IPv6"
        case 47: return "GRE"
        case 50: return "ESP"
        case 51: return "AH"
        case 58: return "ICMPv6"
        case 89: return "OSPF"
        case 103: return "PIM"
        case 112: return "VRRP"
        case 132: return "SCTP"
        case 136: return "UDPLite"
        case 255: return "RAW"
        default: return "IPPROTO_\(number)"
        }
    }
}

public struct KBSocketInfo: Codable, Sendable, Identifiable, Hashable {
    public var fd: Int32
    public var family: Int32
    public var protocolNumber: Int32
    public var type: Int32
    public var state: Int32
    public var local: KBEndpoint
    public var remote: KBEndpoint

    public var id: Int32 { fd }

    /// `family` is normalized by the C layer to 4, 6, or left as AF_UNIX/other.
    /// Mirrors `kb_classify_socket`: TCP/UDP keep the family suffix, any other
    /// IPv4/IPv6 protocol shows its real name (ICMP, SCTP, GRE…) and sockets
    /// outside INET/UNIX show their address family.
    public var protocolLabel: String {
        if family == AF_UNIX { return "UNIX" }
        if family == 4 || family == 6 {
            switch protocolNumber {
            case Int32(IPPROTO_TCP): return family == 6 ? "TCP6" : "TCP4"
            case Int32(IPPROTO_UDP): return family == 6 ? "UDP6" : "UDP4"
            default: return KBIPProtocol.name(for: protocolNumber)
            }
        }
        return KBSocketFamily.name(for: UInt32(max(family, 0)))
    }

    public var stateName: String {
        protocolNumber == Int32(IPPROTO_TCP) ? KBTCPState.name(state) : ""
    }

    public init(fd: Int32, family: Int32, protocolNumber: Int32, type: Int32, state: Int32,
                local: KBEndpoint, remote: KBEndpoint) {
        self.fd = fd
        self.family = family
        self.protocolNumber = protocolNumber
        self.type = type
        self.state = state
        self.local = local
        self.remote = remote
    }
}

public struct KBSocketBucketCounts: Codable, Sendable, Hashable {
    public var tcp4: Int
    public var tcp6: Int
    public var udp4: Int
    public var udp6: Int
    public var unix: Int
    public var raw4: Int
    public var raw6: Int
    public var other: Int

    public var total: Int {
        tcp4 + tcp6 + udp4 + udp6 + unix + raw4 + raw6 + other
    }

    public init(tcp4: Int = 0, tcp6: Int = 0, udp4: Int = 0, udp6: Int = 0,
                unix: Int = 0, raw4: Int = 0, raw6: Int = 0, other: Int = 0) {
        self.tcp4 = tcp4
        self.tcp6 = tcp6
        self.udp4 = udp4
        self.udp6 = udp6
        self.unix = unix
        self.raw4 = raw4
        self.raw6 = raw6
        self.other = other
    }
}

public struct KBSocketTypeCounts: Codable, Sendable, Hashable {
    public var stream: Int
    public var dgram: Int
    public var raw: Int
    public var seqpacket: Int
    public var otherType: Int

    public var total: Int { stream + dgram + raw + seqpacket + otherType }

    public init(stream: Int = 0, dgram: Int = 0, raw: Int = 0,
                seqpacket: Int = 0, otherType: Int = 0) {
        self.stream = stream
        self.dgram = dgram
        self.raw = raw
        self.seqpacket = seqpacket
        self.otherType = otherType
    }
}

public struct KBProcessSocketSummary: Codable, Sendable, Identifiable, Hashable {
    public var key: KBProcessKey
    public var buckets: KBSocketBucketCounts
    public var types: KBSocketTypeCounts
    public var socketFDs: Int
    public var uniqueSockets: Int
    public var restricted: Bool
    public var truncated: Bool
    /// Address families (AF numbers) of the sockets counted in `buckets.other`.
    /// nil when the scanner (or an older daemon) did not report them.
    public var otherFamilies: [UInt32]?
    /// IP protocol numbers of the sockets counted in `buckets.raw4`/`raw6`, so
    /// the UI can show ICMP, SCTP… instead of the generic RAW badge. nil when
    /// the scanner (or an older daemon) did not report them.
    public var otherProtocols: [UInt8]?

    public var id: KBProcessKey { key }

    public init(key: KBProcessKey, buckets: KBSocketBucketCounts,
                types: KBSocketTypeCounts, socketFDs: Int, uniqueSockets: Int,
                restricted: Bool, truncated: Bool,
                otherFamilies: [UInt32]? = nil,
                otherProtocols: [UInt8]? = nil) {
        self.key = key
        self.buckets = buckets
        self.types = types
        self.socketFDs = socketFDs
        self.uniqueSockets = uniqueSockets
        self.restricted = restricted
        self.truncated = truncated
        self.otherFamilies = otherFamilies
        self.otherProtocols = otherProtocols
    }
}

public struct KBSocketInventory: Codable, Sendable {
    public var summaries: [KBProcessSocketSummary]
    public var generatedAt: Date
    public var durationMilliseconds: Double
    public var scannedProcesses: Int
    public var restrictedProcesses: Int
    public var truncated: Bool
    public var error: String?

    public init(summaries: [KBProcessSocketSummary] = [],
                generatedAt: Date = Date(),
                durationMilliseconds: Double = 0,
                scannedProcesses: Int = 0,
                restrictedProcesses: Int = 0,
                truncated: Bool = false,
                error: String? = nil) {
        self.summaries = summaries
        self.generatedAt = generatedAt
        self.durationMilliseconds = durationMilliseconds
        self.scannedProcesses = scannedProcesses
        self.restrictedProcesses = restrictedProcesses
        self.truncated = truncated
        self.error = error
    }
}

public struct KBOpenFileInfo: Codable, Sendable, Identifiable, Hashable {
    public var fd: Int32
    public var type: UInt32
    public var size: UInt64
    public var path: String

    public var id: Int32 { fd }

    public var typeName: String {
        switch type {
        case 1: return "file"
        case 2: return "socket"
        case 3: return "shared memory"
        case 4: return "semaphore"
        case 5: return "kqueue"
        case 6: return "pipe"
        case 7: return "event"
        case 9: return "policy"
        case 10: return "channel"
        case 11: return "nexus"
        default: return "type \(type)"
        }
    }

    public init(fd: Int32, type: UInt32, size: UInt64 = 0, path: String = "") {
        self.fd = fd
        self.type = type
        self.size = size
        self.path = path
    }
}
