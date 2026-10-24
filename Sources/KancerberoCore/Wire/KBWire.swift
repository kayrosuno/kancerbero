import Foundation

public enum KBWireKind: String, Codable, Sendable {
    case hello
    case subscribeAck
    case snapshot
    case processDetail
    case error
    case state
}

public struct KBWireEnvelope: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: KBWireKind
    public var sequence: UInt64
    public var generatedAt: Date
    public var monotonicNanoseconds: UInt64
    public var payload: Data

    public init(schemaVersion: Int = KBVersion.schema, kind: KBWireKind, sequence: UInt64,
                generatedAt: Date = Date(), monotonicNanoseconds: UInt64,
                payload: Data) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.monotonicNanoseconds = monotonicNanoseconds
        self.payload = payload
    }
}

public struct KBHelloRequest: Codable, Sendable {
    public var appVersion: String
    public var schemaVersion: Int

    public init(appVersion: String = KBVersion.current, schemaVersion: Int = KBVersion.schema) {
        self.appVersion = appVersion
        self.schemaVersion = schemaVersion
    }
}

public struct KBHelloResponse: Codable, Sendable {
    public var daemonVersion: String
    public var coreVersion: String
    public var schemaVersion: Int
    public var capabilities: KBCapabilities

    public init(daemonVersion: String = KBVersion.current, coreVersion: String = KBVersion.coreVersion,
                schemaVersion: Int = KBVersion.schema, capabilities: KBCapabilities) {
        self.daemonVersion = daemonVersion
        self.coreVersion = coreVersion
        self.schemaVersion = schemaVersion
        self.capabilities = capabilities
    }
}

public enum KBSubscriptionTopic: String, Codable, Sendable {
    case networkByProcess
    case connections
    case interfaces
}

public struct KBSubscription: Codable, Sendable {
    public var interval: TimeInterval
    public var topics: [KBSubscriptionTopic]

    public init(interval: TimeInterval = 1.0, topics: [KBSubscriptionTopic] = [.networkByProcess, .connections, .interfaces]) {
        self.interval = interval
        self.topics = topics
    }
}

public struct KBRequestMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case snapshot
        case processDetail
    }

    public var kind: Kind
    public var pid: Int32?

    public init(kind: Kind, pid: Int32? = nil) {
        self.kind = kind
        self.pid = pid
    }
}

public struct KBSnapshotPayload: Codable, Sendable {
    public var collection: KBCollectionSnapshot
    public var capabilities: KBCapabilities
    public var diagnostics: KBDiagnostics

    public init(collection: KBCollectionSnapshot, capabilities: KBCapabilities,
                diagnostics: KBDiagnostics) {
        self.collection = collection
        self.capabilities = capabilities
        self.diagnostics = diagnostics
    }
}

public struct KBDetailPayload: Codable, Sendable {
    public var detail: KBProcessDetail

    public init(detail: KBProcessDetail) {
        self.detail = detail
    }
}

public struct KBErrorMessage: Codable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum KBWireCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try PropertyListDecoder().decode(type, from: data)
    }
}
