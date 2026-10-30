import Foundation
import KancerberoCore

/// Turns a selected bundle plus its checked leftovers into trash operations.
/// User-writable paths are moved with `FileManager.trashItem`; system paths are
/// batched to the root daemon. User LaunchAgents are unloaded before moving.
enum TrashCoordinator {
    static func items(bundle: KBAppBundle, leftovers: [KBLeftover]) -> [KBTrashItem] {
        var items: [KBTrashItem] = []
        if !bundle.isProtected {
            items.append(KBTrashItem(path: bundle.path,
                                     kind: bundle.kind.rawValue,
                                     bundleIdentifier: bundle.bundleIdentifier))
        }
        for leftover in leftovers {
            let kind: String
            switch leftover.kind {
            case .launchAgent: kind = "launchAgent"
            case .launchDaemon: kind = "launchDaemon"
            default: kind = "file"
            }
            items.append(KBTrashItem(path: leftover.path,
                                     kind: kind,
                                     bundleIdentifier: bundle.bundleIdentifier))
        }
        return items
    }

    static func trash(items: [KBTrashItem],
                      daemon: (@Sendable ([KBTrashItem]) throws -> [KBTrashResult])?) async
        -> [KBTrashResult] {
        let home = KBPathPolicy.normalized(NSHomeDirectory())
        var results: [KBTrashResult] = []
        var privileged: [KBTrashItem] = []

        for item in items {
            let path = KBPathPolicy.normalized(item.path)
            let userOwned = path.hasPrefix(home + "/") || path.hasPrefix("/Users/Shared/")
            let writable = FileManager.default.isWritableFile(atPath: path)
            if userOwned, writable {
                results.append(await trashLocally(item))
            } else {
                privileged.append(item)
            }
        }

        guard !privileged.isEmpty else { return results }
        guard let daemon else {
            results += privileged.map {
                KBTrashResult(path: $0.path, ok: false, code: "daemon",
                              message: "the root daemon is required")
            }
            return results
        }

        var start = 0
        while start < privileged.count {
            let end = min(start + 32, privileged.count)
            let chunk = Array(privileged[start..<end])
            do {
                let batch = try await Task.detached(priority: .userInitiated) {
                    try daemon(chunk)
                }.value
                results += batch
            } catch {
                results += chunk.map {
                    KBTrashResult(path: $0.path, ok: false, code: "daemon",
                                  message: error.localizedDescription)
                }
            }
            start = end
        }
        return results
    }

    private static func trashLocally(_ item: KBTrashItem) async -> KBTrashResult {
        await Task.detached(priority: .userInitiated) {
            if item.kind == "launchAgent" {
                unloadAgent(at: item.path)
            }
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(
                    at: URL(fileURLWithPath: item.path),
                    resultingItemURL: &resulting
                )
                return KBTrashResult(path: item.path,
                                     trashedPath: (resulting as URL?)?.path,
                                     ok: true)
            } catch {
                return KBTrashResult(path: item.path, ok: false,
                                     message: error.localizedDescription)
            }
        }.value
    }

    private static func unloadAgent(at path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let label = plist["Label"] as? String,
              !label.isEmpty else {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
