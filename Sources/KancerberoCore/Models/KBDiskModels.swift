import Foundation

public struct KBDiskScanOptions: Sendable, Hashable {
    /// Descend into bundles and treat their contents as part of the bundle size.
    public var descendPackages: Bool
    /// Follow directories that are mount points of another file system.
    public var crossMountPoints: Bool
    public var maxDepth: Int
    /// Children retained per directory; the rest are folded into an "Other" node.
    public var maxChildrenRetained: Int
    /// Global cap on retained directory nodes.
    public var maxNodes: Int
    public var largestFilesLimit: Int
    public var includeHiddenInLargestFiles: Bool

    public init(descendPackages: Bool = true,
                crossMountPoints: Bool = false,
                maxDepth: Int = 40,
                maxChildrenRetained: Int = 200,
                maxNodes: Int = 150_000,
                largestFilesLimit: Int = 100,
                includeHiddenInLargestFiles: Bool = false) {
        self.descendPackages = descendPackages
        self.crossMountPoints = crossMountPoints
        self.maxDepth = maxDepth
        self.maxChildrenRetained = maxChildrenRetained
        self.maxNodes = maxNodes
        self.largestFilesLimit = largestFilesLimit
        self.includeHiddenInLargestFiles = includeHiddenInLargestFiles
    }
}

public struct KBDiskNode: Sendable, Identifiable {
    public var id: String { path }

    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let isMountPoint: Bool
    public let accessDenied: Bool
    public let isAggregate: Bool
    public let allocatedBytes: UInt64
    public let logicalBytes: UInt64
    public let fileCount: Int
    public let folderCount: Int
    public let children: [KBDiskNode]
    public let aggregatedChildren: Int
    public let truncated: Bool

    public init(name: String,
                path: String,
                isDirectory: Bool,
                isPackage: Bool,
                isHidden: Bool,
                isMountPoint: Bool,
                accessDenied: Bool,
                isAggregate: Bool,
                allocatedBytes: UInt64,
                logicalBytes: UInt64,
                fileCount: Int,
                folderCount: Int,
                children: [KBDiskNode],
                aggregatedChildren: Int,
                truncated: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.isMountPoint = isMountPoint
        self.accessDenied = accessDenied
        self.isAggregate = isAggregate
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.children = children
        self.aggregatedChildren = aggregatedChildren
        self.truncated = truncated
    }

    /// Depth-first lookup by path. The tree is pruned, so a missing path means
    /// it was folded into an aggregate node or the scan was truncated.
    public func node(at path: String) -> KBDiskNode? {
        if self.path == path { return self }
        for child in children {
            if path == child.path { return child }
            if path.hasPrefix(child.path + "/"), let found = child.node(at: path) {
                return found
            }
        }
        return nil
    }

    /// Parent chain from the root to `path`, inclusive.
    public func lineage(to path: String) -> [KBDiskNode] {
        if self.path == path { return [self] }
        for child in children where path == child.path || path.hasPrefix(child.path + "/") {
            let line = child.lineage(to: path)
            if !line.isEmpty { return [self] + line }
        }
        return []
    }
}

public struct KBDiskFile: Sendable, Identifiable, Hashable {
    public var id: String { path }

    public let name: String
    public let path: String
    public let allocatedBytes: UInt64
    public let logicalBytes: UInt64
    public let isHidden: Bool

    public init(name: String,
                path: String,
                allocatedBytes: UInt64,
                logicalBytes: UInt64,
                isHidden: Bool) {
        self.name = name
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.isHidden = isHidden
    }
}

public struct KBDiskScanProgress: Sendable, Hashable {
    public let path: String
    public let files: Int
    public let folders: Int
    public let bytes: UInt64
    public let denied: Int
    public let elapsed: TimeInterval

    public init(path: String, files: Int, folders: Int, bytes: UInt64,
                denied: Int, elapsed: TimeInterval) {
        self.path = path
        self.files = files
        self.folders = folders
        self.bytes = bytes
        self.denied = denied
        self.elapsed = elapsed
    }
}

public struct KBDiskScanSnapshot: Sendable {
    public let root: KBDiskNode
    public let largestFiles: [KBDiskFile]
    public let deniedPaths: [String]
    public let options: KBDiskScanOptions
    public let generatedAt: Date
    public let duration: TimeInterval
    public let cancelled: Bool
    public let error: String?

