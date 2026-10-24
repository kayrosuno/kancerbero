import Darwin
import Foundation

enum KBInterop {
    /// Copies a fixed-size C char array imported as a Swift tuple.
    static func string<T>(_ tuple: T) -> String {
        var value = tuple
        return withUnsafeBytes(of: &value) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func bytes<T>(_ tuple: T, count: Int) -> [UInt8] {
        var value = tuple
        return withUnsafeBytes(of: &value) { raw in
            Array(raw.prefix(count))
        }
    }

    static func endpoint(family: UInt8, address: [UInt8], port: UInt16, scope: UInt32) -> KBEndpoint {
        KBEndpoint(family: family, address: formatAddress(family: family, bytes: address),
                   port: port, scopeID: scope)
    }

    static func formatAddress(family: UInt8, bytes: [UInt8]) -> String {
        switch family {
        case 4:
            guard bytes.count >= 4 else { return "" }
            return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
        case 6:
            guard bytes.count >= 16 else { return "" }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let result = bytes.withUnsafeBytes { raw in
                inet_ntop(AF_INET6, raw.baseAddress, &buffer, socklen_t(INET6_ADDRSTRLEN))
            }
            return result == nil ? "" : String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        default:
            return ""
        }
    }

    static func monotonicNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
