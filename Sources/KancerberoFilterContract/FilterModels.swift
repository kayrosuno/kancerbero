import Foundation

/// Shared contract between the app and the Network Extension. Everything here
/// is Foundation-only and Codable so both targets can link the same types
/// without pulling in private APIs.

public enum FilterVersion {
    public static let schema = 1
    public static let current = "0.1.0"
}

public enum FilterPolicy: String, Codable, Sendable, CaseIterable, Identifiable {
    case ask
    case allow
    case deny

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ask: return "Ask"
        case .allow: return "Allow"
        case .deny: return "Deny"
        }
    }

    public var detail: String {
        switch self {
        case .ask: return "Ask before each new connection"
        case .allow: return "Always allow this process"
        case .deny: return "Always block this process"
        }
    }
}

/// A process the user has chosen to watch. Identity is the executable path
/// because `NEFilterFlow.sourceAppIdentifier` is unavailable on macOS.
public struct FilterRule: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var executablePath: String
    /// Informational only; the extension cannot read bundle identifiers.
    public var bundleID: String?
    public var displayName: String
    public var policy: FilterPolicy
    public var createdAt: Date

    public init(id: UUID = UUID(),
                executablePath: String,
                bundleID: String? = nil,
                displayName: String,
                policy: FilterPolicy = .ask,
                createdAt: Date = Date()) {
        self.id = id
        self.executablePath = executablePath
        self.bundleID = bundleID
        self.displayName = displayName
        self.policy = policy
        self.createdAt = createdAt
    }
}

public enum FilterRemember: String, Codable, Sendable, CaseIterable {
    case none
    case app
    case destination
}

/// A decision the user asked to remember. `destination` is only used when
/// `remember == .destination` and is formatted as `host:port`.
public struct RememberedDecision: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var executablePath: String
    public var destination: String?
    public var allow: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(),
                executablePath: String,
                destination: String? = nil,
                allow: Bool,
                createdAt: Date = Date()) {
        self.id = id
        self.executablePath = executablePath
        self.destination = destination
        self.allow = allow
        self.createdAt = createdAt
    }
}

public struct FilterEndpoint: Codable, Sendable, Hashable {
    public var address: String
    public var port: UInt16
    public var hostname: String?

    public init(address: String, port: UInt16, hostname: String? = nil) {
        self.address = address
        self.port = port
        self.hostname = hostname
    }

    public var display: String {
        let host = hostname ?? address
        return port > 0 ? "\(host):\(port)" : host
    }

    public var destinationKey: String {
        let host = hostname ?? address
        return "\(host):\(port)"
    }

    /// Every key this endpoint can be matched by. macOS only reports
    /// `remoteHostname` for some flows, so a remembered "app + destination"
    /// decision must match either `host:port` or `address:port`.
    public var destinationKeys: [String] {
        var keys: [String] = []
        if let hostname, !hostname.isEmpty, hostname != address {
            keys.append("\(hostname):\(port)")
        }
        keys.append("\(address):\(port)")
        return keys
    }
}

public enum FilterFlowState: String, Codable, Sendable {
    case observing
    case allowed
    case denied
    case pending
}

public struct FilterRequest: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var pid: Int32
    public var executablePath: String
    public var processName: String
    public var local: FilterEndpoint?
    public var remote: FilterEndpoint?
    public var transport: String
    public var startedAt: Date
    public var deadline: Date
    public var delegated: Bool

    public init(id: UUID,
                pid: Int32,
                executablePath: String,
                processName: String,
                local: FilterEndpoint?,
                remote: FilterEndpoint?,
                transport: String,
                startedAt: Date = Date(),
                deadline: Date,
                delegated: Bool = false) {
        self.id = id
        self.pid = pid
        self.executablePath = executablePath
        self.processName = processName
        self.local = local
        self.remote = remote
        self.transport = transport
        self.startedAt = startedAt
        self.deadline = deadline
        self.delegated = delegated
    }
}

