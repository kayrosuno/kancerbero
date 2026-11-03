import Foundation

/// Used/free space reported for a disk-hierarchy row and the radial chart.
///
/// APFS containers report their own capacity; volumes share the container's
/// free space, so a volume only reports used bytes. Disks and partitions
/// aggregate the capacity-bearing units below them without double counting:
/// a container already includes its volumes, and a partition that contains a
/// container is represented by that container.
public struct KBDiskSpaceUsage: Sendable, Hashable {
    public let usedBytes: UInt64?
    public let freeBytes: UInt64?
    /// True when at least one capacity-bearing descendant could not report
    /// usage (an unmounted volume or partition). The values are then a lower
    /// bound for used and may overstate free space.
    public let isPartial: Bool

    public init(usedBytes: UInt64?, freeBytes: UInt64?,
                isPartial: Bool = false) {
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.isPartial = isPartial
    }

    public var isKnown: Bool { usedBytes != nil }
}

public extension KBDiskItem {
    var spaceUsage: KBDiskSpaceUsage {
        switch kind {
        case .apfsContainer:
            guard hasMountedAPFSVolume else {
                // The collector leaves used/free at zero when no volume is
                // mounted; that means unknown, not empty.
                return KBDiskSpaceUsage(usedBytes: nil, freeBytes: nil,
                                        isPartial: true)
            }
            return KBDiskSpaceUsage(usedBytes: usedBytes, freeBytes: freeBytes)

        case .apfsVolume, .snapshot:
            return KBDiskSpaceUsage(usedBytes: usedBytes, freeBytes: nil)

        case .physicalDisk, .partition:
            return aggregateUsage()
        }
    }
}

private extension KBDiskItem {
    var hasMountedAPFSVolume: Bool {
        hasMountedAPFSVolume(in: children)
    }

    var hasCapacityDescendant: Bool {
        children.contains { child in
            child.sizeBytes > 0 || child.hasCapacityDescendant
        }
    }

    func hasMountedAPFSVolume(in items: [KBDiskItem]) -> Bool {
        items.contains { item in
            (item.kind == .apfsVolume && item.mountPoint?.isEmpty == false)
                || hasMountedAPFSVolume(in: item.children)
        }
    }

    /// Capacity-bearing leaves of the subtree. APFS containers stop the walk
    /// because their used already includes every volume; volumes and snapshots
    /// are never added on their own.
    var capacityUnits: [KBDiskItem] {
        switch kind {
        case .apfsContainer:
            return [self]
        case .apfsVolume, .snapshot:
            return []
        case .physicalDisk, .partition:
            return children.flatMap(\.capacityUnits)
        }
    }

    func aggregateUsage() -> KBDiskSpaceUsage {
        let units = capacityUnits
        guard !units.isEmpty else {
            // A plain mounted filesystem partition reports its own values;
            // an unmounted one stays unknown. With capacity-bearing children
            // that could not report, flag the result as partial.
            let hidden = usedBytes == nil && hasCapacityDescendant
            return KBDiskSpaceUsage(usedBytes: usedBytes, freeBytes: freeBytes,
                                    isPartial: hidden)
        }

        var seen = Set<String>()
        var used: UInt64 = 0
        var free: UInt64 = 0
        var hasUsed = false
        var hasFree = false
        var partial = false

        for unit in units
        where seen.insert(unit.deviceIdentifier).inserted {
            let usage = unit.spaceUsage
            if let value = usage.usedBytes {
                used = adding(used, value)
                hasUsed = true
            }
            if let value = usage.freeBytes {
                free = adding(free, value)
                hasFree = true
            }
            partial = partial || usage.isPartial || usage.usedBytes == nil
        }

        return KBDiskSpaceUsage(usedBytes: hasUsed ? used : nil,
                                freeBytes: hasFree ? free : nil,
                                isPartial: partial)
    }

    func adding(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}