    public init(root: KBDiskNode,
                largestFiles: [KBDiskFile],
                deniedPaths: [String],
                options: KBDiskScanOptions,
                generatedAt: Date,
                duration: TimeInterval,
                cancelled: Bool,
                error: String?) {
        self.root = root
        self.largestFiles = largestFiles
        self.deniedPaths = deniedPaths
        self.options = options
        self.generatedAt = generatedAt
        self.duration = duration
        self.cancelled = cancelled
        self.error = error
    }
}

public enum KBDiskItemKind: String, Sendable, Hashable, CaseIterable {
    case physicalDisk
    case partition
    case apfsContainer
    case apfsVolume
    case snapshot

    public var displayName: String {
        switch self {
        case .physicalDisk: return "Physical disk"
        case .partition: return "Partition"
        case .apfsContainer: return "APFS container"
        case .apfsVolume: return "APFS volume"
        case .snapshot: return "Snapshot"
        }
    }
}

public struct KBDiskItem: Sendable, Identifiable {
    public var id: String { deviceIdentifier }

    public let kind: KBDiskItemKind
    public let name: String
    public let deviceIdentifier: String
    public let content: String?
    public let fileSystem: String?
    public let mountPoint: String?
    public let sizeBytes: UInt64
    public let usedBytes: UInt64?
    public let freeBytes: UInt64?
    public let availableBytes: UInt64?
    public let volumeUUID: String?
    public let mediaUUID: String?
    public let volumeGroupUUID: String?
    public let roles: [String]
    public let isInternal: Bool?
    public let isRemovable: Bool?
    public let isWritable: Bool?
    public let isEncrypted: Bool?
    public let deviceModel: String?
    public let deviceProtocol: String?
    public let busName: String?
    public let parentID: String?
    public let children: [KBDiskItem]

    public init(kind: KBDiskItemKind,
                name: String,
                deviceIdentifier: String,
                content: String?,
                fileSystem: String?,
                mountPoint: String?,
                sizeBytes: UInt64,
                usedBytes: UInt64?,
                freeBytes: UInt64?,
                availableBytes: UInt64?,
                volumeUUID: String?,
                mediaUUID: String?,
                volumeGroupUUID: String?,
                roles: [String],
                isInternal: Bool?,
                isRemovable: Bool?,
                isWritable: Bool?,
                isEncrypted: Bool?,
                deviceModel: String?,
                deviceProtocol: String?,
                busName: String?,
                parentID: String?,
                children: [KBDiskItem]) {
        self.kind = kind
        self.name = name
        self.deviceIdentifier = deviceIdentifier
        self.content = content
        self.fileSystem = fileSystem
        self.mountPoint = mountPoint
        self.sizeBytes = sizeBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.availableBytes = availableBytes
        self.volumeUUID = volumeUUID
        self.mediaUUID = mediaUUID
        self.volumeGroupUUID = volumeGroupUUID
        self.roles = roles
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isWritable = isWritable
        self.isEncrypted = isEncrypted
        self.deviceModel = deviceModel
        self.deviceProtocol = deviceProtocol
        self.busName = busName
        self.parentID = parentID
        self.children = children
    }

    /// Depth-first lookup by device identifier.
    public func item(withID id: String) -> KBDiskItem? {
        if deviceIdentifier == id { return self }
        for child in children {
            if let found = child.item(withID: id) { return found }
        }
        return nil
    }

    public var volumeUsedFraction: Double? {
        guard sizeBytes > 0, let usedBytes else { return nil }
        return min(1, Double(usedBytes) / Double(sizeBytes))
    }
}

public struct KBDiskInventorySnapshot: Sendable {
    public let items: [KBDiskItem]
    public let generatedAt: Date
    public let error: String?
    public let source: String

    public init(items: [KBDiskItem],
                generatedAt: Date,
                error: String?,
                source: String) {
        self.items = items
        self.generatedAt = generatedAt
        self.error = error
        self.source = source
    }

    public var allItems: [KBDiskItem] {
        var result: [KBDiskItem] = []
        func visit(_ item: KBDiskItem) {
            result.append(item)
            for child in item.children { visit(child) }
        }
        for item in items { visit(item) }
        return result
    }

    public var mountedVolumes: [KBDiskItem] {
        allItems.filter { $0.mountPoint?.isEmpty == false }
    }

    public var physicalDiskCount: Int { items.count }
}
