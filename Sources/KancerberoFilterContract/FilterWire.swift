import Foundation

/// Envelope exchanged over the extension's Mach service. Payloads travel as
/// encoded `Data` so the `@objc` XPC protocols stay Foundation-only.

public struct FilterEnvelope: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hello
        case helloAck
        case setRules
        case setRulesAck
        case decide
        case decideAck
        case snapshotRequest
        case snapshot
        case push
    }

    public var schemaVersion: Int
    public var kind: Kind
    public var payload: Data

    public init(kind: Kind, payload: Data = Data(), schemaVersion: Int = FilterVersion.schema) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.payload = payload
    }
}

public struct FilterHello: Codable, Sendable {
    public var schemaVersion: Int
    public var appVersion: String

    public init(schemaVersion: Int = FilterVersion.schema,
                appVersion: String = FilterVersion.current) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
    }
}

public struct FilterAck: Codable, Sendable {
    public var ok: Bool
    public var message: String?

    public init(ok: Bool, message: String? = nil) {
        self.ok = ok
        self.message = message
    }
}

public struct FilterPush: Codable, Sendable {
    public var status: FilterStatus?
    public var pending: [FilterRequest]
    public var resolved: [UUID]
    public var flows: [FlowRecord]
    public var removedFlows: [UUID]
    public var history: [FlowRecord]

    public init(status: FilterStatus? = nil,
                pending: [FilterRequest] = [],
                resolved: [UUID] = [],
                flows: [FlowRecord] = [],
                removedFlows: [UUID] = [],
                history: [FlowRecord] = []) {
        self.status = status
        self.pending = pending
        self.resolved = resolved
        self.flows = flows
        self.removedFlows = removedFlows
        self.history = history
    }

    public var isEmpty: Bool {
        status == nil && pending.isEmpty && resolved.isEmpty
            && flows.isEmpty && removedFlows.isEmpty && history.isEmpty
    }
}

public enum FilterCodec {
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try PropertyListDecoder().decode(type, from: data)
    }

    public static func envelope(_ kind: FilterEnvelope.Kind, payload: Data = Data()) -> Data {
        // Encoding a fixed envelope cannot fail in practice; fall back to an
        // empty payload envelope so a XPC reply is always produced.
        (try? encode(FilterEnvelope(kind: kind, payload: payload)))
            ?? Data()
    }

    public static func envelope<T: Encodable>(_ kind: FilterEnvelope.Kind, value: T) -> Data {
        let payload = (try? encode(value)) ?? Data()
        return envelope(kind, payload: payload)
    }

    public static func decodeEnvelope(_ data: Data) throws -> FilterEnvelope {
        try decode(FilterEnvelope.self, from: data)
    }

    public static func decodePayload<T: Decodable>(_ type: T.Type, from envelope: FilterEnvelope) throws -> T {
        try decode(type, from: envelope.payload)
    }
}
