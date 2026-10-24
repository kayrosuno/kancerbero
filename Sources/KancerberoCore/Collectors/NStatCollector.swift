import Foundation

public final class NStatCollector: @unchecked Sendable {
    private var started = false

    public init() {}

    deinit {
        if started {
            kb_nstat_close()
        }
    }

    public static func availability() -> (available: Bool, message: String) {
        let result = kb_nstat_open()
        if result == 0 {
            return (true, "")
        }
        return (false, String(cString: kb_nstat_last_error()))
    }

    public func start() throws {
        guard !started else { return }
        if kb_nstat_open() != 0 {
            throw KBCollectionError.unavailable(String(cString: kb_nstat_last_error()))
        }
        if kb_nstat_start(1, 1) != 0 {
            throw KBCollectionError.unavailable(String(cString: kb_nstat_last_error()))
        }
        started = true
    }

    /// Returns true when the poll completed or produced partial data.
    public func poll(timeoutMilliseconds: Int32 = 250) -> Bool {
        guard started else { return false }
        // 1 means some sources did not answer before the deadline; the
        // snapshot is still usable and contains the latest known values.
        return kb_nstat_poll(timeoutMilliseconds) >= 0
    }

    public func snapshot() -> [KBNStatSource] {
        guard started else { return [] }
        var pointer: UnsafeMutablePointer<kb_nstat_source>?
        var count = 0
        guard kb_nstat_snapshot(&pointer, &count) == 0, let base = pointer else {
            return []
        }
        defer { kb_nstat_snapshot_free(base) }

        var items: [KBNStatSource] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let raw = base[index]
            let local = KBInterop.endpoint(
                family: raw.local_family,
                address: KBInterop.bytes(raw.local_addr, count: 16),
                port: raw.local_port,
                scope: raw.local_scope
            )
            let remote = KBInterop.endpoint(
                family: raw.remote_family,
                address: KBInterop.bytes(raw.remote_addr, count: 16),
                port: raw.remote_port,
                scope: raw.remote_scope
            )
            items.append(KBNStatSource(
                pid: raw.pid,
                epid: raw.epid,
                processName: KBInterop.string(raw.process_name),
                provider: KBInterop.string(raw.provider),
                tcpState: KBInterop.string(raw.tcp_state),
                interfaceName: KBInterop.string(raw.if_name),
                interfaceType: KBInterop.string(raw.if_type),
                uuid: KBInterop.string(raw.uuid),
                local: local,
                remote: remote,
                counters: KBCounters(rxBytes: raw.rx_bytes, txBytes: raw.tx_bytes,
                                     rxPackets: raw.rx_packets, txPackets: raw.tx_packets),
                rxWiFi: raw.rx_wifi,
                txWiFi: raw.tx_wifi,
                rxWired: raw.rx_wired,
                txWired: raw.tx_wired,
                rxCellular: raw.rx_cellular,
                txCellular: raw.tx_cellular,
                rxDuplicates: raw.rx_dupe,
                rxOutOfOrder: raw.rx_ooo,
                txRetransmits: raw.tx_retx,
                rtt: raw.rtt,
                startNanoseconds: raw.start_ns
            ))
        }
        return items
    }

    public func stop() {
        guard started else { return }
        kb_nstat_close()
        started = false
    }
}
