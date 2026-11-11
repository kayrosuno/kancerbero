import Foundation
import Darwin

/// Native mount-table statistics, without spawning df or walking /Volumes.
public enum FilesystemCollector {
    public static func snapshot() -> KBFilesystemSnapshot {
        var pointer: UnsafeMutablePointer<kb_filesystem>?
        var count = 0
        let result = kb_filesystem_list(&pointer, &count)
        guard result == 0 else {
            return KBFilesystemSnapshot(filesystems: [], generatedAt: Date(),
                                        error: "Mount table: \(message(result))")
        }
        defer { kb_filesystem_list_free(pointer) }

        let filesystems = (0..<count).map { index in
            let raw = pointer![index]
            var warnings: [String] = []
            if raw.stats_error != 0 {
                warnings.append("Cached statistics: \(message(raw.stats_error))")
            }
            if raw.used_space_error != 0 {
                warnings.append("Block-accounting fallback: \(message(raw.used_space_error))")
            }
            return KBFilesystem(
                filesystem: KBInterop.string(raw.filesystem),
                type: KBInterop.string(raw.file_system),
                mountPoint: KBInterop.string(raw.mount_point),
                sizeBytes: raw.size_bytes,
                usedBytes: raw.used_bytes,
                availableBytes: raw.available_bytes,
                inodeCount: raw.inode_count,
                freeInodes: raw.free_inodes,
                isReadOnly: raw.is_read_only != 0,
                isCached: raw.is_cached != 0,
                warning: warnings.isEmpty ? nil : warnings.joined(separator: "\n"))
        }
        return KBFilesystemSnapshot(filesystems: filesystems,
                                    generatedAt: Date(), error: nil)
    }

    private static func message(_ error: Int32) -> String {
        String(cString: strerror(error))
    }
}
