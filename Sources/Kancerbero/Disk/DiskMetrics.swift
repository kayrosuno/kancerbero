import Foundation
import KancerberoCore

/// Shared disk totals used by the volumes cards and the contextual status bar.
enum DiskMetrics {
    static func capacityBytes(_ inventory: KBDiskInventorySnapshot?) -> UInt64 {
        inventory?.items.reduce(UInt64(0)) { $0 &+ $1.sizeBytes } ?? 0
    }

    /// Free space deduplicated across APFS containers, mirroring how the
    /// volumes tree reports capacity.
    static func freeBytes(_ inventory: KBDiskInventorySnapshot?) -> UInt64 {
        guard let inventory else { return 0 }
        var seenContainers = Set<String>()
        var total: UInt64 = 0
        for item in inventory.allItems {
            if item.kind == .apfsVolume || item.kind == .snapshot {
                continue
            }
            if item.kind == .apfsContainer {
                guard let free = item.freeBytes,
                      seenContainers.insert(item.deviceIdentifier).inserted else { continue }
                total &+= free
            } else if item.mountPoint != nil, let free = item.freeBytes {
                total &+= free
            }
        }
        return total
    }

    static func physicalDiskCount(_ inventory: KBDiskInventorySnapshot?) -> Int {
        inventory?.items.count ?? 0
    }

    static func mountedVolumeCount(_ inventory: KBDiskInventorySnapshot?) -> Int {
        inventory?.mountedVolumes.count ?? 0
    }
}
