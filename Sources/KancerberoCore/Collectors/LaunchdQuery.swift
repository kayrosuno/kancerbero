import Foundation

public struct KBRawLaunchdJob: Sendable {
    public var label: String
    public var pid: Int32
    public var lastExitStatus: Int32
    public var program: String
    public var arguments: String
    public var onDemand: Bool
}

/// Structured job list from launchd via `launch_msg("GetJobs")`.
/// The caller's launchd domain is used: the user's GUI domain in the app and
/// the system domain in the root daemon.
public enum LaunchdQuery {
    public static func jobs() throws -> [KBRawLaunchdJob] {
        var pointer: UnsafeMutablePointer<kb_launchd_job>?
        var count = 0
        guard kb_launchd_jobs(&pointer, &count) == 0, let base = pointer else {
            throw KBCollectionError.unavailable(String(cString: kb_launchd_last_error()))
        }
        defer { kb_launchd_jobs_free(base) }

        var items: [KBRawLaunchdJob] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let raw = base[index]
            items.append(KBRawLaunchdJob(
                label: KBInterop.string(raw.label),
                pid: raw.pid,
                lastExitStatus: raw.last_exit_status,
                program: KBInterop.string(raw.program),
                arguments: KBInterop.string(raw.arguments),
                onDemand: raw.on_demand != 0
            ))
        }
        return items
    }
}