public struct FlowRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var pid: Int32
    public var executablePath: String
    public var processName: String
    public var local: FilterEndpoint?
    public var remote: FilterEndpoint?
    public var transport: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var startedAt: Date
    public var endedAt: Date?
    public var state: FilterFlowState
    public var ruleID: UUID?
    public var deniedReason: String?
    public var delegated: Bool

    public init(id: UUID,
                pid: Int32,
                executablePath: String,
                processName: String,
                local: FilterEndpoint?,
                remote: FilterEndpoint?,
                transport: String,
                bytesIn: UInt64 = 0,
                bytesOut: UInt64 = 0,
                startedAt: Date = Date(),
                endedAt: Date? = nil,
                state: FilterFlowState,
                ruleID: UUID? = nil,
                deniedReason: String? = nil,
                delegated: Bool = false) {
        self.id = id
        self.pid = pid
        self.executablePath = executablePath
        self.processName = processName
        self.local = local
        self.remote = remote
        self.transport = transport
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.state = state
        self.ruleID = ruleID
        self.deniedReason = deniedReason
        self.delegated = delegated
    }

    public var totalBytes: UInt64 { bytesIn &+ bytesOut }
}

public struct FilterStatus: Codable, Sendable, Equatable {
    public var version: String
    public var startedAt: Date?
    public var ruleCount: Int
    public var clientCount: Int
    public var pausedFlows: Int
    public var observedFlows: Int
    public var lastError: String?

    public init(version: String = FilterVersion.current,
                startedAt: Date? = nil,
                ruleCount: Int = 0,
                clientCount: Int = 0,
                pausedFlows: Int = 0,
                observedFlows: Int = 0,
                lastError: String? = nil) {
        self.version = version
        self.startedAt = startedAt
        self.ruleCount = ruleCount
        self.clientCount = clientCount
        self.pausedFlows = pausedFlows
        self.observedFlows = observedFlows
        self.lastError = lastError
    }
}

public struct FilterRuleSnapshot: Codable, Sendable, Equatable {
    public var rules: [FilterRule]
    public var remembered: [RememberedDecision]
    /// Global override: deny every new flow, regardless of rules or remembered
    /// decisions. It is not a `FilterRule` and never appears in the rules list.
    public var blockAllNewConnections: Bool

    private enum CodingKeys: String, CodingKey {
        case rules, remembered, blockAllNewConnections
    }

    public init(rules: [FilterRule] = [],
                remembered: [RememberedDecision] = [],
                blockAllNewConnections: Bool = false) {
        self.rules = rules
        self.remembered = remembered
        self.blockAllNewConnections = blockAllNewConnections
    }

    /// Added after the first release: old app payloads and the extension's
    /// cached `rules.plist` do not carry it, so decode it as false.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decode([FilterRule].self, forKey: .rules)
        remembered = try container.decode([RememberedDecision].self, forKey: .remembered)
        blockAllNewConnections = try container.decodeIfPresent(
            Bool.self, forKey: .blockAllNewConnections) ?? false
    }
}

public struct FilterSnapshot: Codable, Sendable, Equatable {
    public var status: FilterStatus
    public var rules: [FilterRule]
    public var remembered: [RememberedDecision]
    public var flows: [FlowRecord]
    public var pending: [FilterRequest]
    public var history: [FlowRecord]

    public init(status: FilterStatus,
                rules: [FilterRule],
                remembered: [RememberedDecision],
                flows: [FlowRecord],
                pending: [FilterRequest],
                history: [FlowRecord]) {
        self.status = status
        self.rules = rules
        self.remembered = remembered
        self.flows = flows
        self.pending = pending
        self.history = history
    }
}

public enum FilterDecisionKind: String, Codable, Sendable {
    case once
    case rememberApp
    case rememberDestination
    case alwaysDeny
    case alwaysAllow
}

public struct FilterDecisionMessage: Codable, Sendable {
    public var flowID: UUID
    public var allow: Bool
    public var remember: FilterRemember
    public var destinationKey: String?
    /// All keys of the decided destination (`host:port` and `address:port`).
    public var destinationKeys: [String]?
    public var executablePath: String?

    public init(flowID: UUID,
                allow: Bool,
                remember: FilterRemember = .none,
                destinationKey: String? = nil,
                destinationKeys: [String]? = nil,
                executablePath: String? = nil) {
        self.flowID = flowID
        self.allow = allow
        self.remember = remember
        self.destinationKey = destinationKey
        self.destinationKeys = destinationKeys
        self.executablePath = executablePath
    }
}
