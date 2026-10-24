import Darwin
import Foundation

public enum SocketCollector {
    public static func snapshot(pid: Int32) throws -> [KBSocketInfo] {
        var pointer: UnsafeMutablePointer<kb_socket>?
        var count = 0
        let result = kb_socket_list(pid, &pointer, &count)
        guard result == 0, let base = pointer else {
            throw KBCollectionError.unavailable("proc_pidfdinfo(PROC_PIDFDSOCKETINFO) failed for pid \(pid)")
        }
        defer { kb_socket_list_free(base) }

        var items: [KBSocketInfo] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let raw = base[index]
            let local = KBInterop.endpoint(
                family: UInt8(truncatingIfNeeded: raw.family),
                address: KBInterop.bytes(raw.local_addr, count: 16),
                port: raw.local_port,
                scope: raw.local_scope
            )
            let remote = KBInterop.endpoint(
                family: UInt8(truncatingIfNeeded: raw.family),
                address: KBInterop.bytes(raw.remote_addr, count: 16),
                port: raw.remote_port,
                scope: raw.remote_scope
            )
            items.append(KBSocketInfo(
                fd: raw.fd,
                family: raw.family,
                protocolNumber: raw.protocol,
                type: raw.type,
                state: raw.state,
                local: local,
                remote: remote
            ))
        }
        return items
    }
}

public enum OpenFileCollector {
    public static func snapshot(pid: Int32) throws -> [KBOpenFileInfo] {
        var pointer: UnsafeMutablePointer<kb_open_file>?
        var count = 0
        let result = kb_open_file_list(pid, &pointer, &count)
        guard result == 0, let base = pointer else {
            throw KBCollectionError.unavailable("proc_pidinfo(PROC_PIDLISTFDS) failed for pid \(pid)")
        }
        defer { kb_open_file_list_free(base) }

        var items: [KBOpenFileInfo] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let raw = base[index]
            items.append(KBOpenFileInfo(
                fd: raw.fd,
                type: raw.type,
                size: raw.size,
                path: KBInterop.string(raw.path)
            ))
        }
        return items.sorted { $0.fd < $1.fd }
    }
}
