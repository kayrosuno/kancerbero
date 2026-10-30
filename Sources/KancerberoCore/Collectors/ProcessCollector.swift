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
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        if info.denom == 0 {
            info.numer = 1
            info.denom = 1
        }
        return info
    }()

    /// Mach absolute ticks -> nanoseconds. Cached timebase; on Apple silicon it
    /// is 125/3, on Intel usually 1/1, so never assume ticks are nanoseconds.
    public static func nanoseconds(fromTicks ticks: UInt64) -> UInt64 {
        let numer = UInt64(timebase.numer)
        let denom = UInt64(timebase.denom)
        return (ticks / denom) * numer + ((ticks % denom) * numer) / denom
    }

    public static func path(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let result = kb_process_path(pid, &buffer, buffer.count)
        guard result > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
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
            items.append(info(from: base[index]))
        }
        return items.sorted { $0.pid < $1.pid }
    }

    /// Identity-only snapshot from KERN_PROC_ALL. It lists every process,
    /// including ones whose task counters are unreadable without the root
    /// daemon, but never blocks on per-PID syscalls.
    public static func metadataSnapshot() -> [KBProcessInfo] {
        var pointer: UnsafeMutablePointer<kb_process>?
        var count = 0
        guard kb_process_metadata_list(&pointer, &count) == 0,
              let base = pointer else {
            return []
        }
        defer { kb_process_list_free(base) }
        var items: [KBProcessInfo] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            items.append(info(from: base[index]))
        }
        return items.sorted { $0.pid < $1.pid }
    }

    public static func info(from raw: kb_process) -> KBProcessInfo {
        let hasTaskInfo = raw.has_task_info != 0
        let runningThreads = Int(raw.running_threads)
        let usage: KBProcessUsage? = hasTaskInfo
            ? KBProcessUsage(
                cpuTimeNanoseconds: nanoseconds(
                    fromTicks: raw.cpu_user_ticks + raw.cpu_system_ticks),
                residentBytes: raw.resident_bytes,
                virtualBytes: raw.virtual_bytes,
                threads: Int(raw.threads),
                runningThreads: runningThreads,
                priority: raw.priority,
                energyNanojoules: raw.energy_nj,
                interruptWakeups: raw.interrupt_wkups,
                packageIdleWakeups: raw.pkg_idle_wkups)
            : nil
        let state: KBProcessState?
        if hasTaskInfo {
            state = KBProcessState.from(status: raw.status,
                                        runningThreads: runningThreads)
        } else {
            // pbi_status is not a reliable run state on macOS 27, but
            // stopped/zombie/idle still carry useful information.
            switch raw.status {
            case 1: state = .idle
            case 4: state = .stopped
            case 5: state = .zombie
            default: state = nil
            }
        }
        return KBProcessInfo(
            pid: raw.pid,
            ppid: raw.ppid,
            uid: raw.uid,
            startTimeUS: raw.start_time_us,
            name: KBInterop.string(raw.name),
            path: KBInterop.string(raw.path),
            state: state,
            nice: raw.nice,
            usage: usage
        )
    }
}
