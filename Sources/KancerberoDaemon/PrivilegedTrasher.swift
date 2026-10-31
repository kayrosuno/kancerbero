import Darwin
import Foundation
import KancerberoCore

/// Moves allow-listed paths to the requesting user's Trash while running as
/// root. Every path is revalidated here: the client's payload is advisory.
enum PrivilegedTrasher {
    static func trash(items: [KBTrashItem], peer: PeerIdentity) -> [KBTrashResult] {
        items.prefix(32).map { trashOne($0, peer: peer) }
    }

    // MARK: - One item

    private static func trashOne(_ item: KBTrashItem, peer: PeerIdentity) -> KBTrashResult {
        let original = item.path
        guard let canonical = canonicalPath(original) else {
            return failure(original, "invalid path")
        }
        guard KBPathPolicy.isAllowed(canonical, home: peer.home) else {
            return failure(original, "path is outside the allowed roots")
        }
        guard !KBPathPolicy.isProtected(canonical) else {
            return failure(original, "path is protected")
        }

        var info = stat()
        guard lstat(canonical, &info) == 0 else {
            return failure(original, "item not found", code: errnoCode())
        }

        if item.kind == "application" || item.kind == "widget" || item.kind == "plugin" {
            if let refusal = bundleRefusal(at: canonical) {
                return failure(original, refusal)
            }
        }

        if item.kind == "launchAgent" || item.kind == "launchDaemon" {
            if let label = launchdLabel(at: canonical) {
                let domain = item.kind == "launchDaemon" ? "system" : "gui/\(peer.uid)"
                bootout(domain: domain, label: label)
            } else {
                return failure(original, "launchd label not found")
            }
        }

        let immutable = UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)
        if info.st_flags & immutable != 0 {
            _ = chflags(canonical, info.st_flags & ~immutable)
        }

        guard let trash = trashDirectory(for: peer) else {
            return failure(original, "cannot prepare the Trash")
        }
        guard let destination = uniqueDestination(in: trash,
                                                  name: (canonical as NSString).lastPathComponent) else {
            return failure(original, "no free name in the Trash")
        }

        do {
            try FileManager.default.moveItem(atPath: canonical, toPath: destination)
        } catch {
            let code = KBTrashError.isPermissionDenied(error)
                ? KBTrashError.permissionCode : nil
            return failure(original, error.localizedDescription, code: code)
        }

        chownTree(at: destination, uid: peer.uid, gid: peer.gid)
        return KBTrashResult(path: original, trashedPath: destination, ok: true)
    }

    // MARK: - Validation

    /// Resolves the parent directory (rejecting symlinked parents) and keeps the
    /// final component verbatim, so moving a symlink moves the link itself.
    private static func canonicalPath(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        let parent = url.deletingLastPathComponent().path
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(parent, &resolved) != nil else { return nil }
        let realParent = String(cString: resolved)
        return realParent == "/" ? "/" + name : realParent + "/" + name
    }

    private static func bundleRefusal(at path: String) -> String? {
        if path.contains("/Kancerbero.app/") {
            return "Kancerbero itself is protected"
        }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved != path {
            // Application bundles must not be symlinks into SIP-protected places.
            return "symlinked bundles are protected"
        }
        // Apple apps under /Applications are removable with administrator
        // rights; only SIP paths (/System) are refused by KBPathPolicy.
        return nil
    }

    private static func launchdLabel(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let label = plist["Label"] as? String else {
            return nil
        }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !label.isEmpty,
              label.unicodeScalars.allSatisfy(allowed.contains) else {
            return nil
        }
        return label
    }

    private static func bootout(domain: String, label: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "\(domain)/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Destination

    private static func trashDirectory(for peer: PeerIdentity) -> String? {
        let trash = peer.home + "/.Trash"
        let manager = FileManager.default
        if !manager.fileExists(atPath: trash) {
            guard (try? manager.createDirectory(
                atPath: trash, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )) != nil else {
                return nil
            }
        }
        _ = chown(trash, peer.uid, peer.gid)
        return trash
    }

    private static func uniqueDestination(in directory: String, name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 1...999 {
            let candidate: String
            if index == 1 {
                candidate = name
            } else if ext.isEmpty {
                candidate = "\(base) \(index)"
            } else {
                candidate = "\(base) \(index).\(ext)"
            }
            let path = directory + "/" + candidate
            if !FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func chownTree(at path: String, uid: uid_t, gid: gid_t) {
        _ = lchown(path, uid, gid)
        addUserAccess(at: path)
        guard let enumerator = FileManager.default.enumerator(atPath: path) else {
            return
        }
        for case let relative as String in enumerator {
            let full = path + "/" + relative
            _ = lchown(full, uid, gid)
            addUserAccess(at: full)
        }
    }

    private static func addUserAccess(at path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        let kind = info.st_mode & S_IFMT
        if kind == S_IFDIR {
            _ = chmod(path, info.st_mode | S_IWUSR | S_IXUSR)
        } else if kind == S_IFREG {
            _ = chmod(path, info.st_mode & ~(S_ISUID | S_ISGID))
        }
    }

    // MARK: - Results

    private static func failure(_ path: String, _ message: String,
                                code: String? = nil) -> KBTrashResult {
        KBTrashResult(path: path, ok: false, code: code, message: message)
    }

    private static func errnoCode() -> String {
        String(cString: strerror(errno))
    }
}
