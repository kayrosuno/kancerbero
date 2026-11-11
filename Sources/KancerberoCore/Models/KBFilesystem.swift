import Foundation

/// One mounted filesystem. APFS capacities/free space are shared; do not sum
/// these rows to calculate physical disk usage.
public struct KBFilesystem: Identifiable, Sendable, Hashable {
    public var id: String { mountPoint }
    public let filesystem: String
    public let type: String
    public let mountPoint: String
    public let sizeBytes: UInt64
    public let usedBytes: UInt64
    public let availableBytes: UInt64
    public let inodeCount: UInt64
    public let freeInodes: UInt64
    public let isReadOnly: Bool
    public let isCached: Bool
    public let warning: String?

    public init(filesystem: String, type: String, mountPoint: String,
                sizeBytes: UInt64, usedBytes: UInt64, availableBytes: UInt64,
                inodeCount: UInt64, freeInodes: UInt64,
                isReadOnly: Bool = false, isCached: Bool = false,
                warning: String? = nil) {
        self.filesystem = filesystem
        self.type = type
        self.mountPoint = mountPoint
        self.sizeBytes = sizeBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.inodeCount = inodeCount
        self.freeInodes = freeInodes
        self.isReadOnly = isReadOnly
        self.isCached = isCached
        self.warning = warning
    }

    /// df uses used/(used+available), rounded up, not used/size. In particular
    /// this differs for APFS and reserved blocks. Zero/zero is 100% in df.
    public var capacityPercent: Double {
        let denominator = Double(usedBytes) + Double(availableBytes)
        return denominator == 0 ? 100 : ceil(Double(usedBytes) / denominator * 100)
    }

    public var usedInodes: UInt64 {
        inodeCount >= freeInodes ? inodeCount - freeInodes : 0
    }

    /// -1 is a sortable sentinel for an undefined inode percentage.
    public var inodePercent: Double {
        inodeCount == 0 ? -1 : (Double(usedInodes) / Double(inodeCount) * 100).rounded()
    }
}

public struct KBFilesystemSnapshot: Sendable {
    public let filesystems: [KBFilesystem]
    public let generatedAt: Date
    public let error: String?
}
