import Foundation

/// Disk/volume inventory from public system APIs.
///
/// IOKit provides the IORegistry hierarchy (physical medium -> partition ->
/// APFS container -> APFS volume) and the APFS metadata. DiskArbitration adds
/// volume names, mount points, UUIDs and device metadata. `getmntinfo` and
/// `getattrlist(ATTR_VOL_*)` provide mounted capacities, including per-volume
/// APFS used space. No external process is executed.
public final class DiskInventoryCollector: @unchecked Sendable {
    public init() {}

    public func snapshot() -> KBDiskInventorySnapshot {
        var pointer: UnsafeMutablePointer<kb_disk_media>?
        var count = 0
        let result = kb_disk_media_list(&pointer, &count)
        guard result == 0, let base = pointer else {
            return KBDiskInventorySnapshot(
                items: [],
                generatedAt: Date(),
                error: "IOKit/DiskArbitration inventory failed",
                source: "iokit+diskarbitration"
            )
        }
        defer { kb_disk_media_list_free(base) }

        var templates: [String: KBDiskItem] = [:]
        var parents: [String: String] = [:]
        var childrenByID: [String: [String]] = [:]
        var roots: [String] = []
        templates.reserveCapacity(count)

        for index in 0..<count {
            let raw = base[index]
            let identifier = KBInterop.string(raw.bsd_name)
            guard !identifier.isEmpty else { continue }

            let roles = KBInterop.string(raw.roles)
                .split(separator: ",")
                .map(String.init)
                .filter { !$0.isEmpty }

            let kind = kind(for: raw, roles: roles)
            let rawName = nonEmpty(KBInterop.string(raw.volume_name))
                ?? nonEmpty(KBInterop.string(raw.media_name))
                ?? identifier
            let name = kind == .apfsContainer
                && (rawName == "AppleAPFSMedia" || rawName.isEmpty)
                ? "APFS Container"
                : rawName
            let fileSystem = kind == .apfsContainer
                ? "APFS"
                : nonEmpty(KBInterop.string(raw.file_system))
            let hasCapacity = raw.is_mounted != 0 || raw.is_apfs_container != 0

            let item = KBDiskItem(
                kind: kind,
                name: name,
                deviceIdentifier: identifier,
                content: nonEmpty(KBInterop.string(raw.content)),
                fileSystem: fileSystem,
                mountPoint: nonEmpty(KBInterop.string(raw.mount_point)),
                sizeBytes: raw.size_bytes != 0 ? raw.size_bytes : raw.volume_size_bytes,
                usedBytes: hasCapacity ? raw.used_bytes : nil,
                freeBytes: hasCapacity ? raw.free_bytes : nil,
                availableBytes: raw.is_mounted != 0 ? raw.available_bytes : nil,
                volumeUUID: nonEmpty(KBInterop.string(raw.volume_uuid)),
                mediaUUID: nonEmpty(KBInterop.string(raw.media_uuid)),
                volumeGroupUUID: nonEmpty(KBInterop.string(raw.vol_group_uuid)),
                roles: roles,
                isInternal: raw.is_internal != 0,
                isRemovable: raw.is_removable != 0,
                isWritable: raw.is_writable != 0,
                isEncrypted: raw.is_encrypted != 0,
                deviceModel: nonEmpty(KBInterop.string(raw.device_model)),
                deviceProtocol: nonEmpty(KBInterop.string(raw.device_protocol)),
                busName: nonEmpty(KBInterop.string(raw.bus_name)),
                parentID: nonEmpty(KBInterop.string(raw.parent_bsd_name)),
                children: []
            )

            templates[identifier] = item
            let parent = KBInterop.string(raw.parent_bsd_name)
            if !parent.isEmpty && parent != identifier {
                parents[identifier] = parent
            }
        }

        for identifier in templates.keys {
            if let parent = parents[identifier], templates[parent] != nil {
                childrenByID[parent, default: []].append(identifier)
            } else {
                roots.append(identifier)
            }
        }

        func build(_ identifier: String, depth: Int) -> KBDiskItem? {
            guard depth < 64, let template = templates[identifier] else { return nil }
            let childIDs = (childrenByID[identifier] ?? []).sorted { lhs, rhs in
                guard let left = templates[lhs], let right = templates[rhs] else {
                    return lhs < rhs
                }
                let leftRank = kindRank(left.kind)
                let rightRank = kindRank(right.kind)
                if leftRank != rightRank { return leftRank < rightRank }
                if left.sizeBytes != right.sizeBytes {
                    return left.sizeBytes > right.sizeBytes
                }
                return left.deviceIdentifier.localizedStandardCompare(
                    right.deviceIdentifier) == .orderedAscending
            }
            let children = childIDs.compactMap { build($0, depth: depth + 1) }
            return template.replacingChildren(children)
        }

        let items = roots
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .compactMap { build($0, depth: 0) }

        return KBDiskInventorySnapshot(
            items: items,
            generatedAt: Date(),
            error: nil,
            source: "iokit+diskarbitration"
        )
    }

    private func kind(for raw: kb_disk_media,
                      roles: [String]) -> KBDiskItemKind {
        if raw.is_apfs_container != 0 {
            return .apfsContainer
        }
        if raw.is_apfs_volume != 0 {
            let isSnapshot = roles.contains { $0.localizedCaseInsensitiveContains("snapshot") }
            return isSnapshot ? .snapshot : .apfsVolume
        }
        if raw.is_whole != 0 {
            return .physicalDisk
        }
        return .partition
    }

    private func kindRank(_ kind: KBDiskItemKind) -> Int {
        switch kind {
        case .physicalDisk: return 0
        case .partition: return 1
        case .apfsContainer: return 2
        case .apfsVolume: return 3
        case .snapshot: return 4
        }
    }

    private func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

private extension KBDiskItem {
    func replacingChildren(_ children: [KBDiskItem]) -> KBDiskItem {
        KBDiskItem(
            kind: kind,
            name: name,
            deviceIdentifier: deviceIdentifier,
            content: content,
            fileSystem: fileSystem,
            mountPoint: mountPoint,
            sizeBytes: sizeBytes,
            usedBytes: usedBytes,
            freeBytes: freeBytes,
            availableBytes: availableBytes,
            volumeUUID: volumeUUID,
            mediaUUID: mediaUUID,
            volumeGroupUUID: volumeGroupUUID,
            roles: roles,
            isInternal: isInternal,
            isRemovable: isRemovable,
            isWritable: isWritable,
            isEncrypted: isEncrypted,
            deviceModel: deviceModel,
            deviceProtocol: deviceProtocol,
            busName: busName,
            parentID: parentID,
            children: children
        )
    }
}
