import Foundation

public enum KBCollectionError: Error, LocalizedError, Sendable {
    case unavailable(String)
    case syscall(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .syscall(let name, let code):
            return "\(name) failed (errno \(code))"
        }
    }
}

public enum ProcessCollector {
    public static func path(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let result = kb_process_path(pid, &buffer, buffer.count)
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    public static func snapshot() throws -> [KBProcessInfo] {
        var pointer: UnsafeMutablePointer<kb_process>?
        var count = 0
        let result = kb_process_list(&pointer, &count)
        guard result == 0, let base = pointer else {
            throw KBCollectionError.unavailable("proc_listallpids failed")
        }
        defer { kb_process_list_free(base) }

        var items: [KBProcessInfo] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let raw = base[index]
            items.append(KBProcessInfo(
                pid: raw.pid,
                ppid: raw.ppid,
                uid: raw.uid,
                startTimeUS: raw.start_time_us,
                name: KBInterop.string(raw.name),
                path: KBInterop.string(raw.path)
            ))
        }
        return items.sorted { $0.pid < $1.pid }
    }
}
