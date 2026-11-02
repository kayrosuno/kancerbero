import Foundation
import KancerberoCore
import KancerberoFilterContract

/// Visible text plus tooltip for an endpoint cell. The tooltip keeps the raw
/// endpoint so a resolved name never hides the address.
struct EndpointLabel {
    var text: String
    var help: String
}

extension KBEndpoint {
    func label(hostName: String?) -> EndpointLabel {
        guard let hostName, !hostName.isEmpty, hostName != address else {
            return EndpointLabel(text: display, help: display)
        }
        let text = port > 0 ? "\(hostName):\(port)" : hostName
        return EndpointLabel(text: text, help: "\(hostName) · \(display)")
    }
}

extension FilterEndpoint {
    /// Raw `address:port`, bracketing IPv6 literals when a port is shown.
    /// `display` is deliberately untouched: `destinationKey`/`destinationKeys`
    /// matching depends on its hostname preference.
    var rawDisplay: String {
        guard port > 0 else { return address }
        let host = address.hasPrefix("[") || !HostNameResolver.isIPv6Address(address)
            ? address
            : "[\(address)]"
        return "\(host):\(port)"
    }

    func label(hostName: String?) -> EndpointLabel {
        let raw = rawDisplay
        guard let hostName, !hostName.isEmpty, hostName != address else {
            return EndpointLabel(text: raw, help: raw)
        }
        let text = port > 0 ? "\(hostName):\(port)" : hostName
        return EndpointLabel(text: text, help: "\(hostName) · \(raw)")
    }
}
