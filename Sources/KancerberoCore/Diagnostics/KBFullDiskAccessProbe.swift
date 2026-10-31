import Darwin
import Foundation

/// Best-effort Full Disk Access (FDA) check. macOS exposes no public API for
/// this permission, so probe a few locations that TCC protects with
/// `SystemPolicyAllFiles` by opening them read-only. No contents are read.
public enum KBFullDiskAccessStatus: String, Sendable {
    case granted
    case denied
    case unknown
}

public enum KBFullDiskAccessProbe {
    private static let candidates = [
        "Library/Safari/History.db",
        "Library/Safari/Bookmarks.plist",
        "Library/Messages/chat.db",
        "Library/Mail",
        "Library/Group Containers/group.com.apple.notes",
        "Library/Application Support/com.apple.TCC/TCC.db"
    ]

    public static func current(homeDirectory: String = NSHomeDirectory())
        -> KBFullDiskAccessStatus {
        let home = URL(fileURLWithPath: homeDirectory, isDirectory: true)
        var sawDenied = false

        for relativePath in candidates {
            let path = home.appendingPathComponent(relativePath).path
            switch probe(path) {
            case .readable:
                return .granted
            case .denied:
                sawDenied = true
            case .missing, .inaccessible:
                continue
            }
        }
        return sawDenied ? .denied : .unknown
    }

    private enum Outcome {
        case readable
        case denied
        case missing
        case inaccessible
    }

    private static func probe(_ path: String) -> Outcome {
        // Opening the path is enough to prove TCC access; a denial happens at
        // open(), before any bytes or directory entries are read.
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        if descriptor >= 0 {
            _ = close(descriptor)
            return .readable
        }

        let code = errno
        if code == ENOENT || code == ENOTDIR {
            return .missing
        }
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        return KBTrashError.isPermissionDenied(error) ? .denied : .inaccessible
    }
}
