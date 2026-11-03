import Foundation

/// One slice of the APFS space bar for the APFS space chart.
public struct APFSSpaceSegment: Sendable, Identifiable, Hashable {
    public enum Role: String, Sendable, Hashable {
        case volume
        case residual
        case free
        case container
        case unknown
    }

    public let id: String
    public let label: String
    public let role: Role
    /// Display value in bytes.
    public let bytes: UInt64
    /// Share of the chart's total (0...1).
    public let fraction: Double
    /// Device identifier used to highlight the selected volume/container.
    public let itemID: String?

    public init(id: String, label: String, role: Role, bytes: UInt64,
                fraction: Double, itemID: String? = nil) {
        self.id = id
        self.label = label
        self.role = role
        self.bytes = bytes
        self.fraction = fraction
        self.itemID = itemID
    }
}

/// One legend row for the APFS space chart.
public struct APFSSpaceLegendRow: Sendable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let role: APFSSpaceSegment.Role
    /// Used bytes, or nil when the volume/container is not mounted.
    public let bytes: UInt64?
    /// Capacity for container rows.
    public let capacityBytes: UInt64?
    /// Used fraction (0...1) for the trailing percentage.
    public let percent: Double?
    /// Secondary line: roles, mount point or volume/snapshot counts.
    public let detail: String?
    public let itemID: String?

    public init(id: String, label: String, role: APFSSpaceSegment.Role,
                bytes: UInt64?, capacityBytes: UInt64? = nil,
                percent: Double? = nil, detail: String? = nil,
                itemID: String? = nil) {
        self.id = id
        self.label = label
        self.role = role
        self.bytes = bytes
        self.capacityBytes = capacityBytes
        self.percent = percent
        self.detail = detail
        self.itemID = itemID
    }
}

/// Everything the APFS space chart needs for a selected disk, container,
/// volume or snapshot.
public struct APFSSpaceContext: Sendable, Hashable {
    public enum Subject: String, Sendable, Hashable {
        case physicalDisk
        case container
        case volume
        case snapshot
    }

    public enum Availability: String, Sendable, Hashable {
        case ready
        /// The container has no mounted volume, so free space is unknown.
        case unmounted
        /// Capacity is zero or missing.
        case unavailable
    }

    public let subject: Subject
    public let availability: Availability
    public let title: String
    public let caption: String?
    public let totalBytes: UInt64
    public let usedBytes: UInt64?
    public let freeBytes: UInt64?
    public let segments: [APFSSpaceSegment]
    public let legend: [APFSSpaceLegendRow]
    public let highlightedItemID: String?
    public let note: String?
}

public extension KBDiskInventorySnapshot {
    /// Containers in the subtree (or the item itself when it is a container).
    func apfsContainers(under item: KBDiskItem) -> [KBDiskItem] {
        var result: [KBDiskItem] = []
        func visit(_ node: KBDiskItem) {
            if node.kind == .apfsContainer { result.append(node) }
            for child in node.children { visit(child) }
        }
        visit(item)
        return result
    }

    /// Walks the real tree while carrying the current container, so it works
    /// for volumes and for snapshots nested under a volume.
    func apfsContainer(enclosing item: KBDiskItem) -> KBDiskItem? {
        if item.kind == .apfsContainer { return item }
        func search(_ node: KBDiskItem, current: KBDiskItem?) -> KBDiskItem? {
            let container = node.kind == .apfsContainer ? node : current
            if node.deviceIdentifier == item.deviceIdentifier { return container }
            for child in node.children {
                if let found = search(child, current: container) { return found }
            }
            return nil
        }
        for root in items {
            if let found = search(root, current: nil) { return found }
        }
        return nil
    }

    /// Nearest enclosing APFS volume for a snapshot selection.
    func nearestAncestorVolume(of item: KBDiskItem) -> KBDiskItem? {
        func search(_ node: KBDiskItem, current: KBDiskItem?) -> KBDiskItem? {
            let volume = node.kind == .apfsVolume ? node : current
            if node.deviceIdentifier == item.deviceIdentifier { return volume }
            for child in node.children {
                if let found = search(child, current: volume) { return found }
            }
            return nil
        }
        for root in items {
            if let found = search(root, current: nil) { return found }
        }
        return nil
    }

    /// Chart context for the selected item; nil for non-APFS media.
    func apfsSpaceContext(for item: KBDiskItem) -> APFSSpaceContext? {
        switch item.kind {
        case .physicalDisk, .partition:
            let containers = apfsContainers(under: item)
            guard !containers.isEmpty else { return nil }
            if containers.count == 1 {
                return APFSSpaceBuilder.volumeBreakdown(
                    container: containers[0],
                    subject: .physicalDisk,
                    captionPrefix: "1 APFS container",
                    highlightedItemID: nil)
            }
            return APFSSpaceBuilder.containerSummary(containers)

        case .apfsContainer:
            return APFSSpaceBuilder.volumeBreakdown(
                container: item,
                subject: .container,
                captionPrefix: Self.containerLabel(item),
                highlightedItemID: nil)

        case .apfsVolume, .snapshot:
            guard let container = apfsContainer(enclosing: item) else {
                return nil
            }
            let highlight = item.kind == .apfsVolume
                ? item.deviceIdentifier
                : nearestAncestorVolume(of: item)?.deviceIdentifier
            return APFSSpaceBuilder.volumeBreakdown(
                container: container,
                subject: item.kind == .snapshot ? .snapshot : .volume,
                captionPrefix: Self.containerLabel(container),
                highlightedItemID: highlight)
        }
    }

