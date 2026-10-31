import Foundation
import KancerberoCore

/// Turns a selected bundle plus its checked leftovers into trash operations.
/// User-writable paths are moved with `FileManager.trashItem`; system paths are
/// batched to the root daemon. A local move that is refused by permissions
/// (for example TCC-protected app containers) is retried through the daemon,
/// mirroring AppCleaner's local-then-privileged fallback. User LaunchAgents are
/// unloaded before moving.
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
        var results: [Int: KBTrashResult] = [:]
        var pending: [(item: KBTrashItem, index: Int)] = []

        for (index, item) in items.enumerated() {
            let path = KBPathPolicy.normalized(item.path)
            guard !KBPathPolicy.requiresPrivilege(path, home: home) else {
                pending.append((item, index))
                continue
            }
            let outcome = await trashLocally(item)
            results[index] = outcome.result
            if !outcome.result.ok, outcome.permissionDenied {
                // The user owns the item but macOS (TCC/App Data) or an ACL
                // refused the move: root may be allowed to do it.
                pending.append((item, index))
            }
        }

        guard !pending.isEmpty else {
            return items.indices.compactMap { results[$0] }
        }
        guard let daemon else {
            for (item, index) in pending where results[index] == nil {
                results[index] = KBTrashResult(path: item.path, ok: false,
                                               code: "daemon",
                                               message: "the root daemon is required")
            }
            return items.indices.compactMap { results[$0] }
        }

        var indexByPath: [String: Int] = [:]
        for entry in pending {
            indexByPath[entry.item.path] = entry.index
        }
        var delivered = Set<String>()

        var start = 0
        while start < pending.count {
            let end = min(start + 32, pending.count)
            let chunk = pending[start..<end].map(\.item)
            do {
                let batch = try await Task.detached(priority: .userInitiated) {
                    try daemon(chunk)
                }.value
                for result in batch {
                    guard let index = indexByPath[result.path] else { continue }
                    if !result.ok,
                       results[index]?.code == KBTrashError.permissionCode {
                        // Keep the permission code from the local attempt: an
                        // older daemon does not tag its own denial, and the UI
                        // needs it to offer Full Disk Access guidance.
                        results[index] = KBTrashResult(
                            path: result.path,
                            trashedPath: result.trashedPath,
                            ok: false,
                            code: KBTrashError.permissionCode,
                            message: result.message ?? results[index]?.message
                        )
                    } else {
                        results[index] = result
                    }
                    delivered.insert(result.path)
                }
            } catch {
                for item in chunk {
                    guard let index = indexByPath[item.path] else { continue }
                    delivered.insert(item.path)
                    // Keep the local permission failure: it is the actionable
                    // cause when the helper could not retry the item.
                    if results[index]?.code == KBTrashError.permissionCode {
                        continue
                    }
                    results[index] = KBTrashResult(path: item.path, ok: false,
                                                   code: "daemon",
                                                   message: error.localizedDescription)
                }
            }
            start = end
        }

        for (path, index) in indexByPath where !delivered.contains(path) {
            // Keep the local permission failure if there is one: it is more
            // informative than a generic missing-daemon-result message.
            if results[index]?.code == KBTrashError.permissionCode {
                continue
            }
            results[index] = KBTrashResult(path: path, ok: false, code: "daemon",
                                           message: "no result from the daemon")
        }
        return items.indices.compactMap { results[$0] }
    }

    private struct LocalTrashOutcome: Sendable {
        let result: KBTrashResult
        let permissionDenied: Bool
    }

    private static func trashLocally(_ item: KBTrashItem) async -> LocalTrashOutcome {
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
                return LocalTrashOutcome(
                    result: KBTrashResult(path: item.path,
                                          trashedPath: (resulting as URL?)?.path,
                                          ok: true),
                    permissionDenied: false
                )
            } catch {
                let denied = KBTrashError.isPermissionDenied(error)
                return LocalTrashOutcome(
                    result: KBTrashResult(path: item.path, ok: false,
                                          code: denied ? KBTrashError.permissionCode : nil,
                                          message: error.localizedDescription),
                    permissionDenied: denied
                )
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
