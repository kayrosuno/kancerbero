import Foundation
import Network
import NetworkExtension
import KancerberoFilterContract

enum FilterFlowEndpoints {
    struct Description {
        var local: FilterEndpoint?
        var remote: FilterEndpoint?
        var transport: String
        var isUDP: Bool
    }

    static func describe(_ flow: NEFilterFlow) -> Description {
        guard let socket = flow as? NEFilterSocketFlow else {
            return Description(local: nil, remote: nil, transport: "other", isUDP: false)
        }

        let isUDP = socket.socketProtocol == IPPROTO_UDP
        let isIPv6 = socket.socketFamily == AF_INET6
        let transport = (isUDP ? "udp" : "tcp") + (isIPv6 ? "6" : "4")

        var local: FilterEndpoint?
        var remote: FilterEndpoint?
        if #available(macOS 15.0, *) {
            local = endpoint(socket.localFlowEndpoint)
            remote = endpoint(socket.remoteFlowEndpoint)
        }
        if let hostname = socket.remoteHostname, !hostname.isEmpty {
            if var current = remote {
                current.hostname = hostname
                remote = current
            } else {
                remote = FilterEndpoint(address: hostname, port: 0, hostname: hostname)
            }
        }

        return Description(local: local, remote: remote, transport: transport, isUDP: isUDP)
    }

    private static func endpoint(_ value: NWEndpoint?) -> FilterEndpoint? {
        guard let value else { return nil }
        switch value {
        case .hostPort(let host, let port):
            let address: String
            switch host {
            case .name(let name, _):
                address = name
            case .ipv4(let address4):
                address = String(describing: address4)
            case .ipv6(let address6):
                address = String(describing: address6)
            @unknown default:
                address = String(describing: host)
            }
            return FilterEndpoint(address: address, port: port.rawValue)

        case .service(let name, _, _, _):
            return FilterEndpoint(address: name, port: 0)

        default:
            return nil
        }
    }
}
