import AppKit
import SwiftUI
import KancerberoCore

/// One big number shown beside the radial chart.
struct VolumeHierarchyStat: Identifiable {
    let id: String
    let title: String
    let value: String
}

/// Multi-ring hierarchy of the selected disk: partitions → APFS containers →
/// volumes. The scope always climbs to the physical disk so the shape stays
/// stable while the user selects different items; the selected item is
/// outlined in its ring and in the legend.
struct VolumeHierarchyChart: View {
    let item: KBDiskItem
    let inventory: KBDiskInventorySnapshot
    var isMaximized = false
    var onSelectItem: ((String) -> Void)? = nil
    var stats: [VolumeHierarchyStat] = []
    var usageFraction: Double? = nil
    var usageCaption: String? = nil
    var notes: [String] = []

    @Environment(\.byteUnitSystem) private var byteUnitSystem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredNodeID: String?
    @State private var chartHoverNodeID: String?
    @State private var hoverLocation: CGPoint?

    var body: some View {
        let scope = scopeItem(in: inventory)
        let nodes = makeNodes(for: scope)
        let highlightID = highlightID(in: nodes)
        let rows = legendRows(nodes)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center,
                   spacing: isMaximized ? 14 : 10) {
                heroInfo
                circle(nodes: nodes, scope: scope, highlightID: highlightID)
                    .frame(height: isMaximized ? 760 : 500)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            legend(rows, highlightID: highlightID)
        }
        .padding(.top, 6)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25),
                   value: item.deviceIdentifier)
    }

    // MARK: - Hero

    private var heroInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let capacity = capacityStat {
                VStack(alignment: .leading, spacing: 1) {
                    Text(capacity.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Text(capacity.value)
                        .font(.system(
                            size: isMaximized ? 24 : 20,
                            weight: .semibold,
                            design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .offset(y: -10)
            }

            HStack(alignment: .center,
                   spacing: isMaximized ? 12 : 6) {
                VerticalUsageBar(
                    fraction: usageFraction,
                    tint: DiskPalette.tint(for: item.kind),
                    kindLabel: gaugeKindLabel(for: item.kind),
                    caption: usageCaption,
                    height: isMaximized ? 300 : 210,
                    width: isMaximized ? 54 : 46,
                    isMaximized: isMaximized)
                statsColumn
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var capacityStat: VolumeHierarchyStat? {
        stats.first { $0.id == "capacity" }
    }

    private var sideStats: [VolumeHierarchyStat] {
        stats.filter { $0.id != "capacity" }
    }

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: isMaximized ? 14 : 11) {
            ForEach(sideStats) { stat in
                VStack(alignment: .leading, spacing: 1) {
                    Text(stat.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(stat.value)
                        .font(.system(
                            size: isMaximized ? 24 : 20,
                            weight: .semibold,
                            design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: isMaximized ? 150 : 130, alignment: .leading)
    }

    private func countsText(for scope: KBDiskItem) -> String {
        var partitions = 0
        var containers = 0
        var volumes = 0
        func visit(_ item: KBDiskItem) {
            switch item.kind {
            case .partition: partitions += 1
            case .apfsContainer: containers += 1
            case .apfsVolume: volumes += 1
            default: break
            }
            for child in item.children { visit(child) }
        }
        for child in scope.children { visit(child) }

        func count(_ value: Int, _ singular: String, _ plural: String) -> String {
            "\(value) \(value == 1 ? singular : plural)"
        }
        return "\(count(partitions, "partition", "partitions")) · "
            + "\(count(containers, "container", "containers")) · "
            + count(volumes, "volume", "volumes")
    }

    // MARK: - Chart

    private func circle(nodes: [HierarchyNode],
                        scope: KBDiskItem,
                        highlightID: String?) -> some View {
        GeometryReader { proxy in
            let layout = makeLayout(nodes: nodes, in: proxy.size,
                                    baseLevel: baseLevel(for: scope.kind))

            ZStack(alignment: .topLeading) {
                halo(layout: layout)

                Canvas { context, _ in
                    draw(layout: layout, highlightID: highlightID,
                         context: &context)
                }

                centerLabel(for: item, centerRadius: layout.centerRadius)
                    .position(layout.center)
                    .allowsHitTesting(false)

                if let hovered = hoveredSector(in: layout) {
                    tooltip(hovered)
                        .offset(x: tooltipX(in: proxy.size),
                                y: tooltipY(in: proxy.size))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let hovered = callout(at: location, in: layout)?.node.id
                        ?? sector(at: location, in: layout)?.node.id
                    if hovered != hoveredNodeID {
                        hoveredNodeID = hovered
                        chartHoverNodeID = hovered
                    }
                    hoverLocation = location
                case .ended:
                    hoveredNodeID = nil
                    chartHoverNodeID = nil
                    hoverLocation = nil
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if isInsideCenter(value.location, in: layout) {
                        onSelectItem?(scope.deviceIdentifier)
                        return
                    }
                    if let callout = callout(at: value.location, in: layout),
                       callout.node.role.isSelectable,
                       let itemID = callout.node.itemID {
                        onSelectItem?(itemID)
                        return
                    }
                    guard let sector = sector(at: value.location, in: layout),
                          sector.node.role.isSelectable,
                          let itemID = sector.node.itemID else { return }
                    onSelectItem?(itemID)
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Disk structure")
            .accessibilityValue(
                "\(displayName(scope)) (\(scope.deviceIdentifier)) · "
                    + "\(countsText(for: scope)) · \(kindLine(for: item))")
            .accessibilityAction(named: Text("Show disk details")) {
                onSelectItem?(scope.deviceIdentifier)
            }
        }
    }

    private func halo(layout: Layout) -> some View {
        Circle()
            .fill(AngularGradient(
                colors: [
                    DiskPalette.sand.opacity(0.16),
                    DiskPalette.stone.opacity(0.14),
                    DiskPalette.taupe.opacity(0.16),
                    DiskPalette.sand.opacity(0.16)
                ],
                center: .center))
            .frame(width: layout.maxRadius * 2 + 24,
                   height: layout.maxRadius * 2 + 24)
            .blur(radius: 26)
            .position(layout.center)
            .allowsHitTesting(false)
    }

    private func kindLine(for item: KBDiskItem) -> String {
        let kind = DiskPalette.kindLabel(for: item.kind).uppercased()
        let fileSystem = item.fileSystem
            ?? item.children.first?.fileSystem
        return fileSystem.map { "\(kind) · \($0)" } ?? kind
    }

    private func gaugeKindLabel(for kind: KBDiskItemKind) -> String {
        switch kind {
        case .physicalDisk: return "DISK"
        case .partition: return "PARTITION"
        case .apfsContainer: return "CONTAINER"
        case .apfsVolume: return "VOLUME"
        case .snapshot: return "SNAPSHOT"
        }
    }

    private func tooltipX(in size: CGSize) -> CGFloat {
        guard let hoverLocation else { return 8 }
        return min(max(8, hoverLocation.x + 16),
                   max(8, size.width - 200))
    }

    private func tooltipY(in size: CGSize) -> CGFloat {
        guard let hoverLocation else { return 8 }
        return min(max(8, hoverLocation.y + 16),
                   max(8, size.height - 150))
    }

    private func centerLabel(for item: KBDiskItem,
                             centerRadius: CGFloat) -> some View {
        let usage = item.spaceUsage
        return VStack(spacing: 1) {
            Image(systemName: icon(for: item.kind))
                .font(.system(size: isMaximized ? 20 : 15,
                              weight: .semibold))
                .foregroundStyle(DiskPalette.ink)
            Text(kindLine(for: item))
                .font(.system(size: isMaximized ? 10 : 9,
                              weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(displayName(item))
                .font(.system(size: isMaximized ? 16 : 13,
                              weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let used = usage.usedBytes {
                Text("\(KBFormat.bytes(used, units: byteUnitSystem)) used")
                    .font(.system(size: isMaximized ? 12.5 : 10.5,
                                  weight: .medium))
                    .monospacedDigit()
            } else {
                Text("Usage unknown")
                    .font(.system(size: isMaximized ? 10 : 8.5))
                    .foregroundStyle(.secondary)
            }
            if let free = usage.freeBytes {
                Text("\(KBFormat.bytes(free, units: byteUnitSystem)) free")
                    .font(.system(size: isMaximized ? 11 : 9.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let fraction = item.volumeUsedFraction {
                Text(KBFormat.percent(fraction))
                    .font(.system(size: isMaximized ? 11 : 9.5))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .frame(width: centerRadius * 1.7, height: centerRadius * 1.7)
    }

    private func tooltip(_ sector: Sector) -> some View {
        let node = sector.node
        return VStack(alignment: .leading, spacing: 2) {
            Text(node.label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text(subtitle(for: node))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let detail = node.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let capacity = node.capacityBytes {
                tooltipRow("Capacity", capacity)
            }
            if let used = node.usedBytes {
                tooltipRow("Used", used)
            }
            if let free = node.freeBytes {
                tooltipRow("Free", free)
            } else if node.usedBytes == nil && !node.role.isSelectable {
                tooltipRow("Size", node.bytes)
            }
            Text(KBFormat.percent(sector.globalFraction))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if node.role.isSelectable && node.itemID != nil {
                Text("Click to select")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.6), lineWidth: 1)
        }
    }

    private func tooltipRow(_ title: String, _ bytes: UInt64) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(KBFormat.bytes(bytes, units: byteUnitSystem))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private func subtitle(for node: HierarchyNode) -> String {
        let id = node.itemID.map { "\($0) · " } ?? ""
        let kind = node.kindLabel ?? ""
        guard let fileSystem = node.fileSystem,
              !fileSystem.isEmpty else {
            return id + kind
        }
        return "\(id)\(kind) · \(fileSystem)"
    }

    // MARK: - Legend

    private struct LegendRow: Identifiable {
        let id: String
        let node: HierarchyNode
        let depth: Int
    }

    private func legend(_ rows: [LegendRow], highlightID: String?) -> some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 220), spacing: 8)
        ], spacing: 4) {
            ForEach(rows) { row in
                legendRow(row, highlightID: highlightID)
            }
        }
    }

    @ViewBuilder
    private func legendRow(_ row: LegendRow,
                           highlightID: String?) -> some View {
        let node = row.node
        let selected = node.itemID != nil && node.itemID == highlightID
        let content = HStack(alignment: .top, spacing: 5) {
            legendSwatch(node)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(legendLabel(node))
                    .font(.system(size: 9.5,
                                  weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.8)
                Text(legendDetail(node))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 2)
            Text(legendValue(node))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .padding(.leading, CGFloat(row.depth) * 9)
        .background {
            if hoveredNodeID == node.id || selected {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.quaternary.opacity(0.32))
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hoveredNodeID = inside ? node.id : nil
        }

        if node.role.isSelectable, let itemID = node.itemID {
            Button { onSelectItem?(itemID) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(legendLabel(node)), \(legendDetail(node))")
                .accessibilityValue(legendValue(node))
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    /// Shape and color both identify the level: square = partition,
    /// rounded square = container, circle = volume.
    @ViewBuilder
    private func legendSwatch(_ node: HierarchyNode) -> some View {
        let border = DiskPalette.contentColor(on: node.color).opacity(0.45)
        switch node.role {
        case .partition:
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(node.color)
                .overlay {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .strokeBorder(border, lineWidth: 0.5)
                }
                .frame(width: 8, height: 8)
        case .container:
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(node.color)
                .overlay {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .strokeBorder(border, lineWidth: 0.5)
                }
                .frame(width: 8, height: 8)
        case .volume:
            Circle()
                .fill(node.color)
                .overlay { Circle().strokeBorder(border, lineWidth: 0.5) }
                .frame(width: 8, height: 8)
        case .free, .residual, .unallocated, .used, .unknown:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(node.color)
                .overlay {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(border, lineWidth: 0.5)
                }
                .frame(width: 8, height: 8)
        }
    }

    private func legendLabel(_ node: HierarchyNode) -> String {
        switch node.role {
        case .partition, .container, .volume:
            guard let id = node.itemID, id != node.label else {
                return node.label
            }
            return "\(id) · \(node.label)"
        default:
            return node.label
        }
    }

    private func legendDetail(_ node: HierarchyNode) -> String {
        let kind = node.kindLabel ?? ""
        guard let fileSystem = node.fileSystem,
              !fileSystem.isEmpty else {
            return kind
        }
        return "\(kind) · \(fileSystem)"
    }

    private func legendValue(_ node: HierarchyNode) -> String {
        switch node.role {
        case .partition, .container, .volume:
            guard let used = node.usedBytes else { return "—" }
            return KBFormat.bytes(used, units: byteUnitSystem)
        case .residual, .free, .unallocated, .used, .unknown:
            return KBFormat.bytes(node.bytes, units: byteUnitSystem)
        }
    }

    private func legendRows(_ nodes: [HierarchyNode],
                            depth: Int = 0) -> [LegendRow] {
        nodes.flatMap { node in
            [LegendRow(id: node.id, node: node, depth: depth)]
                + legendRows(node.children, depth: depth + 1)
        }
    }

    // MARK: - Data

    private func scopeItem(in inventory: KBDiskInventorySnapshot) -> KBDiskItem {
        var byID: [String: KBDiskItem] = [:]
        for item in inventory.allItems {
            byID[item.deviceIdentifier] = item
        }

        var current = item
        var highest = item
        var seen: Set<String> = [item.deviceIdentifier]
        var depth = 0

        while depth < 64,
              let parentID = current.parentID,
              let parent = byID[parentID],
              seen.insert(parent.deviceIdentifier).inserted {
            highest = parent
            current = parent
            if parent.kind == .physicalDisk { return parent }
            depth += 1
        }
        return highest
    }

    private func makeNodes(for scope: KBDiskItem) -> [HierarchyNode] {
        switch scope.kind {
        case .physicalDisk:
            var containerCount = 0
            var volumeCount = 0
            return partitionNodes(for: scope,
                                  containerCount: &containerCount,
                                  volumeCount: &volumeCount)
        case .partition:
            var containerCount = 0
            var volumeCount = 0
            let containers = containerNodes(
                for: scope,
                parentBytes: scope.sizeBytes,
                containerCount: &containerCount,
                volumeCount: &volumeCount)
            return containers.isEmpty ? usageNodes(for: scope) : containers
        case .apfsContainer:
            var volumeCount = 0
            return volumeNodes(for: scope, volumeCount: &volumeCount)
        case .apfsVolume, .snapshot:
            guard let container = inventory.apfsContainer(enclosing: scope) else {
                return []
            }
            var volumeCount = 0
            return volumeNodes(for: container, volumeCount: &volumeCount)
        }
    }

    private func partitionNodes(for scope: KBDiskItem,
                                containerCount: inout Int,
                                volumeCount: inout Int) -> [HierarchyNode] {
        let partitions = scope.children
            .filter { $0.kind != .snapshot && $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        guard !partitions.isEmpty else { return usageNodes(for: scope) }

        var accounted: UInt64 = 0
        for partition in partitions {
            accounted = adding(accounted, partition.sizeBytes)
        }
        let denominator = max(scope.sizeBytes, accounted)
        var nodes: [HierarchyNode] = []

        for (index, partition) in partitions.enumerated() {
            let color = DiskPalette.fill(level: 0, index: index)
            let usage = partition.spaceUsage
            let children = containerNodes(
                for: partition,
                parentBytes: partition.sizeBytes,
                containerCount: &containerCount,
                volumeCount: &volumeCount)
            nodes.append(HierarchyNode(
                id: "partition:\(partition.deviceIdentifier)",
                itemID: partition.deviceIdentifier,
                role: .partition,
                label: displayName(partition),
                detail: partition.mountPoint,
                kindLabel: "Partition",
                fileSystem: partition.fileSystem
                    ?? partition.children.first?.fileSystem,
                bytes: partition.sizeBytes,
                capacityBytes: partition.sizeBytes,
                usedBytes: usage.usedBytes,
                freeBytes: usage.freeBytes,
                fraction: Double(partition.sizeBytes) / Double(max(denominator, 1)),
                color: color,
                children: children))
        }

        if scope.sizeBytes > accounted {
            let other = scope.sizeBytes - accounted
            nodes.append(HierarchyNode(
                id: "unallocated:\(scope.deviceIdentifier)",
                itemID: nil,
                role: .unallocated,
                label: "Other",
                detail: nil,
                kindLabel: "Not allocated",
                fileSystem: nil,
                bytes: other,
                capacityBytes: nil,
                usedBytes: nil,
                freeBytes: nil,
                fraction: Double(other) / Double(max(denominator, 1)),
                color: DiskPalette.unallocated,
                children: []))
        }
        return nodes
    }

    private func containerNodes(for partition: KBDiskItem,
                                parentBytes: UInt64,
                                containerCount: inout Int,
                                volumeCount: inout Int) -> [HierarchyNode] {
        let containers = partition.children
            .filter { $0.kind == .apfsContainer && $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        guard !containers.isEmpty else { return [] }

        var accounted: UInt64 = 0
        for container in containers {
            accounted = adding(accounted, container.sizeBytes)
        }
        let denominator = max(parentBytes, accounted)
        var nodes: [HierarchyNode] = []

        for container in containers {
            let color = DiskPalette.fill(level: 1, index: containerCount)
            containerCount += 1
            let usage = container.spaceUsage
            let volumes = container.children.filter { $0.kind == .apfsVolume }
            nodes.append(HierarchyNode(
                id: "container:\(container.deviceIdentifier)",
                itemID: container.deviceIdentifier,
                role: .container,
                label: displayName(container),
                detail: "\(volumes.count) volume\(volumes.count == 1 ? "" : "s")",
                kindLabel: "APFS container",
                fileSystem: container.fileSystem,
                bytes: container.sizeBytes,
                capacityBytes: container.sizeBytes,
                usedBytes: usage.usedBytes,
                freeBytes: usage.freeBytes,
                fraction: Double(container.sizeBytes) / Double(max(denominator, 1)),
                color: color,
                children: volumeNodes(for: container,
                                      volumeCount: &volumeCount)))
        }

        if parentBytes > accounted {
            let other = parentBytes - accounted
            nodes.append(HierarchyNode(
                id: "unallocated:\(partition.deviceIdentifier)",
                itemID: nil,
                role: .unallocated,
                label: "Other",
                detail: nil,
                kindLabel: "Not allocated",
                fileSystem: nil,
                bytes: other,
                capacityBytes: nil,
                usedBytes: nil,
                freeBytes: nil,
                fraction: Double(other) / Double(max(denominator, 1)),
                color: DiskPalette.unallocated,
                children: []))
        }
        return nodes
    }

    private func volumeNodes(for container: KBDiskItem,
                             volumeCount: inout Int) -> [HierarchyNode] {
        guard let context = inventory.apfsSpaceContext(for: container) else {
            return []
        }

        var nodes: [HierarchyNode] = []
        var represented = Set<String>()

        for segment in context.segments where segment.fraction > 0 {
            let id = "\(container.deviceIdentifier):\(segment.id)"
            let role: SliceRole
            switch segment.role {
            case .volume: role = .volume
            case .container: role = .container
            case .free: role = .free
            case .residual: role = .residual
            case .unknown: role = .unknown
            }

            let color: Color
            switch role {
            case .volume:
                color = DiskPalette.fill(level: 2, index: volumeCount)
                volumeCount += 1
            case .free:
                color = DiskPalette.free
            case .residual:
                color = DiskPalette.residual
            case .unknown:
                color = DiskPalette.unknown
            case .container:
                color = DiskPalette.fill(level: 1, index: 0)
            case .partition, .unallocated, .used:
                color = DiskPalette.unallocated
            }

            let segmentItem = inventory.allItems
                .first { $0.deviceIdentifier == segment.itemID }
            let detail = segmentItem?.mountPoint
            let kindLabel: String
            switch role {
            case .volume: kindLabel = "APFS volume"
            case .container: kindLabel = "APFS container"
            case .free: kindLabel = "Free space"
            case .residual: kindLabel = "Snapshots & metadata"
            case .unknown: kindLabel = "Usage unknown"
            case .partition: kindLabel = "Partition"
            case .unallocated: kindLabel = "Not allocated"
            case .used: kindLabel = "Used"
            }
            let fileSystem = (role == .volume || role == .container)
                ? segmentItem?.fileSystem : nil

            nodes.append(HierarchyNode(
                id: id,
                itemID: segment.itemID,
                role: role,
                label: segment.label,
                detail: detail,
                kindLabel: kindLabel,
                fileSystem: fileSystem,
                bytes: segment.bytes,
                capacityBytes: role == .volume ? context.totalBytes : nil,
                usedBytes: role == .volume ? segment.bytes : nil,
                freeBytes: nil,
                fraction: segment.fraction,
                color: color,
                children: []))
            if let itemID = segment.itemID {
                represented.insert(itemID)
            }
        }

        // Unmounted or empty volumes have no arc; keep them selectable from
        // the legend.
        let missing = container.children
            .filter { $0.kind == .apfsVolume }
            .filter { !represented.contains($0.deviceIdentifier) }
        for volume in missing {
            nodes.append(HierarchyNode(
                id: "legend:\(container.deviceIdentifier):\(volume.deviceIdentifier)",
                itemID: volume.deviceIdentifier,
                role: .volume,
                label: displayName(volume),
                detail: volume.mountPoint,
                kindLabel: "APFS volume",
                fileSystem: volume.fileSystem,
                bytes: volume.usedBytes ?? 0,
                capacityBytes: context.totalBytes,
                usedBytes: volume.usedBytes,
                freeBytes: nil,
                fraction: 0,
                color: DiskPalette.fill(level: 2, index: volumeCount),
                children: []))
            volumeCount += 1
        }
        return nodes
    }

    /// Fallback for a disk/partition without any APFS container: used vs free.
    private func usageNodes(for item: KBDiskItem) -> [HierarchyNode] {
        let usage = item.spaceUsage
        guard let used = usage.usedBytes else { return [] }
        let free = usage.freeBytes ?? 0
        let total = max(adding(used, free), 1)

        var nodes: [HierarchyNode] = [
            HierarchyNode(
                id: "used:\(item.deviceIdentifier)",
                itemID: nil,
                role: .used,
                label: "Used",
                detail: nil,
                kindLabel: "Used",
                fileSystem: item.fileSystem,
                bytes: used,
                capacityBytes: item.sizeBytes,
                usedBytes: used,
                freeBytes: nil,
                fraction: Double(used) / Double(total),
                color: DiskPalette.fill(level: 0, index: 0),
                children: [])
        ]
        if free > 0 {
            nodes.append(HierarchyNode(
                id: "free:\(item.deviceIdentifier)",
                itemID: nil,
                role: .free,
                label: "Free",
                detail: nil,
                kindLabel: "Free space",
                fileSystem: nil,
                bytes: free,
                capacityBytes: nil,
                usedBytes: nil,
                freeBytes: nil,
                fraction: Double(free) / Double(total),
                color: DiskPalette.free,
                children: []))
        }
        return nodes
    }

    private func highlightID(in nodes: [HierarchyNode]) -> String? {
        if contains(item.deviceIdentifier, in: nodes) {
            return item.deviceIdentifier
        }

        let byID = {
            var map: [String: KBDiskItem] = [:]
            for entry in inventory.allItems {
                map[entry.deviceIdentifier] = entry
            }
            return map
        }()
        var current = item
        var depth = 0
        while depth < 64,
              let parentID = current.parentID,
              let parent = byID[parentID] {
            if contains(parent.deviceIdentifier, in: nodes) {
                return parent.deviceIdentifier
            }
            current = parent
            depth += 1
        }
        return nil
    }

    private func contains(_ identifier: String, in nodes: [HierarchyNode]) -> Bool {
        nodes.contains { node in
            node.itemID == identifier || contains(identifier, in: node.children)
        }
    }

    private func displayName(_ item: KBDiskItem) -> String {
        item.name.isEmpty ? item.deviceIdentifier : item.name
    }

    private func adding(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }

    private func icon(for kind: KBDiskItemKind) -> String {
        switch kind {
        case .physicalDisk: return "internaldrive"
        case .partition: return "square.split.2x1"
        case .apfsContainer: return "square.stack.3d.up"
        case .apfsVolume: return "externaldrive.fill"
        case .snapshot: return "clock.arrow.circlepath"
        }
    }

    // MARK: - Layout

    private enum SliceRole: String {
        case partition
        case container
        case volume
        case residual
        case free
        case unallocated
        case used
        case unknown

        var isSelectable: Bool {
            self == .partition || self == .container || self == .volume
        }
    }

    private struct HierarchyNode: Identifiable {
        let id: String
        let itemID: String?
        let role: SliceRole
        let label: String
        let detail: String?
        let kindLabel: String?
        let fileSystem: String?
        let bytes: UInt64
        let capacityBytes: UInt64?
        let usedBytes: UInt64?
        let freeBytes: UInt64?
        /// Share of the parent's angular span (0...1).
        let fraction: Double
        let color: Color
        let children: [HierarchyNode]
    }

    private struct Sector: Identifiable {
        let id: String
        let node: HierarchyNode
        let depth: Int
        /// 0 = partitions, 1 = containers, 2 = volumes.
        let level: Int
        let startAngle: Double
        let endAngle: Double
        let innerRadius: CGFloat
        let outerRadius: CGFloat

        var globalFraction: Double {
            (endAngle - startAngle) / (2 * Double.pi)
        }
    }

    private struct Callout: Identifiable {
        let id: String
        let node: HierarchyNode
        let text: String
        let anchor: CGPoint
        let outerEdge: CGPoint
        let elbowX: CGFloat
        let textPoint: CGPoint
        let textRect: CGRect
        let rightSide: Bool
    }

    private struct Layout {
        let sectors: [Sector]
        let callouts: [Callout]
        let center: CGPoint
        let centerRadius: CGFloat
        let maxRadius: CGFloat
        let side: CGFloat
    }

    private func makeLayout(nodes: [HierarchyNode], in size: CGSize,
                            baseLevel: Int) -> Layout {
        let minGutter: CGFloat = isMaximized ? 56 : 46
        let gutteredSide = min(size.height,
                               max(0, size.width - 2 * minGutter))
        let guttered = gutteredSide >= 240
            && (size.width - gutteredSide) / 2 >= 32
        let side = guttered ? gutteredSide
                            : min(size.width, size.height)
        let gutter = max(0, (size.width - side) / 2)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = max(0, side / 2 - 10)
        let centerRadius = max(60,
                               min(isMaximized ? 100 : 66, side * 0.15))
        let rings = max(1, depth(of: nodes))
        let ringWidth = max(0, (maxRadius - centerRadius) / CGFloat(rings))

        var sectors: [Sector] = []
        append(nodes, depth: 0,
               start: -Double.pi / 2,
               end: 3 * Double.pi / 2,
               centerRadius: centerRadius,
               ringWidth: ringWidth,
               baseLevel: baseLevel,
               sectors: &sectors)

        let callouts = guttered
            ? makeCallouts(sectors: sectors, size: size, center: center,
                           maxRadius: maxRadius, gutter: gutter)
            : []
        return Layout(sectors: sectors, callouts: callouts, center: center,
                      centerRadius: centerRadius,
                      maxRadius: maxRadius, side: side)
    }

    private func makeCallouts(sectors: [Sector], size: CGSize,
                              center: CGPoint, maxRadius: CGFloat,
                              gutter: CGFloat) -> [Callout] {
        let textBudget = max(24, gutter - 4)
        let nameSize: CGFloat = isMaximized ? 9.5 : 8.5

        struct Candidate {
            let sector: Sector
            let text: String
            let mid: Double
            let idealY: CGFloat
            var rightSide: Bool
            let fraction: Double
        }

        var candidates: [Candidate] = []
        for sector in sectors {
            guard !canDrawInside(sector) else { continue }
            let span = sector.endAngle - sector.startAngle
            guard span >= 0.001 else { continue }
            let text = truncatedCallout(calloutText(for: sector.node),
                                        maxWidth: textBudget,
                                        size: nameSize)
            guard !text.isEmpty else { continue }
            let mid = (sector.startAngle + sector.endAngle) / 2
            candidates.append(Candidate(
                sector: sector,
                text: text,
                mid: mid,
                idealY: center.y + CGFloat(sin(mid)) * (maxRadius + 8),
                rightSide: cos(mid) >= 0,
                fraction: span / (2 * Double.pi)))
        }

        // Slices near the top or bottom are nearly vertical: spread them over
        // both gutters instead of piling every label on one side.
        var leftCount = candidates.filter {
            !$0.rightSide && abs(cos($0.mid)) > 0.15
        }.count
        var rightCount = candidates.filter {
            $0.rightSide && abs(cos($0.mid)) > 0.15
        }.count
        for index in candidates.indices
        where abs(cos(candidates[index].mid)) <= 0.15 {
            if leftCount <= rightCount {
                candidates[index].rightSide = false
                leftCount += 1
            } else {
                candidates[index].rightSide = true
                rightCount += 1
            }
        }

        var result: [Callout] = []
        let minY: CGFloat = 12
        let maxY = max(minY, size.height - 12)

        for right in [false, true] {
            var side = candidates
                .filter { $0.rightSide == right }
                .sorted { $0.idealY < $1.idealY }

            while !side.isEmpty {
                guard let ys = distributedYs(side.map(\.idealY),
                                             minY: minY, maxY: maxY,
                                             spacing: isMaximized ? 16 : 13) else {
                    let drop = side.indices.min {
                        side[$0].fraction < side[$1].fraction
                    }!
                    side.remove(at: drop)
                    continue
                }

                let elbowX = center.x + (right ? 1 : -1) * (maxRadius + 8)
                let textX = elbowX + (right ? 4 : -4)
                for (candidate, y) in zip(side, ys) {
                    let mid = (candidate.sector.startAngle
                               + candidate.sector.endAngle) / 2
                    let anchorRadius = min(candidate.sector.outerRadius,
                                           maxRadius)
                    let anchor = point(center: center, radius: anchorRadius,
                                       angle: mid)
                    let outerEdge = point(center: center, radius: maxRadius,
                                          angle: mid)
                    let width = textWidth(candidate.text, size: nameSize,
                                          weight: .semibold)
                    let rect = right
                        ? CGRect(x: textX - 2, y: y - 9,
                                 width: width + 4, height: 18)
                        : CGRect(x: textX - width - 2, y: y - 9,
                                 width: width + 4, height: 18)
                    result.append(Callout(
                        id: "callout:\(candidate.sector.id)",
                        node: candidate.sector.node,
                        text: candidate.text,
                        anchor: anchor,
                        outerEdge: outerEdge,
                        elbowX: elbowX,
                        textPoint: CGPoint(x: textX, y: y),
                        textRect: rect,
                        rightSide: right))
                }
                break
            }
        }
        return result
    }

    private func distributedYs(_ ideal: [CGFloat], minY: CGFloat,
                               maxY: CGFloat, spacing: CGFloat) -> [CGFloat]? {
        guard !ideal.isEmpty else { return [] }
        var ys = ideal.map { min(max($0, minY), maxY) }
        for index in 1..<ys.count {
            ys[index] = max(ys[index], ys[index - 1] + spacing)
        }
        if let last = ys.last, last > maxY {
            ys[ys.count - 1] = maxY
            if ys.count > 1 {
                for index in stride(from: ys.count - 2, through: 0, by: -1) {
                    ys[index] = min(ys[index], ys[index + 1] - spacing)
                }
            }
        }
        return (ys.first ?? minY) >= minY ? ys : nil
    }

    private func truncatedCallout(_ text: String, maxWidth: CGFloat,
                                  size: CGFloat) -> String {
        if textWidth(text, size: size, weight: .semibold) <= maxWidth {
            return text
        }
        var candidate = text
        while !candidate.isEmpty {
            candidate.removeLast()
            let value = candidate + "…"
            if textWidth(value, size: size, weight: .semibold) <= maxWidth {
                return value
            }
        }
        return ""
    }

    private func calloutText(for node: HierarchyNode) -> String {
        switch node.role {
        case .partition, .container:
            return node.itemID ?? node.label
        case .volume:
            return node.label
        case .free:
            return "Free"
        case .residual:
            return node.label.hasPrefix("Snapshots")
                ? "Snapshots" : "Metadata"
        case .unallocated:
            return "Other"
        case .unknown:
            return "Unknown"
        case .used:
            return "Used"
        }
    }

    private func point(center: CGPoint, radius: CGFloat,
                       angle: Double) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius)
    }

    private func baseLevel(for kind: KBDiskItemKind) -> Int {
        switch kind {
        case .physicalDisk: return 0
        case .partition: return 1
        case .apfsContainer: return 2
        case .apfsVolume, .snapshot: return 2
        }
    }

    private func depth(of nodes: [HierarchyNode]) -> Int {
        nodes.map { 1 + depth(of: $0.children) }.max() ?? 0
    }

    private func level(for role: SliceRole) -> Int? {
        switch role {
        case .partition: return 0
        case .container: return 1
        case .volume: return 2
        case .free, .residual, .unallocated, .used, .unknown: return nil
        }
    }

    private func append(_ nodes: [HierarchyNode], depth: Int,
                        start: Double, end: Double,
                        centerRadius: CGFloat, ringWidth: CGFloat,
                        baseLevel: Int,
                        sectors: inout [Sector]) {
        let inner = centerRadius + CGFloat(depth) * ringWidth
        let outer = inner + ringWidth
        let ringLevel = nodes.compactMap { level(for: $0.role) }.first
            ?? baseLevel
        var angle = start

        for node in nodes {
            let span = (end - start) * node.fraction
            guard span > 0.0005 else { continue }
            let nodeLevel = level(for: node.role) ?? ringLevel

            sectors.append(Sector(
                id: "\(node.id)|\(depth)",
                node: node,
                depth: depth,
                level: nodeLevel,
                startAngle: angle,
                endAngle: angle + span,
                innerRadius: inner,
                outerRadius: outer))

            if !node.children.isEmpty {
                append(node.children, depth: depth + 1,
                       start: angle, end: angle + span,
                       centerRadius: centerRadius, ringWidth: ringWidth,
                       baseLevel: nodeLevel,
                       sectors: &sectors)
            }
            angle += span
        }
    }

    // MARK: - Drawing

    private func draw(layout: Layout, highlightID: String?,
                      context: inout GraphicsContext) {
        for sector in layout.sectors {
            let node = sector.node
            let content = DiskPalette.contentColor(on: node.color)
            let separator = content.opacity(0.18)
            let ancestorStroke = content.opacity(0.35)
            let hoverStroke = content.opacity(0.65)
            let hovered = hoveredNodeID == node.id
            let selected = node.itemID != nil && node.itemID == highlightID
            let ancestor = !selected && containsSelection(node, highlightID: highlightID)

            let path = sectorPath(sector, center: layout.center)
            context.fill(path, with: .color(node.color))
            context.stroke(path, with: .color(separator), lineWidth: 0.3)

            drawLevelBand(sector, layout: layout, context: &context)

            if selected {
                context.stroke(
                    path,
                    with: .color(DiskPalette.contentColor(on: node.color)),
                    lineWidth: 3)
            } else if ancestor {
                context.stroke(path, with: .color(ancestorStroke),
                               lineWidth: 0.75)
            }
            if hovered && !selected {
                context.stroke(path, with: .color(hoverStroke),
                               lineWidth: 1.0)
            }

            drawLabel(sector, layout: layout, context: &context)
        }

        let centerRect = CGRect(
            x: layout.center.x - layout.centerRadius,
            y: layout.center.y - layout.centerRadius,
            width: layout.centerRadius * 2,
            height: layout.centerRadius * 2)
        let centerPath = Path(ellipseIn: centerRect)
        context.fill(centerPath, with: .color(Color(nsColor: .controlBackgroundColor)))
        let centerTint = DiskPalette.tint(for: item.kind)
        context.stroke(centerPath, with: .color(centerTint.opacity(0.85)),
                       lineWidth: 1.0)

        drawCallouts(layout, highlightID: highlightID, context: &context)
    }

    private func drawCallouts(_ layout: Layout, highlightID: String?,
                              context: inout GraphicsContext) {
        for callout in layout.callouts {
            let active = callout.node.id == hoveredNodeID
                || (callout.node.itemID != nil
                    && callout.node.itemID == highlightID)

            if callout.anchor != callout.outerEdge {
                var radial = Path()
                radial.move(to: callout.anchor)
                radial.addLine(to: callout.outerEdge)
                context.stroke(
                    radial,
                    with: .color(.secondary.opacity(0.40)),
                    style: StrokeStyle(lineWidth: 1,
                                       lineCap: .round,
                                       dash: [2, 2]))
            }

            var line = Path()
            line.move(to: callout.outerEdge)
            line.addLine(to: CGPoint(x: callout.elbowX,
                                     y: callout.textPoint.y))
            line.addLine(to: callout.textPoint)
            context.stroke(line, with: .color(.secondary.opacity(0.45)),
                           lineWidth: 1)

            let dotRect = CGRect(x: callout.anchor.x - 1.5,
                                 y: callout.anchor.y - 1.5,
                                 width: 3, height: 3)
            let dotColor = DiskPalette.bandColor(on: callout.node.color)
            context.fill(Path(ellipseIn: dotRect),
                         with: .color(dotColor))

            let text = context.resolve(
                Text(callout.text)
                    .font(.system(size: isMaximized ? 9.5 : 8.5,
                                  weight: active ? .semibold : .regular))
                    .foregroundColor(.primary.opacity(active ? 0.95 : 0.75)))
            context.draw(text, at: callout.textPoint,
                         anchor: callout.rightSide ? .leading : .trailing)
        }
    }

    private func drawLevelBand(_ sector: Sector, layout: Layout,
                               context: inout GraphicsContext) {
        let span = sector.endAngle - sector.startAngle
        guard span >= 0.02 else { return }

        let width: CGFloat = isMaximized ? 0.8 : 0.6
        let radius = max(0, sector.outerRadius - width / 2 - 0.5)
        let epsilon = min(0.012, span * 0.2, 1.2 / max(radius, 1))
        var path = Path()
        path.addArc(center: layout.center, radius: radius,
                    startAngle: .radians(sector.startAngle + epsilon),
                    endAngle: .radians(sector.endAngle - epsilon),
                    clockwise: false)

        let band = DiskPalette.bandColor(on: sector.node.color)
        let opacity = sector.node.role.isSelectable ? 1.0 : 0.7
        context.stroke(
            path,
            with: .color(band.opacity(opacity)),
            style: StrokeStyle(lineWidth: width, lineCap: .butt))
    }

    private func sectorPath(_ sector: Sector, center: CGPoint) -> Path {
        var path = Path()
        path.addArc(center: center, radius: sector.outerRadius,
                    startAngle: .radians(sector.startAngle),
                    endAngle: .radians(sector.endAngle), clockwise: false)
        path.addArc(center: center, radius: sector.innerRadius,
                    startAngle: .radians(sector.endAngle),
                    endAngle: .radians(sector.startAngle), clockwise: true)
        path.closeSubpath()
        return path
    }

    private func containsSelection(_ node: HierarchyNode,
                                   highlightID: String?) -> Bool {
        guard let highlightID else { return false }
        return nodeContains(node, identifier: highlightID)
    }

    private func nodeContains(_ node: HierarchyNode,
                              identifier: String) -> Bool {
        node.itemID == identifier
            || node.children.contains {
                nodeContains($0, identifier: identifier)
            }
    }

    private var labelNameSize: CGFloat { isMaximized ? 11.5 : 9.5 }
    private var labelValueSize: CGFloat { isMaximized ? 9.5 : 8 }

    /// Single source of truth for inside labels and callout generation, so a
    /// slice never gets both or neither.
    private func canDrawInside(_ sector: Sector) -> Bool {
        let span = sector.endAngle - sector.startAngle
        guard span >= (isMaximized ? 0.12 : 0.16),
              sector.outerRadius - sector.innerRadius >= 20 else {
            return false
        }
        let radius = (sector.innerRadius + sector.outerRadius) / 2
        let chord = 2 * radius * sin(span / 2)
        let available = span >= Double.pi ? 2 * radius - 8 : chord
        let name = labelText(sector.node)
        return textWidth(name, size: labelNameSize, weight: .semibold) + 4
            <= available
    }

    private func drawLabel(_ sector: Sector, layout: Layout,
                           context: inout GraphicsContext) {
        guard canDrawInside(sector) else { return }

        let span = sector.endAngle - sector.startAngle
        let node = sector.node
        let middle = (sector.startAngle + sector.endAngle) / 2
        let radius = (sector.innerRadius + sector.outerRadius) / 2
        let chord = 2 * radius * sin(span / 2)
        let nameSize = labelNameSize
        let valueSize = labelValueSize

        let name = labelText(node)
        let value = KBFormat.bytes(node.bytes, units: byteUnitSystem)
        let nameWidth = textWidth(name, size: nameSize,
                                  weight: .semibold)
        let valueWidth = textWidth(value, size: valueSize,
                                   weight: .regular)
        // For arcs above a half circle the chord shrinks again; use the ring
        // width at the label radius as the available room instead.
        let available = span >= Double.pi ? 2 * radius - 8 : chord
        guard nameWidth + 4 <= available else { return }

        let contentColor = DiskPalette.contentColor(on: node.color)
        let point = CGPoint(
            x: layout.center.x + cos(middle) * radius,
            y: layout.center.y + sin(middle) * radius)

        let nameText = context.resolve(
            Text(name)
                .font(.system(size: nameSize, weight: .semibold))
                .foregroundColor(contentColor))
        context.draw(nameText,
                     at: CGPoint(x: point.x,
                                 y: point.y - (isMaximized ? 6 : 5)),
                     anchor: .center)

        if valueWidth + 4 <= available {
            let valueText = context.resolve(
                Text(value)
                    .font(.system(size: valueSize))
                    .foregroundColor(contentColor))
            context.draw(valueText,
                         at: CGPoint(x: point.x,
                                     y: point.y + (isMaximized ? 7 : 6)),
                         anchor: .center)
        }
    }

    private func labelText(_ node: HierarchyNode) -> String {
        switch node.role {
        case .partition, .container:
            return node.itemID ?? node.label
        default:
            return node.label
        }
    }

    private func textWidth(_ text: String, size: CGFloat,
                           weight: NSFont.Weight) -> CGFloat {
        (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight)
        ]).width
    }

    // MARK: - Hit testing

    private func hoveredSector(in layout: Layout) -> Sector? {
        guard let chartHoverNodeID else { return nil }
        return layout.sectors.first { $0.node.id == chartHoverNodeID }
    }

    private func callout(at location: CGPoint, in layout: Layout) -> Callout? {
        layout.callouts.first { $0.textRect.contains(location) }
    }

    private func isInsideCenter(_ location: CGPoint,
                                in layout: Layout) -> Bool {
        let dx = location.x - layout.center.x
        let dy = location.y - layout.center.y
        return dx * dx + dy * dy
            <= layout.centerRadius * layout.centerRadius
    }

    private func sector(at location: CGPoint, in layout: Layout) -> Sector? {
        let dx = location.x - layout.center.x
        let dy = location.y - layout.center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= layout.centerRadius,
              distance <= layout.maxRadius else { return nil }

        var angle = atan2(dy, dx)
        if angle < -Double.pi / 2 {
            angle += 2 * Double.pi
        }

        return layout.sectors.first { sector in
            distance >= sector.innerRadius
                && distance <= sector.outerRadius
                && angle >= sector.startAngle
                && angle < sector.endAngle
        }
    }
}

private struct VerticalUsageBar: View {
    let fraction: Double?
    let tint: Color
    let kindLabel: String?
    let caption: String?
    let height: CGFloat
    let width: CGFloat
    let isMaximized: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double {
        guard let fraction, fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    private var percentText: String {
        fraction == nil ? "—" : KBFormat.percent(clamped)
    }

    var body: some View {
        VStack(spacing: 5) {
            if let kindLabel {
                Text(kindLabel)
                    .font(.system(size: 7.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: width)
            }
            Text(percentText)
                .font(.system(size: isMaximized ? 14 : 12,
                              weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(fraction == nil ? .secondary : .primary)

            GeometryReader { proxy in
                let trackHeight = proxy.size.height
                let fillHeight = max(0, trackHeight * clamped)
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(.quaternary.opacity(0.30))

                    if clamped > 0 {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [tint.opacity(0.85), tint],
                                startPoint: .bottom,
                                endPoint: .top))
                            .frame(height: fillHeight)
                            .shadow(color: tint.opacity(0.35),
                                    radius: 5, y: -1)
                            .overlay(alignment: .top) {
                                Capsule()
                                    .fill(.white.opacity(0.55))
                                    .frame(height: 2)
                                    .padding(.horizontal, 4)
                            }
                    }

                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(.primary.opacity(0.08))
                                .frame(height: 1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(DiskPalette.ink.opacity(0.28),
                                      lineWidth: 0.5)
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.4),
                           value: clamped)
            }
            .frame(width: isMaximized ? 24 : 20, height: height)

            Text(caption ?? "")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: width)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kindLabel.map { "\($0) capacity used" }
                            ?? "Capacity used")
        .accessibilityValue(fraction == nil ? "Unknown" : percentText)
    }
}