    private static func containerLabel(_ container: KBDiskItem) -> String {
        container.name.isEmpty
            ? container.deviceIdentifier
            : "\(container.deviceIdentifier) · \(container.name)"
    }
}

private enum APFSSpaceBuilder {
    static func volumeBreakdown(container: KBDiskItem,
                                subject: APFSSpaceContext.Subject,
                                captionPrefix: String?,
                                highlightedItemID: String?) -> APFSSpaceContext? {
        let capacity = container.sizeBytes
        let volumes = container.children
            .filter { $0.kind == .apfsVolume }
            .sorted { ($0.usedBytes ?? 0) > ($1.usedBytes ?? 0) }
        let snapshots = container.descendants(ofKind: .snapshot)
        let mounted = volumes.filter { $0.mountPoint?.isEmpty == false }

        var captionParts: [String] = []
        if let captionPrefix { captionParts.append(captionPrefix) }
        captionParts.append("\(volumes.count) volume\(volumes.count == 1 ? "" : "s")")
        if !snapshots.isEmpty {
            captionParts.append("\(snapshots.count) snapshot\(snapshots.count == 1 ? "" : "s")")
        }
        let caption = captionParts.joined(separator: " · ")

        let legend = volumes.map { volume in
            APFSSpaceLegendRow(
                id: "volume:\(volume.deviceIdentifier)",
                label: volumeLabel(volume),
                role: .volume,
                bytes: volume.usedBytes,
                percent: volume.usedBytes.map {
                    Double($0) / Double(max(capacity, 1))
                },
                detail: volumeDetail(volume),
                itemID: volume.deviceIdentifier)
        }

        if capacity == 0 {
            return APFSSpaceContext(
                subject: subject, availability: .unavailable,
                title: "APFS space", caption: caption,
                totalBytes: 0, usedBytes: nil, freeBytes: nil,
                segments: [unknownSegment(bytes: 0)],
                legend: legend,
                highlightedItemID: highlightedItemID,
                note: "Capacity unavailable.")
        }

        guard !mounted.isEmpty else {
            return APFSSpaceContext(
                subject: subject, availability: .unmounted,
                title: "APFS space", caption: caption,
                totalBytes: capacity, usedBytes: nil, freeBytes: nil,
                segments: [unknownSegment(bytes: capacity)],
                legend: legend,
                highlightedItemID: highlightedItemID,
                note: "No mounted volume in this container, so free space is unknown.")
        }

        let free = min(container.freeBytes ?? 0, capacity)
        let usable = capacity - free

        var usedSum: UInt64 = 0
        var anyUnmounted = false
        for volume in volumes {
            guard let used = volume.usedBytes else {
                anyUnmounted = true
                continue
            }
            let (sum, overflow) = usedSum.addingReportingOverflow(min(used, capacity))
            usedSum = overflow ? UInt64.max : sum
        }

        let estimated = usedSum > usable
        let residual = estimated ? 0 : usable - usedSum

        var segments: [APFSSpaceSegment] = []
        for volume in volumes {
            guard let used = volume.usedBytes, used > 0 else { continue }
            let fraction: Double
            if estimated {
                let share = usedSum > 0 ? Double(used) / Double(usedSum) : 0
                fraction = share * Double(usable) / Double(capacity)
            } else {
                fraction = Double(used) / Double(capacity)
            }
            segments.append(APFSSpaceSegment(
                id: "volume:\(volume.deviceIdentifier)",
                label: volumeLabel(volume),
                role: .volume,
                bytes: used,
                fraction: fraction,
                itemID: volume.deviceIdentifier))
        }

        if residual > 0 {
            segments.append(APFSSpaceSegment(
                id: "residual",
                label: residualLabel(snapshots: !snapshots.isEmpty,
                                     unmounted: anyUnmounted),
                role: .residual,
                bytes: residual,
                fraction: Double(residual) / Double(capacity)))
        }

        if free > 0 {
            segments.append(APFSSpaceSegment(
                id: "free", label: "Free", role: .free,
                bytes: free,
                fraction: Double(free) / Double(capacity)))
        }

        var fullLegend = legend
        if residual > 0 {
            fullLegend.append(APFSSpaceLegendRow(
                id: "residual",
                label: residualLabel(snapshots: !snapshots.isEmpty,
                                     unmounted: anyUnmounted),
                role: .residual,
                bytes: residual,
                percent: Double(residual) / Double(capacity)))
        }
        fullLegend.append(APFSSpaceLegendRow(
            id: "free", label: "Free", role: .free,
            bytes: free,
            percent: Double(free) / Double(capacity)))

        return APFSSpaceContext(
            subject: subject, availability: .ready,
            title: "APFS space", caption: caption,
            totalBytes: capacity, usedBytes: usable, freeBytes: free,
            segments: segments,
            legend: fullLegend,
            highlightedItemID: highlightedItemID,
            note: estimated
                ? "Volume usage exceeds the container's used space; slices are scaled to fit."
                : nil)
    }

