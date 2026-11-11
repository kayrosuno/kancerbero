import Foundation
import DiskArbitration

/// Use only a disposable image named KancerberoOperationTest. Arguments are
/// the filesystem BSD identifier and its whole-disk BSD identifier.
@main enum DiskOperationIntegrationTests {
    static func main() async throws {
        guard CommandLine.arguments.count == 3,
              let session = DASessionCreate(nil),
              let disk = DADiskCreateFromBSDName(nil, session, CommandLine.arguments[1]),
              let description = DADiskCopyDescription(disk) as? [String: Any],
              description[kDADiskDescriptionVolumeNameKey as String] as? String == "KancerberoOperationTest",
              let physical = DADiskCreateFromBSDName(nil, session, CommandLine.arguments[2]),
              let physicalDescription = DADiskCopyDescription(physical) as? [String: Any],
              physicalDescription[kDADiskDescriptionMediaWholeKey as String] as? Bool == true else {
            fatalError("Provide the volume and whole-disk IDs of the disposable KancerberoOperationTest image.")
        }
        func item(_ id: String, _ kind: KBDiskItemKind, children: [KBDiskItem] = []) -> KBDiskItem {
            KBDiskItem(kind: kind, name: id, deviceIdentifier: id, content: nil,
                fileSystem: "apfs", mountPoint: nil, sizeBytes: 0, usedBytes: nil,
                freeBytes: nil, availableBytes: nil, volumeUUID: nil, mediaUUID: nil,
                volumeGroupUUID: nil, roles: [], isInternal: false, isRemovable: true,
                isWritable: true, isEncrypted: false, deviceModel: nil, deviceProtocol: nil,
                busName: nil, parentID: nil, children: children)
        }
        // A minimal inventory fixture keeps the real IOService resolution
        // test independent of the C collector and works with HFS+ and APFS.
        let volumeID = CommandLine.arguments[1]
        let wholeID = CommandLine.arguments[2]
        let fixture = KBDiskInventorySnapshot(items: [item(wholeID, .physicalDisk,
            children: [item(volumeID, .apfsVolume)])], generatedAt: Date(), error: nil, source: "integration")
        let resolved = DiskOperationService.ejectDisks(in: fixture)
        precondition(resolved[volumeID] == wholeID && resolved[wholeID] == wholeID,
            "Volume eject must resolve the physical disk, including synthetic APFS disks")
        let service = DiskOperationService()
        try await service.execute(.init(action: .mount, device: CommandLine.arguments[1]))
        precondition(FileManager.default.fileExists(atPath: "/Volumes/KancerberoOperationTest"))
        try await service.execute(.init(action: .unmount, device: CommandLine.arguments[1]))
        precondition(!FileManager.default.fileExists(atPath: "/Volumes/KancerberoOperationTest"))
        try await KBDiskOperationRunner.run([
            .init(action: .unmount, device: CommandLine.arguments[2]),
            .init(action: .eject, device: CommandLine.arguments[2])], executor: service)
        print("Disk Arbitration image integration: mount, unmount and eject passed")
    }
}
