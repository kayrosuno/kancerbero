import Foundation

public enum InterfaceCollector {
    public static func snapshot() throws -> [KBInterfaceInfo] {
        var pointer: UnsafeMutablePointer<kb_interface>?
        var count = 0
        let result = kb_interface_list(&pointer, &count)
        guard result == 0, let base = pointer else {
            throw KBCollectionError.unavailable("sysctl NET_RT_IFLIST2 failed")
        }
        defer { kb_interface_list_free(base) }

        var items: [KBInterfaceInfo] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let raw = base[index]
            items.append(KBInterfaceInfo(
                index: raw.index,
                name: KBInterop.string(raw.name),
                flags: raw.flags,
                type: raw.type,
                counters: KBCounters(rxBytes: raw.rx_bytes, txBytes: raw.tx_bytes,
                                     rxPackets: raw.rx_packets, txPackets: raw.tx_packets),
                rxErrors: raw.rx_errors,
                txErrors: raw.tx_errors,
                rxDrops: raw.rx_drops,
                collisions: raw.collisions,
                mtu: raw.mtu,
                baudrate: raw.baudrate
            ))
        }
        return items
    }
}