    static func containerSummary(_ containers: [KBDiskItem]) -> APFSSpaceContext? {
        var total: UInt64 = 0
        for container in containers {
            let (sum, overflow) = total.addingReportingOverflow(container.sizeBytes)
            total = overflow ? UInt64.max : sum
        }
        guard total > 0 else { return nil }

        let sorted = containers.sorted { $0.sizeBytes > $1.sizeBytes }
        var segments: [APFSSpaceSegment] = []
        var legend: [APFSSpaceLegendRow] = []
        var volumeCount = 0
        var snapshotCount = 0
        var usedSum: UInt64 = 0
        var hasKnownUsed = false

        for container in sorted {
            let volumes = container.children.filter { $0.kind == .apfsVolume }
            let snapshots = container.descendants(ofKind: .snapshot)
            volumeCount += volumes.count
            snapshotCount += snapshots.count

            let isMounted = volumes.contains { $0.mountPoint?.isEmpty == false }
            let used: UInt64? = isMounted
                ? (container.usedBytes
                   ?? max(0, container.sizeBytes - (container.freeBytes ?? 0)))
                : nil
            if let used {
                hasKnownUsed = true
                let (sum, overflow) = usedSum.addingReportingOverflow(used)
                usedSum = overflow ? UInt64.max : sum
            }

            let id = "container:\(container.deviceIdentifier)"
            let label = container.name.isEmpty
                ? container.deviceIdentifier
                : "\(container.deviceIdentifier) · \(container.name)"
            segments.append(APFSSpaceSegment(
                id: id, label: label, role: .container,
                bytes: container.sizeBytes,
                fraction: Double(container.sizeBytes) / Double(total),
                itemID: container.deviceIdentifier))
            legend.append(APFSSpaceLegendRow(
                id: id, label: label, role: .container,
                bytes: used,
                capacityBytes: container.sizeBytes,
                percent: used.map { Double($0) / Double(max(container.sizeBytes, 1)) },
                detail: "\(volumes.count) volume\(volumes.count == 1 ? "" : "s")"
                    + " · \(snapshots.count) snapshot\(snapshots.count == 1 ? "" : "s")",
                itemID: container.deviceIdentifier))
        }

        var captionParts = [
            "\(containers.count) container\(containers.count == 1 ? "" : "s")",
            "\(volumeCount) volume\(volumeCount == 1 ? "" : "s")"
        ]
        if snapshotCount > 0 {
            captionParts.append("\(snapshotCount) snapshot\(snapshotCount == 1 ? "" : "s")")
        }

        return APFSSpaceContext(
            subject: .physicalDisk, availability: .ready,
            title: "APFS space",
            caption: captionParts.joined(separator: " · "),
            totalBytes: total,
            usedBytes: hasKnownUsed ? usedSum : nil,
            freeBytes: nil,
            segments: segments,
            legend: legend,
            highlightedItemID: nil,
            note: hasKnownUsed
                ? nil
                : "Used space is unavailable for containers without a mounted volume.")
    }

    private static func unknownSegment(bytes: UInt64) -> APFSSpaceSegment {
        APFSSpaceSegment(id: "unknown", label: "Unknown",
                         role: .unknown, bytes: bytes, fraction: 1)
    }

    private static func volumeLabel(_ volume: KBDiskItem) -> String {
        volume.name.isEmpty ? volume.deviceIdentifier : volume.name
    }

    private static func volumeDetail(_ volume: KBDiskItem) -> String? {
        if let mountPoint = volume.mountPoint, !mountPoint.isEmpty {
            return mountPoint
        }
        if !volume.roles.isEmpty {
            return volume.roles.joined(separator: ", ")
        }
        return "Not mounted"
    }

    private static func residualLabel(snapshots: Bool, unmounted: Bool) -> String {
        switch (snapshots, unmounted) {
        case (true, true): return "Snapshots, metadata & unmounted"
        case (true, false): return "Snapshots & metadata"
        case (false, true): return "Metadata & unmounted"
        case (false, false): return "Metadata & overhead"
        }
    }
}

private extension KBDiskItem {
    func descendants(ofKind kind: KBDiskItemKind) -> [KBDiskItem] {
        var result: [KBDiskItem] = []
        for child in children {
            if child.kind == kind { result.append(child) }
            result.append(contentsOf: child.descendants(ofKind: kind))
        }
        return result
    }
}
