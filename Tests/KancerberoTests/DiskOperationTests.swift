import Foundation

private actor Executor: KBDiskOperationExecuting {
    var calls: [KBDiskOperationStep] = []
    let fail: Bool
    init(fail: Bool) { self.fail = fail }
    func execute(_ step: KBDiskOperationStep) async throws {
        calls.append(step)
        if fail { throw NSError(domain: "busy", code: 1) }
    }
}

@main enum DiskOperationTests {
    static func item(_ id: String, _ kind: KBDiskItemKind, mount: String? = nil,
                     roles: [String] = [], group: String? = nil, fs: String? = "apfs",
                     children: [KBDiskItem] = []) -> KBDiskItem {
        KBDiskItem(kind: kind, name: id, deviceIdentifier: id, content: nil,
            fileSystem: fs, mountPoint: mount, sizeBytes: 100, usedBytes: nil,
            freeBytes: nil, availableBytes: nil, volumeUUID: id, mediaUUID: nil,
            volumeGroupUUID: group, roles: roles, isInternal: false, isRemovable: true,
            isWritable: true, isEncrypted: false, deviceModel: nil, deviceProtocol: nil,
            busName: nil, parentID: nil, children: children)
    }
    static func fs(_ device: String, _ mount: String, type: String = "apfs") -> KBFilesystem {
        KBFilesystem(filesystem: device, type: type, mountPoint: mount,
            sizeBytes: 100, usedBytes: 10, availableBytes: 90, inodeCount: 10, freeInodes: 9)
    }
    static func main() async throws {
        let root = item("disk1s1", .apfsVolume, mount: "/", roles: ["System"], group: "boot")
        let data = item("disk1s2", .apfsVolume, mount: "/System/Volumes/Data", roles: ["Data"], group: "boot")
        let auxiliary = item("disk1s3", .apfsVolume, mount: "/System/Volumes/Preboot", roles: ["Preboot"])
        let boot = item("disk0", .physicalDisk, children: [item("disk1", .apfsContainer, children: [root, data, auxiliary])])
        let mounted = item("disk3s1", .apfsVolume, mount: "/Volumes/Test")
        let unmounted = item("disk3s2", .apfsVolume)
        let preboot = item("disk3s3", .apfsVolume, roles: ["Preboot"])
        let snapshot = item("disk3s1s1", .snapshot, mount: "/Volumes/Snapshot")
        let container = item("disk3", .apfsContainer, children: [mounted, unmounted, preboot, snapshot])
        let external = item("disk2", .physicalDisk, children: [container, item("disk2s9", .partition, fs: nil)])
        let mounts = [fs("/dev/disk1s1", "/"), fs("/dev/disk1s2", "/System/Volumes/Data"), fs("/dev/disk3s1", "/Volumes/Test"), fs("server:/share", "/Volumes/NFS", type: "nfs"), fs("map", "/net", type: "autofs")]
        let inventory = KBDiskInventorySnapshot(items: [boot, external], generatedAt: Date(), error: nil, source: "test")
        let policy = KBDiskOperationPolicy(inventory: inventory, filesystems: mounts,
            homePath: "/System/Volumes/Data/Users/test", ejectDisks: ["disk2": "disk2", "disk3": "disk2", "disk3s1": "disk2", "disk0": "disk0", "disk2s9": "disk2"])
        func enabled(_ a: KBDiskAction, _ id: String) -> Bool { policy.steps(for: a, target: .disk(id)) != nil }
        precondition(!enabled(.mount, "disk2") && !enabled(.unmount, "disk2"))
        precondition(enabled(.mount, unmounted.id) && !enabled(.unmount, unmounted.id))
        precondition(enabled(.unmount, mounted.id) && !enabled(.mount, mounted.id))
        precondition(!enabled(.unmount, root.id) && !enabled(.unmount, data.id) && !enabled(.unmount, auxiliary.id))
        precondition(!enabled(.eject, "disk0") && !enabled(.unmount, "disk1"))
        precondition(!enabled(.unmount, snapshot.id) && !enabled(.mount, "disk2s9"))
        precondition(policy.steps(for: .mount, target: .disk(container.id)) == [.init(action: .mount, device: unmounted.id)])
        precondition(policy.steps(for: .unmount, target: .disk(container.id)) == [.init(action: .unmount, device: mounted.id)])
        precondition(policy.steps(for: .unmount, target: .filesystem(mounts[3])) == [.init(action: .unmount, device: "/Volumes/NFS", network: true)])
        precondition(policy.steps(for: .mount, target: .filesystem(mounts[3])) == nil)
        precondition(policy.steps(for: .unmount, target: .filesystem(mounts[4])) == nil)
        precondition(policy.steps(for: .unmount, target: .disk("missing")) == nil)
        let steps = policy.steps(for: .eject, target: .disk(mounted.id))!
        precondition(steps == [.init(action: .unmount, device: snapshot.id),
            .init(action: .unmount, device: mounted.id),
            .init(action: .unmount, device: "disk2"), .init(action: .eject, device: "disk2")])
        let failure = Executor(fail: true)
        do { try await KBDiskOperationRunner.run(steps, executor: failure); preconditionFailure() } catch {}
        let failedCalls = await failure.calls
        precondition(failedCalls.count == 1)
        let success = Executor(fail: false)
        try await KBDiskOperationRunner.run(steps, executor: success)
        let calls = await success.calls
        precondition(calls == steps)
        let sealedMounts = [fs("/dev/disk1s1s1", "/"), fs("/dev/disk1s2", "/System/Volumes/Data")]
        let sealedInventory = KBDiskInventorySnapshot(items: [item("disk0", .physicalDisk,
            children: [item("disk1", .apfsContainer, children: [
                item("disk1s1", .apfsVolume, roles: ["System"], group: "boot"), data, auxiliary])])],
            generatedAt: Date(), error: nil, source: "test")
        let sealed = KBDiskOperationPolicy(inventory: sealedInventory, filesystems: sealedMounts,
            homePath: "/Users/me", ejectDisks: [:])
        precondition(sealed.steps(for: .unmount, target: .disk(data.id)) == nil)
        precondition(sealed.steps(for: .unmount, target: .disk(auxiliary.id)) == nil)
        precondition(policy.steps(for: .eject, target: .disk("disk2s9")) == nil)
        let staleVolume = item(mounted.id, .partition, mount: mounted.mountPoint)
        precondition(policy.steps(for: .unmount,
            target: .disk(mounted.id, identity: .init(staleVolume))) == nil)
        precondition(policy.steps(for: .unmount,
            target: .disk(mounted.id, identity: .init(mounted))) != nil)
        let missing = KBDiskOperationPolicy(inventory: inventory, filesystems: mounts,
            homePath: "/Users/me", ejectDisks: [:])
        precondition(missing.steps(for: .eject, target: .disk(mounted.id)) == nil)
        let stale = fs("changed:/share", "/Volumes/NFS", type: "nfs")
        precondition(policy.steps(for: .unmount, target: .filesystem(stale)) == nil)
        let networkHome = KBDiskOperationPolicy(inventory: inventory, filesystems: mounts,
            homePath: "/Volumes/NFS/me", ejectDisks: [:])
        precondition(networkHome.steps(for: .unmount, target: .filesystem(mounts[3])) == nil)
        let home = KBDiskOperationPolicy(inventory: inventory, filesystems: mounts,
            homePath: "/Volumes/Test/Users/me", ejectDisks: [mounted.id: "disk2"])
        precondition(home.steps(for: .unmount, target: .disk(mounted.id)) == nil)
        precondition(home.steps(for: .eject, target: .disk(mounted.id)) == nil)
        print("Disk operations: policy and simulated executor checks passed")
    }
}
