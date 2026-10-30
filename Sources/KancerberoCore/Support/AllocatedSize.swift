import Foundation

public enum KBAllocatedSize {
    /// Allocated bytes of a file or directory tree. Symbolic links are not
    /// followed and hidden entries are ignored, matching Finder's accounting.
    /// The walk is cooperative: it checks `Task.isCancelled` periodically.
    public static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }
        if !isDirectory.boolValue {
            return singleFileSize(url, keys: keys)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        var visited = 0
        for case let item as URL in enumerator {
            visited += 1
            if visited % 256 == 0, Task.isCancelled {
                break
            }
            guard let values = try? item.resourceValues(forKeys: keys) else {
                continue
            }
            if values.isSymbolicLink == true || values.isRegularFile != true {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static func singleFileSize(_ url: URL, keys: Set<URLResourceKey>) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
