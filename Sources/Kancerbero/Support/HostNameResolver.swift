import Darwin
import Foundation

/// Reverse-DNS lookup for the numeric addresses shown in the connection
/// tables. `getnameinfo` blocks until mDNSResponder answers, so the async
/// entry point runs it on a private GCD queue instead of a cooperative-pool
/// thread.
enum HostNameResolver {
    /// A stalled resolver must not occupy every worker.
    static let maxConcurrentLookups = 6

    private static let queue = DispatchQueue(
        label: "uno.kayros.kancerbero.reverse-dns",
        qos: .utility,
        attributes: .concurrent
    )

    /// Returns a PTR name for a numeric IPv4/IPv6 literal, or nil when the
    /// address is not numeric or has no PTR record. `NI_NAMEREQD` guarantees
    /// we never return the numeric address as a "name".
    static func hostName(for address: String) -> String? {
        guard let host = hostPart(of: address), !isUnspecified(host) else { return nil }

        var address4 = in_addr()
        if inet_pton(AF_INET, host, &address4) == 1 {
            var socketAddress = sockaddr_in()
            socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            socketAddress.sin_family = sa_family_t(AF_INET)
            socketAddress.sin_addr = address4
            return lookupName(&socketAddress,
                              length: socklen_t(MemoryLayout<sockaddr_in>.size))
        }

        var address6 = in6_addr()
        if inet_pton(AF_INET6, host, &address6) == 1 {
            var socketAddress = sockaddr_in6()
            socketAddress.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            socketAddress.sin6_family = sa_family_t(AF_INET6)
            socketAddress.sin6_addr = address6
            return lookupName(&socketAddress,
                              length: socklen_t(MemoryLayout<sockaddr_in6>.size))
        }

        return nil
    }

    static func hostNameAsync(for address: String) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            queue.async {
                continuation.resume(returning: HostNameResolver.hostName(for: address))
            }
        }
    }

    /// True for IPv4/IPv6 literals worth a PTR query. Hostnames, service names
    /// and wildcard listen addresses are skipped.
    static func isResolvableAddress(_ address: String) -> Bool {
        guard let host = hostPart(of: address), !isUnspecified(host) else { return false }
        var address4 = in_addr()
        if inet_pton(AF_INET, host, &address4) == 1 { return true }
        var address6 = in6_addr()
        return inet_pton(AF_INET6, host, &address6) == 1
    }

    static func isIPv6Address(_ address: String) -> Bool {
        guard let host = hostPart(of: address) else { return false }
        var value = in6_addr()
        return inet_pton(AF_INET6, host, &value) == 1
    }

    /// Strips IPv6 brackets and a `%zone` suffix. The zone is intentionally
    /// dropped: PTR records for link-local addresses effectively do not exist.
    private static func hostPart(of address: String) -> String? {
        var host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        host = host.split(separator: "%", maxSplits: 1,
                          omittingEmptySubsequences: false)
            .first.map(String.init) ?? host
        return host.isEmpty ? nil : host
    }

    private static func isUnspecified(_ host: String) -> Bool {
        host == "0.0.0.0" || host == "::" || host == "*"
    }

    private static func lookupName<T>(_ storage: inout T, length: socklen_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getnameinfo(socketAddress, length,
                            &buffer, socklen_t(buffer.count),
                            nil, 0, NI_NAMEREQD)
            }
        }
        guard result == 0 else { return nil }
        let name = String(cString: buffer)
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        return trimmed.isEmpty ? nil : trimmed
    }
}
