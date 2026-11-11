import Foundation

public enum KBDiskAction: String, CaseIterable, Sendable {
    case mount = "Mount", unmount = "Unmount", eject = "Eject"
}

public struct KBDiskOperationIdentity: Equatable, Sendable {
    private let kind: KBDiskItemKind
    private let volumeUUID: String?
    private let mediaUUID: String?
    private let parentID: String?
    private let size: UInt64

    public init(_ item: KBDiskItem) {
        kind = item.kind; volumeUUID = item.volumeUUID; mediaUUID = item.mediaUUID
        parentID = item.parentID; size = item.sizeBytes
    }
}

public enum KBDiskOperationTarget: Sendable {
    case disk(String, identity: KBDiskOperationIdentity? = nil)
    case filesystem(KBFilesystem)
}

public struct KBDiskOperationStep: Equatable, Sendable {
    public let action: KBDiskAction
    public let device: String
    public let network: Bool
    public init(action: KBDiskAction, device: String, network: Bool = false) {
        self.action = action; self.device = device; self.network = network
    }
}

public struct KBDiskOperationPolicy: Sendable {
    public let inventory: KBDiskInventorySnapshot
    public let filesystems: [KBFilesystem]
    public let homePath: String
    /// Public Disk Arbitration metadata, keyed by inventory ID. Only unique,
    /// ejectable whole disks whose inventory ancestry agrees are included.
    public let ejectDisks: [String: String]

    public init(inventory: KBDiskInventorySnapshot, filesystems: [KBFilesystem],
                homePath: String, ejectDisks: [String: String]) {
        self.inventory = inventory; self.filesystems = filesystems
        self.homePath = homePath; self.ejectDisks = ejectDisks
    }

    private func contains(_ mount: String, path: String) -> Bool {
        path == mount || path.hasPrefix(mount == "/" ? "/" : mount + "/")
    }

    private var protectedIDs: Set<String> {
        let all = inventory.allItems
        let root = all.filter { $0.mountPoint == "/" }
        let bootGroups = Set(root.compactMap(\.volumeGroupUUID))
        // A sealed root snapshot can be the only mounted root entry. Follow
        // ancestry to recover its System/Data group and active auxiliaries.
        let rootDevices = filesystems.filter { $0.mountPoint == "/" }
            .map { $0.filesystem.replacingOccurrences(of: "/dev/", with: "") }
        let bootContainers = all.filter { item in
            item.kind == .apfsContainer && (root.contains { item.item(withID: $0.id) != nil }
                || item.children.contains { child in
                    rootDevices.contains { $0 == child.id || $0.hasPrefix(child.id + "s") }
                })
        }
        let bootVolumes = bootContainers.flatMap { $0.children }
        let groups = bootGroups.union(bootVolumes.filter {
            $0.roles.contains { $0.lowercased() == "system" }
        }.compactMap(\.volumeGroupUUID))
        let homeMount = filesystems.filter { contains($0.mountPoint, path: homePath) }
            .max { $0.mountPoint.count < $1.mountPoint.count }?.mountPoint
        var ids = Set(all.filter { item in
            item.mountPoint == "/" || (homeMount != nil && item.mountPoint == homeMount)
                || (item.volumeGroupUUID.map { groups.contains($0) } ?? false)
                || (bootVolumes.contains { $0.id == item.id } && item.roles.contains {
                    ["preboot", "recovery", "vm", "system", "data"].contains($0.lowercased())
                })
        }.map(\.id))
        // Fail closed if the root/home mount is missing from the volume view.
        for fs in filesystems where fs.mountPoint == "/" || fs.mountPoint == homeMount {
            let bsd = fs.filesystem.replacingOccurrences(of: "/dev/", with: "")
            for item in all where bsd == item.id || bsd.hasPrefix(item.id + "s") {
                ids.insert(item.id)
            }
        }
        return ids
    }

    private func protected(_ item: KBDiskItem) -> Bool {
        let ids = protectedIDs
        return ids.contains(item.id) || item.children.contains { protected($0) }
    }

    public func steps(for action: KBDiskAction, target: KBDiskOperationTarget) -> [KBDiskOperationStep]? {
        let item: KBDiskItem
        switch target {
        case .filesystem(let requested):
            guard let fs = filesystems.first(where: { $0.id == requested.id }),
                  fs.filesystem == requested.filesystem, fs.type == requested.type else { return nil }
            if ["smbfs", "nfs"].contains(fs.type.lowercased()) {
                guard action == .unmount, fs.mountPoint != "/",
                      !contains(fs.mountPoint, path: homePath) else { return nil }
                return [.init(action: .unmount, device: fs.mountPoint, network: true)]
            }
            guard fs.filesystem.hasPrefix("/dev/"),
                  let local = inventory.allItems.first(where: { $0.mountPoint == fs.mountPoint }),
                  fs.filesystem == "/dev/" + local.id else { return nil }
            item = local
        case .disk(let id, let identity):
            guard let local = inventory.allItems.first(where: { $0.id == id }),
                  identity == nil || identity == KBDiskOperationIdentity(local) else { return nil }
            item = local
        }
        guard item.kind != .snapshot,
              item.kind != .partition || item.fileSystem != nil else { return nil }
        if action == .eject {
            guard let wholeID = ejectDisks[item.id],
                  let whole = inventory.allItems.first(where: { $0.id == wholeID }),
                  whole.kind == .physicalDisk, !protected(whole) else { return nil }
            let mounted = inventory.mountedVolumes.filter {
                $0.id != wholeID && whole.item(withID: $0.id) != nil
            }.sorted { ($0.mountPoint?.count ?? 0) > ($1.mountPoint?.count ?? 0) }
            return mounted.map { .init(action: .unmount, device: $0.id) }
                + [.init(action: .unmount, device: wholeID), .init(action: .eject, device: wholeID)]
        }
        if item.kind == .apfsContainer {
            let volumes = item.children.filter { $0.kind == .apfsVolume }
            if action == .unmount && protected(item) { return nil }
            let candidates = volumes.filter {
                !protected($0) && (action == .mount ? $0.mountPoint == nil : $0.mountPoint != nil)
                    && (action != .mount || !$0.roles.contains {
                        ["preboot", "recovery", "vm"].contains($0.lowercased())
                    })
            }
            return candidates.isEmpty ? nil : candidates.map { .init(action: action, device: $0.id) }
        }
        guard [.apfsVolume, .partition].contains(item.kind), item.fileSystem != nil,
              !protected(item), action == (item.mountPoint == nil ? .mount : .unmount) else { return nil }
        return [.init(action: action, device: item.id)]
    }
}

public protocol KBDiskOperationExecuting: Sendable {
    func execute(_ step: KBDiskOperationStep) async throws
}

public enum KBDiskOperationRunner {
    /// Stops on the first error: no rollback and, in particular, no eject
    /// after a failed unmount.
    public static func run(_ steps: [KBDiskOperationStep], executor: any KBDiskOperationExecuting) async throws {
        for step in steps { try await executor.execute(step) }
    }
}
