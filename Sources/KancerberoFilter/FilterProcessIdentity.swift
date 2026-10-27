import Foundation
import NetworkExtension

/// Resolves the process behind a flow. On macOS `sourceAppIdentifier` is not
/// available, so the audit token is the only supported identity source.
struct FilterProcessIdentity: Sendable {
    var pid: Int32
    var path: String
    var name: String
    var delegated: Bool

    static let unknown = FilterProcessIdentity(pid: -1, path: "", name: "Unknown", delegated: false)

    static func resolve(_ flow: NEFilterFlow) -> FilterProcessIdentity {
        let appToken = flow.sourceAppAuditToken
        let processToken = flow.sourceProcessAuditToken

        var delegated = false
        if let appToken, let processToken, appToken != processToken {
            delegated = true
        }

        // Prefer the app that owns the flow; fall back to the process that
        // actually created it when the app token is missing or unresolvable.
        var resolved: Int32?
        for token in [appToken, processToken].compactMap({ $0 }) {
            if let value = pid(from: token), value > 0 {
                resolved = value
                break
            }
        }
        guard let pid = resolved else {
            return .unknown
        }

        let path = executablePath(pid: pid)
        let name = path.isEmpty
            ? processName(pid: pid)
            : (path as NSString).lastPathComponent

        return FilterProcessIdentity(pid: pid,
                                     path: path,
                                     name: name.isEmpty ? "PID \(pid)" : name,
                                     delegated: delegated)
    }

    private static func pid(from token: Data) -> Int32? {
        guard token.count == MemoryLayout<audit_token_t>.size else { return nil }
        var value = audit_token_t()
        _ = withUnsafeMutableBytes(of: &value) { destination in
            token.copyBytes(to: destination)
        }
        let result = audit_token_to_pid(value)
        return result > 0 ? result : nil
    }

    private static func executablePath(pid: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { raw in
            proc_pidpath(pid, raw.baseAddress, UInt32(raw.count))
        }
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func processName(pid: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: Int(MAXCOMLEN) + 1)
        let length = buffer.withUnsafeMutableBytes { raw in
            proc_name(pid, raw.baseAddress, UInt32(raw.count))
        }
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
