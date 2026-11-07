import AppKit
import SwiftUI
import KancerberoCore

/// One big number shown beside the chart.
struct VolumeHierarchyStat: Identifiable {
    let id: String
    let title: String
    let value: String
}

/// Nested treemap of the selected disk: partitions → APFS containers →
/// volumes. The scope always climbs to the physical disk so the shape stays
/// stable while the user selects different items; the selected item is
/// outlined in its rectangle.
struct VolumeHierarchyChart: View {
    let item: KBDiskItem
    let inventory: KBDiskInventorySnapshot
    var isMaximized = false
    var onSelectItem: ((String) -> Void)? = nil
    var stats: [VolumeHierarchyStat] = []
    var usageFraction: Double? = nil
    var usageCaption: String? = nil
    var notes: [String] = []
    /// Height of the detail-card viewport. The chart and the bar are capped
    /// to it so the bar stays fully visible when the window shrinks.
    var availableHeight: CGFloat? = nil
    @Binding var selectedFreeContainerID: String?
    @Binding var detailSelectionHidden: Bool

    @Environment(\.byteUnitSystem) private var byteUnitSystem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredNodeID: String?

    var body: some View {
        let scope = scopeItem(in: inventory)
        let nodes = makeNodes(for: scope)
        let highlightID = highlightID(in: nodes)

        // The treemap keeps its original adaptive height. Only the bar is
        // capped to the window so it stays fully visible when resizing.
        let treemapHeight = adaptiveTreemapHeight(for: nodes)
        let desiredBarHeight = (treemapHeight * 0.8).rounded()
        let maxBarHeight = availableHeight.map { max(180, $0 - 145) }
            ?? desiredBarHeight
        let trackHeight = min(desiredBarHeight, maxBarHeight)
        HStack(alignment: .top, spacing: chartColumnSpacing) {
            heroInfo(trackHeight: trackHeight)
            treemap(nodes: nodes, scope: scope,
                    highlightID: detailSelectionHidden ? nil : highlightID)
                .frame(height: treemapHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25),
                   value: item.deviceIdentifier)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25),
                   value: selectedFreeContainerID)
        .onChange(of: item.deviceIdentifier) { _, _ in
            selectedFreeContainerID = nil
            detailSelectionHidden = false
        }
    }

    // MARK: - Hero

    private var chartColumnSpacing: CGFloat { isMaximized ? 10 : 6 }

    private var statsWidth: CGFloat { isMaximized ? 150 : 130 }
    private var heroSpacing: CGFloat { isMaximized ? 12 : 6 }
    private var barWidth: CGFloat { isMaximized ? 72 : 64 }
    private var columnSpacing: CGFloat { isMaximized ? 14 : 11 }
    private var statValueSize: CGFloat { isMaximized ? 24 : 20 }

    private func heroInfo(trackHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: heroSpacing) {
            statsColumn(trackHeight: trackHeight)
            VerticalUsageBar(
                slices: barSlices,
                fraction: usageFraction,
                tint: DiskPalette.tint(for: item.kind),
                kindLabel: gaugeKindLabel(for: item.kind),
                caption: usageCaption,
                height: trackHeight,
                width: barWidth,
                isMaximized: isMaximized,
                onSliceTap: handleBarTap)
        }
        .fixedSize(horizontal: true, vertical: false)
        .overlayPreferenceValue(UsedLeaderAnchorKey.self) { anchors in
            GeometryReader { proxy in
                Canvas { context, _ in
                    guard let anchor = anchors["used"] else { return }
                    let rect = proxy[anchor]
                    let start = CGPoint(x: rect.maxX + 4, y: rect.midY)
                    let endX = statsWidth + heroSpacing + 1
                    guard endX > start.x else { return }
                    let color = Color(.sRGB, red: 0.30, green: 0.66,
                                      blue: 0.92, opacity: 0.85)
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: CGPoint(x: endX, y: start.y))
                    context.stroke(
                        path, with: .color(color),
                        style: StrokeStyle(lineWidth: 1,
                                           lineCap: .round))
                    let dot = CGRect(x: endX - 1.6, y: start.y - 1.6,
                                     width: 3.2, height: 3.2)
                    context.fill(Path(ellipseIn: dot),
                                 with: .color(color))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A hidden detail selection comes back when the bar is clicked; with a
    /// visible selection, clicking a highlighted segment hides it.
    private func handleBarTap(_ slice: VolumeBarSlice) {
        if detailSelectionHidden {
            detailSelectionHidden = false
            return
        }
        guard slice.isHighlighted else { return }
        if selectedFreeContainerID != nil {
            selectedFreeContainerID = nil
        } else {
            detailSelectionHidden = true
        }
    }

    /// Distance from the hero top to the top of the bar: the kind label and
    /// percentage sit above the capsule inside the bar column.
    private var barTopOffset: CGFloat {
        labelLineHeight(7.5) + 5
            + labelLineHeight(isMaximized ? 14 : 12) + 5
    }

    private var statRowHeight: CGFloat {
        labelLineHeight(9.5) + 1 + labelLineHeight(statValueSize)
    }

    /// Offset of the value line inside a stat row, used to align Used with
    /// the selected bar portion.
    private var usedValueMidOffset: CGFloat {
        labelLineHeight(9.5) + 1 + labelLineHeight(statValueSize) / 2
    }

    /// Top offset of the Used row so its value sits at the selected bar
    /// portion. It never overlaps Capacity and Free.
    private func usedRowTop(trackHeight: CGFloat) -> CGFloat {
        let minimumTop = statRowHeight * 2 + columnSpacing * 2
        // A free-space selection is highlighted in the bar but has no Used
        // leader: the Used value keeps its normal position.
        guard !detailSelectionHidden,
              selectedFreeContainerID == nil,
              let center = VolumeBarLayout.selectedCenterY(
                  for: barSlices, height: trackHeight,
                  isMaximized: isMaximized) else {
            return minimumTop
        }
        let target = barTopOffset + center - usedValueMidOffset
        return max(minimumTop, target)
    }

    /// Capacity and Free stay at the top; Used travels to the selected bar
    /// portion and gets a horizontal leader line.
    private func statsColumn(trackHeight: CGFloat) -> some View {
        let capacity = stats.first { $0.id == "capacity" }
        let free = stats.first { $0.id == "free" }
        let used = stats.first { $0.id == "used" }
        let usedTop = usedRowTop(trackHeight: trackHeight)
        let freeBottom = statRowHeight * 2 + columnSpacing
        let spacer = max(0, usedTop - freeBottom)
        return VStack(alignment: .leading, spacing: 0) {
            if let capacity {
                statRow(capacity)
            }
            Color.clear.frame(height: columnSpacing)
            if let free {
                statRow(free)
            }
            Color.clear.frame(height: spacer)
            if let used {
                statRow(used,
                        anchorID: !detailSelectionHidden
                            && selectedFreeContainerID == nil
                            ? "used" : nil)
            }
            Color.clear.frame(height: columnSpacing)
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: isMaximized ? 11 : 10))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: statsWidth, alignment: .leading)
    }

    private func statRow(_ stat: VolumeHierarchyStat,
                         anchorID: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(stat.title)
                .font(.system(size: 9.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(stat.value)
                .font(.system(size: statValueSize, weight: .semibold,
                              design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .anchorPreference(key: UsedLeaderAnchorKey.self,
                                  value: .bounds) { anchor in
                    anchorID.map { [$0: anchor] } ?? [:]
                }
        }
    }

    /// A leaf block of the depth-first bar view: an APFS volume or a
    /// container's free space.
    private struct BarBlock {
        let id: String
        let ownerID: String
        let containerID: String
        let bytes: UInt64
        let isFree: Bool
    }

    /// The bar always shows the deepest blocks of the disk being viewed
    /// (volumes plus each container's free space), independently of which
    /// element is selected. The selection only changes the outline.
    private var barSlices: [VolumeBarSlice] {
        let scope = scopeItem(in: inventory)
        let blocks = barBlocks(for: scope)
        guard !blocks.isEmpty else { return [] }

        let selectedIDs = selectedSubtreeIDs()
        let total = blocks.reduce(0.0) { $0 + Double($1.bytes) }
        return blocks.map { block in
            let fraction = total > 0
                ? Double(block.bytes) / total : 0
            let highlighted: Bool
            if detailSelectionHidden {
                highlighted = false
            } else if let selectedFreeContainerID {
                highlighted = block.isFree
                    && block.containerID == selectedFreeContainerID
            } else {
                highlighted = block.isFree
                    ? selectedIDs.contains(block.containerID)
                    : selectedIDs.contains(block.ownerID)
            }
            return VolumeBarSlice(
                id: block.id,
                fraction: fraction,
                isFree: block.isFree,
                isHighlighted: highlighted)
        }
    }

    /// The selected element and all of its descendants. A block is outlined
    /// when its volume (or the container that owns a free block) is in here.
    private func selectedSubtreeIDs() -> Set<String> {
        var root = item
        if item.kind == .snapshot,
           let container = inventory.apfsContainer(enclosing: item) {
            root = container
        }
        var ids: Set<String> = []
        func visit(_ node: KBDiskItem) {
            guard ids.insert(node.deviceIdentifier).inserted else { return }
            for child in node.children { visit(child) }
        }
        visit(root)
        return ids
    }

    /// Flattens the disk hierarchy to its deepest blocks: every APFS volume
    /// plus one free-space block per container. Partitions and containers are
    /// never drawn as blocks themselves.
    private func barBlocks(for scope: KBDiskItem) -> [BarBlock] {
        var blocks: [BarBlock] = []

        func appendContainer(_ container: KBDiskItem) {
            if let context = inventory.apfsSpaceContext(for: container),
               let free = context.segments.first(where: {
                   $0.role == .free
               }), free.bytes > 0 {
                blocks.append(BarBlock(
                    id: "free:\(container.deviceIdentifier)",
                    ownerID: container.deviceIdentifier,
                    containerID: container.deviceIdentifier,
                    bytes: free.bytes,
                    isFree: true))
            }
            let volumes = container.children
                .filter { $0.kind == .apfsVolume }
                .sorted { ($0.usedBytes ?? 0) > ($1.usedBytes ?? 0) }
            for volume in volumes {
                blocks.append(BarBlock(
                    id: "volume:\(volume.deviceIdentifier)",
                    ownerID: volume.deviceIdentifier,
                    containerID: container.deviceIdentifier,
                    bytes: volume.usedBytes ?? 0,
                    isFree: false))
            }
        }

        func visit(_ node: KBDiskItem) {
            switch node.kind {
            case .apfsContainer:
                appendContainer(node)
            case .apfsVolume:
                blocks.append(BarBlock(
                    id: "volume:\(node.deviceIdentifier)",
                    ownerID: node.deviceIdentifier,
                    containerID: node.parentID ?? node.deviceIdentifier,
                    bytes: node.usedBytes ?? 0,
                    isFree: false))
            case .physicalDisk, .partition:
                for child in node.children where child.kind != .snapshot {
                    visit(child)
                }
            case .snapshot:
                break
            }
        }

        visit(scope)
        if blocks.isEmpty {
            return fallbackBarBlocks(for: scope)
        }
        return blocks
    }

    /// A disk without APFS volumes still gets blocks: its leaf partitions, or
    /// its used/free breakdown.
    private func fallbackBarBlocks(
        for scope: KBDiskItem
    ) -> [BarBlock] {
        var blocks: [BarBlock] = []

        func visit(_ node: KBDiskItem) {
            switch node.kind {
            case .physicalDisk, .partition:
                let children = node.children.filter { $0.kind != .snapshot }
                if children.isEmpty {
                    guard node.kind == .partition else { return }
                    blocks.append(BarBlock(
                        id: "partition:\(node.deviceIdentifier)",
                        ownerID: node.deviceIdentifier,
                        containerID: node.deviceIdentifier,
                        bytes: max(node.sizeBytes, 1),
                        isFree: false))
                } else {
                    for child in children { visit(child) }
                }
            case .apfsContainer, .apfsVolume:
                let prefix = node.kind == .apfsContainer
                    ? "container" : "volume"
                blocks.append(BarBlock(
                    id: "\(prefix):\(node.deviceIdentifier)",
                    ownerID: node.deviceIdentifier,
                    containerID: node.deviceIdentifier,
                    bytes: max(node.usedBytes ?? node.sizeBytes, 1),
                    isFree: false))
            case .snapshot:
                break
            }
        }

        visit(scope)
        if !blocks.isEmpty { return blocks }

        let usage = scope.spaceUsage
        let used = usage.usedBytes ?? 0
        let free = usage.freeBytes ?? 0
        if used > 0 {
            blocks.append(BarBlock(
                id: "used:\(scope.deviceIdentifier)",
                ownerID: scope.deviceIdentifier,
                containerID: scope.deviceIdentifier,
                bytes: used,
                isFree: false))
        }
        if free > 0 {
            blocks.append(BarBlock(
                id: "free:\(scope.deviceIdentifier)",
                ownerID: scope.deviceIdentifier,
                containerID: scope.deviceIdentifier,
                bytes: free,
                isFree: true))
        }
        return blocks
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

    private var headerUsageSummary: String {
        var parts: [String] = []
        if let used = headerUsedBytes {
            parts.append("\(KBFormat.bytes(used, units: byteUnitSystem)) used")
        }
        if let free = headerFreeBytes {
            parts.append("\(KBFormat.bytes(free, units: byteUnitSystem)) free")
        }
        if let fraction = item.volumeUsedFraction {
            parts.append(KBFormat.percent(fraction))
        }
        return parts.isEmpty ? "Usage unknown" : parts.joined(separator: " · ")
    }

    private var headerUsedBytes: UInt64? {
        let usage = item.spaceUsage
        if item.kind == .apfsContainer && !usage.isKnown { return nil }
        return usage.usedBytes
    }

    private var headerFreeBytes: UInt64? {
        if item.kind == .apfsVolume || item.kind == .snapshot {
            return item.freeBytes
        }
        let usage = item.spaceUsage
        if item.kind == .apfsContainer && !usage.isKnown { return nil }
        return usage.freeBytes
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

    // MARK: - Treemap

    private func treemap(nodes: [HierarchyNode], scope: KBDiskItem,
                         highlightID: String?) -> some View {
        GeometryReader { proxy in
            let layout = makeTreemap(nodes: nodes, size: proxy.size,
                                     scopeID: scope.deviceIdentifier)

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawTreemap(layout, scope: scope,
                                highlightID: highlightID,
                                diskSelected: !detailSelectionHidden
                                    && item.deviceIdentifier
                                        == scope.deviceIdentifier,
                                context: &context)
                }

                VStack(spacing: 0) {
                    treemapDiskHeader(scope)
                        .padding(.horizontal, rootInset + 8)
                        .frame(height: diskHeaderHeight, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(.top, rootInset)
                .allowsHitTesting(false)

                if layout.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 18, weight: .medium))
                        Text("Structure unavailable")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let hovered = treemapItem(at: location, in: layout)?.node.id
                    if hovered != hoveredNodeID {
                        withAnimation(reduceMotion ? nil
                                       : .easeOut(duration: 0.12)) {
                            hoveredNodeID = hovered
                        }
                    }
                case .ended:
                    withAnimation(reduceMotion ? nil
                                   : .easeOut(duration: 0.12)) {
                        hoveredNodeID = nil
                    }
                }
            }
            .highPriorityGesture(
                SpatialTapGesture().onEnded { value in
                    guard let hit = treemapItem(at: value.location, in: layout)
                    else {
                        selectedFreeContainerID = nil
                        if detailSelectionHidden
                            || item.deviceIdentifier
                                != scope.deviceIdentifier {
                            detailSelectionHidden = false
                            if item.deviceIdentifier
                                != scope.deviceIdentifier {
                                onSelectItem?(scope.deviceIdentifier)
                            }
                        } else {
                            detailSelectionHidden = true
                        }
                        return
                    }
                    if hit.node.role == .free, let ownerID = hit.ownerID {
                        detailSelectionHidden = false
                        selectedFreeContainerID =
                            selectedFreeContainerID == ownerID
                                ? nil : ownerID
                        return
                    }
                    selectedFreeContainerID = nil
                    guard hit.node.role.isSelectable,
                          let itemID = hit.node.itemID else { return }
                    if itemID == item.deviceIdentifier {
                        detailSelectionHidden.toggle()
                        return
                    }
                    detailSelectionHidden = false
                    onSelectItem?(itemID)
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Disk structure")
            .accessibilityValue(
                "\(displayName(scope)) (\(scope.deviceIdentifier)) · "
                    + "\(countsText(for: scope)) · "
                    + "Selected \(kindLine(for: item)) "
                    + "\(item.deviceIdentifier): \(headerUsageSummary)")
            .accessibilityAction(named: Text("Show disk details")) {
                selectedFreeContainerID = nil
                detailSelectionHidden = false
                onSelectItem?(scope.deviceIdentifier)
            }
        }
    }

    private var rootInset: CGFloat { isMaximized ? 13 : 10 }

    private var diskHeaderHeight: CGFloat { isMaximized ? 36 : 34 }

    private var diskContentInset: CGFloat { isMaximized ? 6 : 5 }

    private var treemapMinimumHeight: CGFloat { isMaximized ? 460 : 420 }

    private var treemapMaximumHeight: CGFloat { 860 }

    private func treemapDiskHeader(_ scope: KBDiskItem) -> some View {
        let usage = scope.spaceUsage
        let capacity = scope.sizeBytes > 0
            ? KBFormat.bytes(scope.sizeBytes, units: byteUnitSystem) : "—"
        let used = usage.usedBytes.map {
            KBFormat.bytes($0, units: byteUnitSystem)
        } ?? "—"
        let free = usage.freeBytes.map {
            KBFormat.bytes($0, units: byteUnitSystem)
        } ?? "—"
        let summary = "\(capacity) capacity · \(used) used · \(free) free"

        return HStack(spacing: 6) {
            Image(systemName: "internaldrive")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DiskPalette.textInk.opacity(0.8))
            Text(scope.deviceIdentifier)
                .font(.system(size: 11.5, weight: .semibold,
                              design: .monospaced))
                .foregroundStyle(DiskPalette.textInk)
            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DiskPalette.textInk.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk being viewed")
        .accessibilityValue(
            "\(displayName(scope)), \(scope.deviceIdentifier), \(summary)")
    }

    private func makeTreemap(nodes: [HierarchyNode],
                             size: CGSize,
                             scopeID: String) -> TreemapLayout {
        let diskRect = CGRect(
            x: rootInset,
            y: rootInset,
            width: max(0, size.width - 2 * rootInset),
            height: max(0, size.height - 2 * rootInset))
        let bounds = CGRect(
            x: diskRect.minX + diskContentInset,
            y: diskRect.minY + diskHeaderHeight,
            width: max(0, diskRect.width - 2 * diskContentInset),
            height: max(0, diskRect.height - diskHeaderHeight
                - diskContentInset))
        var items: [TreemapItem] = []
        layoutTreemap(nodes, in: bounds, depth: 0, axis: .rows,
                      path: "", parentFraction: 1,
                      ownerID: scopeID, items: &items)
        return TreemapLayout(bounds: bounds, items: items,
                             diskRect: diskRect,
                             diskHeaderHeight: diskHeaderHeight)
    }

    private func layoutTreemap(_ nodes: [HierarchyNode], in rect: CGRect,
                               depth: Int, axis: TreemapAxis, path: String,
                               parentFraction: Double, ownerID: String?,
                               items: inout [TreemapItem]) {
        guard rect.width > 0.5, rect.height > 0.5 else { return }
        guard !nodes.isEmpty else { return }

        let entries = nodes.filter { $0.fraction.isFinite }
        guard !entries.isEmpty else { return }

        let length = axis == .rows ? rect.height : rect.width
        guard length.isFinite, length > 0.5 else { return }

        let gap = adaptiveGap(depth: depth, count: entries.count,
                              length: length)
        let available = max(
            0, length - gap * CGFloat(max(0, entries.count - 1)))
        guard available > 0.5 else { return }

        let extents = allocateExtents(entries, available: available,
                                      axis: axis, depth: depth)
        var offset: CGFloat = 0

        for (node, extent) in zip(entries, extents) {
            let childRect: CGRect = axis == .rows
                ? CGRect(x: rect.minX, y: rect.minY + offset,
                         width: rect.width, height: extent)
                : CGRect(x: rect.minX + offset, y: rect.minY,
                         width: extent, height: rect.height)
            offset += extent + gap
            guard extent > 0, childRect.width >= 0.5,
                  childRect.height >= 0.5 else {
                continue
            }

            let childPath = "\(path)/\(depth):\(node.id)"
            let safeFraction = node.fraction.isFinite ? node.fraction : 0
            let global = parentFraction * safeFraction
            let resolvedOwner = node.itemID ?? ownerID
            let inset = adaptiveInset(depth: depth, rect: childRect)
            let headerHeight = treemapHeaderHeight(
                for: node, rect: childRect, inset: inset)

            let index = items.count
            items.append(TreemapItem(
                id: childPath,
                node: node,
                depth: depth,
                rect: childRect,
                globalFraction: global,
                ownerID: resolvedOwner,
                headerHeight: headerHeight,
                hasDrawableChildren: false))

            guard !node.children.isEmpty else { continue }

            var inner = childRect.insetBy(dx: inset, dy: inset)
            if headerHeight > 0 {
                inner.origin.y += headerHeight
                inner.size.height = max(0, inner.height - headerHeight)
            }
            guard inner.width > 3, inner.height > 3 else {
                items[index].headerHeight = 0
                continue
            }

            let before = items.count
            layoutTreemap(node.children, in: inner, depth: depth + 1,
                          axis: axis == .rows ? .columns : .rows,
                          path: childPath, parentFraction: global,
                          ownerID: resolvedOwner, items: &items)
            let hasChildren = items.count > before
            items[index].hasDrawableChildren = hasChildren
            if !hasChildren {
                items[index].headerHeight = 0
            }
        }
    }

    /// Guarantees a visible floor for every sibling, then spreads the rest
    /// proportionally to the real fraction.
    private func allocateExtents(_ entries: [HierarchyNode],
                                 available: CGFloat,
                                 axis: TreemapAxis,
                                 depth: Int) -> [CGFloat] {
        let count = entries.count
        guard count > 0, available.isFinite, available > 0 else {
            return Array(repeating: 0, count: count)
        }

        let requested = entries.map {
            minimumExtent(for: $0, axis: axis, depth: depth)
        }
        let requestedTotal = requested.reduce(0, +)
        let scale = requestedTotal > available
            ? available / requestedTotal : 1
        let mins = requested.map { max(0, $0 * scale) }
        let remainder = max(0, available - mins.reduce(0, +))
        let weights = entries.map {
            $0.fraction.isFinite ? max(0, $0.fraction) : 0
        }
        let weightTotal = weights.reduce(0, +)

        var extents: [CGFloat]
        if weightTotal > 0, weightTotal.isFinite {
            extents = zip(mins, weights).map { minimum, weight in
                minimum + remainder * CGFloat(weight / weightTotal)
            }
        } else {
            extents = mins.map { $0 + remainder / CGFloat(count) }
        }

        let drift = available - extents.reduce(0, +)
        if abs(drift) > 0.001,
           let index = extents.indices.max(by: { extents[$0] < extents[$1] }) {
            extents[index] = max(0, extents[index] + drift)
        }
        return extents
    }

    private func minimumExtent(for node: HierarchyNode,
                               axis: TreemapAxis,
                               depth: Int) -> CGFloat {
        let big = isMaximized
        if node.fraction.isFinite, node.fraction <= 0 {
            switch axis {
            case .rows: return big ? 22 : 20
            case .columns: return big ? 40 : 36
            }
        }
        switch (node.role, axis) {
        case (.partition, .rows):
            if node.children.isEmpty { return big ? 34 : 30 }
            let required = nodeContentHeight(node, axis: .rows,
                                             depth: depth)
            let cap: CGFloat = big ? 600 : 520
            return min(required, cap)
        case (.partition, .columns):
            return big ? 70 : 60
        case (.container, .rows):
            return node.children.isEmpty
                ? (big ? 24 : 22) : (big ? 38 : 32)
        case (.container, .columns):
            return big ? 70 : 60
        case (.volume, .rows):
            return big ? 24 : 22
        case (.volume, .columns):
            return big ? 48 : 44
        case (_, .rows):
            return big ? 22 : 20
        case (_, .columns):
            return big ? 44 : 40
        }
    }

    /// Height needed for a tile to show its descendants at the current
    /// nested axes: stacked children add up, side-by-side children share.
    private func childAxis(of axis: TreemapAxis) -> TreemapAxis {
        axis == .rows ? .columns : .rows
    }

    private func contentHeight(of nodes: [HierarchyNode],
                               axis: TreemapAxis,
                               depth: Int) -> CGFloat {
        guard !nodes.isEmpty else { return 0 }
        let heights = nodes.map {
            nodeContentHeight($0, axis: axis, depth: depth)
        }
        if axis == .rows {
            let gap = siblingGap(depth: depth)
            return heights.reduce(0, +)
                + gap * CGFloat(max(0, nodes.count - 1))
        }
        return heights.max() ?? 0
    }

    private func nodeContentHeight(_ node: HierarchyNode,
                                   axis: TreemapAxis,
                                   depth: Int) -> CGFloat {
        let children = node.children.filter { $0.fraction.isFinite }
        guard !children.isEmpty else {
            return minimumExtent(for: node, axis: .rows, depth: depth)
        }

        let inset = nestedInset(depth: depth)
        let header: CGFloat = isMaximized ? 20 : 18
        let childContent = contentHeight(
            of: children,
            axis: childAxis(of: axis),
            depth: depth + 1)
        return header + inset * 2 + childContent
    }

    private func adaptiveTreemapHeight(for nodes: [HierarchyNode]) -> CGFloat {
        let content = contentHeight(of: nodes, axis: .rows, depth: 0)
        let chrome = 2 * rootInset + diskHeaderHeight + diskContentInset
        return min(max(content + chrome, treemapMinimumHeight),
                   treemapMaximumHeight)
    }

    private func treemapHeaderHeight(for node: HierarchyNode, rect: CGRect,
                                     inset: CGFloat) -> CGFloat {
        guard !node.children.isEmpty else { return 0 }
        let base: CGFloat = isMaximized ? 20 : 18
        return rect.height >= base + inset * 2 + 2 ? base : 0
    }

    private func adaptiveGap(depth: Int, count: Int,
                             length: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        return min(siblingGap(depth: depth),
                   max(0, length) * 0.18 / CGFloat(count - 1))
    }

    private func siblingGap(depth: Int) -> CGFloat {
        switch depth {
        case 0: return isMaximized ? 8.0 : 6.5
        case 1: return isMaximized ? 6.5 : 5.5
        default: return isMaximized ? 2.5 : 2.0
        }
    }

    private func nestedInset(depth: Int) -> CGFloat {
        switch depth {
        case 0: return isMaximized ? 14 : 12
        case 1: return isMaximized ? 11 : 9
        default: return isMaximized ? 8 : 7
        }
    }

    private func adaptiveInset(depth: Int, rect: CGRect) -> CGFloat {
        let configured = nestedInset(depth: depth)
        let side = min(rect.width, rect.height)
        let maxInset = max(0, (side - 8) / 2)
        let target = max(2.5, side * 0.14)
        return min(configured, target, maxInset)
    }

    // MARK: - Treemap drawing

    private func drawDiskRoot(_ layout: TreemapLayout, scope: KBDiskItem,
                              highlightID: String?,
                              diskSelected: Bool,
                              context: inout GraphicsContext) {
        let rect = layout.diskRect
        let radius: CGFloat = isMaximized ? 9 : 8
        let path = Path(roundedRect: rect, cornerRadius: radius)
        context.fill(path, with: .color(DiskPalette.paper))

        var headerContext = context
        headerContext.clip(to: path)
        let band = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width,
                          height: layout.diskHeaderHeight)
        headerContext.fill(Path(band),
                           with: .color(DiskPalette.sand.opacity(0.45)))

        let separatorY = rect.minY + layout.diskHeaderHeight
        var separator = Path()
        separator.move(to: CGPoint(x: rect.minX + 8, y: separatorY))
        separator.addLine(to: CGPoint(x: rect.maxX - 8, y: separatorY))
        context.stroke(separator,
                       with: .color(DiskPalette.textInk.opacity(0.16)),
                       lineWidth: 0.75)
        context.stroke(path,
                       with: .color(DiskPalette.textInk.opacity(0.22)),
                       lineWidth: 1)

        if diskSelected || highlightID == scope.deviceIdentifier {
            let inset: CGFloat = 1.1
            let selected = Path(
                roundedRect: rect.insetBy(dx: inset, dy: inset),
                cornerRadius: max(0, radius - inset))
            context.stroke(selected,
                           with: .color(DiskPalette.textInk),
                           lineWidth: 2)
        }
    }

    private func drawTreemap(_ layout: TreemapLayout, scope: KBDiskItem,
                             highlightID: String?,
                             diskSelected: Bool,
                             context: inout GraphicsContext) {
        drawDiskRoot(layout, scope: scope, highlightID: highlightID,
                     diskSelected: diskSelected, context: &context)
        for item in layout.items {
            let path = Path(roundedRect: item.rect,
                            cornerRadius: cornerRadius(for: item.depth))
            let base = item.node.color
            context.fill(path, with: .color(base))
            context.fill(path, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.16), .clear]),
                startPoint: CGPoint(x: item.rect.midX,
                                    y: item.rect.minY),
                endPoint: CGPoint(x: item.rect.midX,
                                  y: item.rect.midY)))
            let (color, width) = treemapBorder(for: item)
            context.stroke(path, with: .color(color), lineWidth: width)
        }

        for item in layout.items {
            drawTreemapLabel(item, mountColumnX: layout.bounds.midX,
                             context: &context)
        }

        for item in layout.items {
            let content = DiskPalette.contentColor(on: item.node.color)
            let freeSelected = selectedFreeContainerID != nil
                && item.node.role == .free
                && item.ownerID == selectedFreeContainerID
            let selected = (item.node.itemID != nil
                && item.node.itemID == highlightID) || freeSelected
            let ancestor = !selected
                && containsSelection(item.node, highlightID: highlightID)
            let hovered = hoveredNodeID == item.node.id && !selected

            let minSide = min(item.rect.width, item.rect.height)
            let selectedWidth = min(2.2, max(1, minSide * 0.18))
            let selectedInset = min(1.1, selectedWidth / 2)
            let hoverWidth = min(1, max(0.5, minSide * 0.08))
            let hoverInset = min(0.5, hoverWidth / 2)

            let inset: CGFloat
            let color: Color
            let width: CGFloat
            if selected {
                inset = selectedInset
                color = content
                width = selectedWidth
            } else if hovered {
                inset = hoverInset
                color = content.opacity(0.60)
                width = hoverWidth
            } else if ancestor {
                inset = 0.375
                color = content.opacity(0.40)
                width = 0.75
            } else {
                continue
            }

            let path = Path(
                roundedRect: item.rect.insetBy(dx: inset, dy: inset),
                cornerRadius: max(0, cornerRadius(for: item.depth) - inset))
            context.stroke(path, with: .color(color), lineWidth: width)
        }
    }

    private func treemapBorder(for item: TreemapItem) -> (Color, CGFloat) {
        let content = DiskPalette.contentColor(on: item.node.color)
        let opacity: CGFloat
        let width: CGFloat
        switch item.depth {
        case 0:
            opacity = 0.32
            width = 1.0
        case 1:
            opacity = 0.24
            width = 0.8
        default:
            opacity = 0.16
            width = 0.6
        }
        if !item.node.role.isSelectable {
            return (content.opacity(opacity * 0.8), width * 0.8)
        }
        return (content.opacity(opacity), width)
    }

    private func cornerRadius(for depth: Int) -> CGFloat {
        switch depth {
        case 0: return 3
        case 1: return 2
        default: return 1.5
        }
    }

    private func drawTreemapLabel(_ item: TreemapItem,
                                  mountColumnX: CGFloat,
                                  context: inout GraphicsContext) {
        let node = item.node
        let color = DiskPalette.contentColor(on: node.color)

        if item.hasDrawableChildren {
            guard item.headerHeight > 0 else { return }
            let size = labelNameSize(for: item.depth)
            let valueSize = labelValueSize(for: item.depth)

            let usage = fittedTreemapLabel(
                headerUsageCandidates(node),
                maxWidth: min(item.rect.width * 0.55,
                              isMaximized ? 300 : 240),
                size: valueSize,
                weight: .regular)
            let usageWidth = usage.map {
                textWidth($0, size: valueSize, weight: .regular)
            } ?? 0
            let nameMaxWidth = item.rect.width - 10
                - (usage == nil ? 0 : usageWidth + 8)

            guard let text = fittedTreemapLabel(
                treemapHeaderCandidates(node),
                maxWidth: max(40, nameMaxWidth),
                size: size,
                weight: .semibold) else { return }
            let resolved = context.resolve(
                Text(text)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(color))

            var headerContext = context
            headerContext.clip(to: Path(
                CGRect(x: item.rect.minX, y: item.rect.minY,
                       width: item.rect.width, height: item.headerHeight)
                    .insetBy(dx: 2, dy: 1)))
            headerContext.draw(
                resolved,
                at: CGPoint(x: item.rect.minX + 5, y: item.rect.minY + 1.5),
                anchor: .topLeading)

            if let usage {
                let resolvedUsage = context.resolve(
                    Text(usage)
                        .font(.system(size: valueSize))
                        .foregroundColor(color.opacity(0.82)))
                headerContext.draw(
                    resolvedUsage,
                    at: CGPoint(
                        x: item.rect.maxX - 5,
                        y: item.rect.minY + 1.5 + (size - valueSize) / 2),
                    anchor: .topTrailing)
            }
            return
        }

        let standardSize = labelNameSize(for: item.depth)
        let standardLine = labelLineHeight(standardSize)
        let compact = item.rect.height < 2 + standardLine + 3
        let nameSize = compact ? minimumTileTextSize : standardSize
        let nameTop: CGFloat = compact ? 1.5 : 2
        let nameLine = labelLineHeight(nameSize)
        let nameBottom = item.rect.minY + nameTop + nameLine
        let nameMinHeight = nameTop + nameLine + 1
        guard item.rect.width >= 34,
              item.rect.height >= nameMinHeight else { return }

        let valueSize = labelValueSize(for: item.depth)
        let dataTop = nameBottom + 2
        let dataLine = labelLineHeight(valueSize)
        let dataBottom = dataTop + dataLine
        let data = treemapDataText(node)

        let mountPoint = node.role == .volume
            ? node.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let mountSize = minimumTileTextSize
        let dataFits = dataBottom <= item.rect.maxY - 2
        let showsDataLine = !compact
            && item.rect.width >= 60
            && dataFits

        let inlineSize = compact ? minimumTileTextSize : valueSize
        let inlineData: String? = {
            guard !showsDataLine, let data, item.rect.width >= 60 else {
                return nil
            }
            let available = item.rect.width - 8
            let proposed = max(24, min(available * 0.55, 110))
            guard available - (proposed + 8) >= 34 else { return nil }
            return truncatedLabel(
                data,
                maxWidth: proposed,
                size: inlineSize,
                weight: .regular)
        }()
        let inlineWidth = inlineData.map {
            textWidth($0, size: inlineSize, weight: .regular)
        } ?? 0

        let mountColumnInside = mountPoint?.isEmpty == false
            && mountColumnX >= item.rect.minX + 42
            && mountColumnX <= item.rect.maxX - 42
        let rightReserve = 4 + (inlineData == nil ? 0 : inlineWidth + 8)
        let mountMaxWidth = max(
            0,
            item.rect.maxX - rightReserve - mountColumnX - 6)
        let fittedMount = (mountPoint?.isEmpty == false
            && mountColumnInside
            && mountMaxWidth > 8)
            ? truncatedLabel(
                mountPoint!,
                maxWidth: mountMaxWidth,
                size: mountSize,
                weight: .regular,
                monospaced: true)
            : nil

        let baseNameMax = item.rect.width - 8
            - (inlineData == nil ? 0 : inlineWidth + 8)
        let nameMaxWidth = fittedMount != nil
            ? min(baseNameMax, mountColumnX - item.rect.minX - 8)
            : baseNameMax

        guard let name = fittedTreemapLabel(
            treemapLeafCandidates(node, ownerID: item.ownerID),
            maxWidth: max(34, nameMaxWidth),
            size: nameSize,
            weight: .semibold) else { return }
        let resolved = context.resolve(
            Text(name)
                .font(.system(size: nameSize, weight: .semibold))
                .foregroundColor(color))

        var labelContext = context
        labelContext.clip(to: Path(item.rect.insetBy(dx: 2, dy: 1)))
        labelContext.draw(
            resolved,
            at: CGPoint(x: item.rect.minX + 4,
                        y: item.rect.minY + nameTop),
            anchor: .topLeading)

        if let inlineData {
            let resolvedData = context.resolve(
                Text(inlineData)
                    .font(.system(size: inlineSize))
                    .foregroundColor(color.opacity(0.82)))
            labelContext.draw(
                resolvedData,
                at: CGPoint(x: item.rect.maxX - 4,
                            y: item.rect.minY + nameTop),
                anchor: .topTrailing)
        } else if showsDataLine,
                  let data,
                  let fitted = truncatedLabel(
                    data,
                    maxWidth: item.rect.width - 8,
                    size: valueSize,
                    weight: .regular) {
            let resolvedValue = context.resolve(
                Text(fitted)
                    .font(.system(size: valueSize))
                    .foregroundColor(color.opacity(0.82)))
            labelContext.draw(
                resolvedValue,
                at: CGPoint(x: item.rect.minX + 4,
                            y: dataTop),
                anchor: .topLeading)
        }

        if let fittedMount {
            let resolvedMount = context.resolve(
                Text(fittedMount)
                    .font(.system(size: mountSize, design: .monospaced))
                    .foregroundColor(color.opacity(0.9)))
            labelContext.draw(
                resolvedMount,
                at: CGPoint(
                    x: mountColumnX,
                    y: item.rect.minY + nameTop + nameLine / 2),
                anchor: .leading)
        }
    }

    private func occupancy(of node: HierarchyNode) -> Double? {
        guard let used = node.usedBytes, let capacity = node.capacityBytes,
              capacity > 0 else { return nil }
        return min(1, Double(used) / Double(capacity))
    }

    private func treemapDataText(_ node: HierarchyNode) -> String? {
        if let used = node.usedBytes, let fraction = occupancy(of: node) {
            return "\(KBFormat.bytes(used, units: byteUnitSystem)) · "
                + KBFormat.percent(fraction)
        }
        if node.role == .volume, node.detail == nil,
           (node.usedBytes ?? 0) == 0 {
            return "Not mounted"
        }
        if node.role.isSelectable, node.usedBytes == nil {
            return "Usage unknown"
        }
        guard node.bytes > 0 else { return nil }
        let fraction = node.fraction.isFinite
            ? min(max(node.fraction, 0), 1) : 0
        return "\(KBFormat.bytes(node.bytes, units: byteUnitSystem)) · "
            + KBFormat.percent(fraction)
    }

    private func headerUsageCandidates(_ node: HierarchyNode) -> [String] {
        guard node.role == .partition || node.role == .container else {
            return []
        }
        guard let used = node.usedBytes else { return ["Usage unknown"] }
        let bytes = KBFormat.bytes(used, units: byteUnitSystem)
        guard let fraction = occupancy(of: node) else {
            return ["\(bytes) used"]
        }
        let percent = KBFormat.percent(fraction)
        return ["\(bytes) used · \(percent)", "\(bytes) used", percent]
    }

    private func treemapTypeLabel(_ node: HierarchyNode) -> String {
        switch node.role {
        case .partition: return "Partition"
        case .container: return "APFS container"
        case .volume: return "APFS volume"
        case .free: return "Free space"
        case .residual: return "Snapshots & metadata"
        case .unallocated: return "Not allocated"
        case .used: return "Used"
        case .unknown: return "Usage unknown"
        }
    }

    /// Avoids repeating the type when the node name already carries it.
    private func typeSuffix(for node: HierarchyNode) -> String {
        let name = node.label.lowercased()
        switch node.role {
        case .partition:
            return name.contains("partition") ? "" : "Partition"
        case .container:
            if name.contains("apfs container") { return "" }
            return name.contains("container") ? "APFS" : "APFS container"
        case .volume:
            return name.contains("apfs") ? "" : "APFS volume"
        default:
            return treemapTypeLabel(node)
        }
    }

    private func nameAddsDetail(_ name: String, type: String) -> Bool {
        !name.isEmpty && !type.localizedCaseInsensitiveContains(name)
    }

    private func treemapHeaderCandidates(_ node: HierarchyNode) -> [String] {
        let id = node.itemID
        let name = node.label
        let type = treemapTypeLabel(node)
        let suffix = typeSuffix(for: node)

        var idPart: [String] = []
        if let id, !id.isEmpty { idPart.append(id) }

        var full = idPart
        if !name.isEmpty && name != id { full.append(name) }
        if !suffix.isEmpty { full.append(suffix) }

        let idType = (idPart + [type]).joined(separator: " · ")

        var nameType: [String] = []
        if !name.isEmpty && name != id { nameType.append(name) }
        if !suffix.isEmpty { nameType.append(suffix) }

        return [full.joined(separator: " · "),
                idType,
                nameType.joined(separator: " · "),
                name,
                id ?? ""]
    }

    private func treemapLeafCandidates(_ node: HierarchyNode,
                                       ownerID: String?) -> [String] {
        let id = node.itemID ?? ownerID
        let name = node.label
        let type = treemapTypeLabel(node)
        let suffix = typeSuffix(for: node)

        var idPart: [String] = []
        if let id, !id.isEmpty { idPart.append(id) }

        switch node.role {
        case .free, .residual, .unallocated, .used, .unknown:
            var full = idPart
            if nameAddsDetail(name, type: type) {
                full.append(name)
            }
            full.append(type)
            return [full.joined(separator: " · "),
                    (idPart + [type]).joined(separator: " · "),
                    id ?? ""]
        default:
            var full = idPart
            if !name.isEmpty && name != id { full.append(name) }
            if !suffix.isEmpty { full.append(suffix) }

            var nameType: [String] = []
            if !name.isEmpty && name != id { nameType.append(name) }
            if !suffix.isEmpty { nameType.append(suffix) }

            return [full.joined(separator: " · "),
                    nameType.joined(separator: " · "),
                    name,
                    (idPart + [type]).joined(separator: " · "),
                    id ?? ""]
        }
    }

    private func fittedTreemapLabel(_ candidates: [String], maxWidth: CGFloat,
                                    size: CGFloat,
                                    weight: NSFont.Weight) -> String? {
        let usable = candidates.filter { !$0.isEmpty }
        for candidate in usable
            where textWidth(candidate, size: size, weight: weight) <= maxWidth {
            return candidate
        }
        for candidate in usable {
            if let truncated = truncatedLabel(candidate, maxWidth: maxWidth,
                                              size: size, weight: weight) {
                return truncated
            }
        }
        return nil
    }

    private var minimumTileTextSize: CGFloat {
        isMaximized ? 12.5 : 11.5
    }

    private func labelLineHeight(_ size: CGFloat,
                                 monospaced: Bool = false) -> CGFloat {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont.systemFont(ofSize: size)
        return ceil(font.ascender - font.descender + font.leading)
    }

    private func labelNameSize(for depth: Int) -> CGFloat {
        let base: CGFloat = depth == 0 ? 11.5 : (depth == 1 ? 11 : 10.5)
        return max(minimumTileTextSize, isMaximized ? base + 1 : base)
    }

    private func labelValueSize(for depth: Int) -> CGFloat {
        let base: CGFloat = depth == 0 ? 10 : (depth == 1 ? 9.5 : 9)
        return max(minimumTileTextSize, isMaximized ? base + 1 : base)
    }

    private func truncatedLabel(_ text: String, maxWidth: CGFloat,
                                size: CGFloat,
                                weight: NSFont.Weight,
                                monospaced: Bool = false) -> String? {
        guard maxWidth > 8 else { return nil }
        if textWidth(text, size: size, weight: weight,
                     monospaced: monospaced) <= maxWidth {
            return text
        }
        let ellipsis = "…"
        guard textWidth(ellipsis, size: size, weight: weight,
                        monospaced: monospaced) <= maxWidth else {
            return nil
        }
        var result = text
        while !result.isEmpty {
            result.removeLast()
            let candidate = result + ellipsis
            if textWidth(candidate, size: size, weight: weight,
                         monospaced: monospaced) <= maxWidth {
                return candidate
            }
        }
        return ellipsis
    }

    private func textWidth(_ text: String, size: CGFloat,
                           weight: NSFont.Weight,
                           monospaced: Bool = false) -> CGFloat {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: - Hit testing

    private func treemapItem(at location: CGPoint,
                             in layout: TreemapLayout) -> TreemapItem? {
        var best: TreemapItem?
        for item in layout.items where item.rect.contains(location) {
            if best == nil || item.depth >= best!.depth {
                best = item
            }
        }
        return best
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
            return partitionNodes(for: scope)
        case .partition:
            let containers = containerNodes(
                for: scope,
                parentBytes: scope.sizeBytes)
            return containers.isEmpty ? usageNodes(for: scope) : containers
        case .apfsContainer:
            return volumeNodes(for: scope)
        case .apfsVolume, .snapshot:
            guard let container = inventory.apfsContainer(enclosing: scope) else {
                return []
            }
            return volumeNodes(for: container)
        }
    }

    private func partitionNodes(for scope: KBDiskItem) -> [HierarchyNode] {
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

        for partition in partitions {
            let color = DiskPalette.fill(level: 0)
            let usage = partition.spaceUsage
            let children = containerNodes(
                for: partition,
                parentBytes: partition.sizeBytes)
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
                                parentBytes: UInt64) -> [HierarchyNode] {
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
            let color = DiskPalette.fill(level: 1)
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
                children: volumeNodes(for: container)))
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

    private func volumeNodes(for container: KBDiskItem) -> [HierarchyNode] {
        guard let context = inventory.apfsSpaceContext(for: container) else {
            return []
        }

        var nodes: [HierarchyNode] = []
        var represented = Set<String>()
        let selectedVolumeID = item.kind == .apfsVolume
            ? item.deviceIdentifier : nil
        var volumeIndex = 0

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
                if let selectedVolumeID,
                   segment.itemID == selectedVolumeID {
                    color = DiskPalette.tint(for: .apfsVolume)
                } else {
                    color = DiskPalette.mutedVolume(volumeIndex)
                }
                volumeIndex += 1
            case .free:
                color = DiskPalette.free
            case .residual:
                color = DiskPalette.residual
            case .unknown:
                color = DiskPalette.unknown
            case .container:
                color = DiskPalette.fill(level: 1)
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

        // Unmounted or empty volumes have no area; keep them selectable in
        // the chart.
        let missing = container.children
            .filter { $0.kind == .apfsVolume }
            .filter { !represented.contains($0.deviceIdentifier) }
        for volume in missing {
            let isSelected = selectedVolumeID != nil
                && volume.deviceIdentifier == selectedVolumeID
            let color: Color = isSelected
                ? DiskPalette.tint(for: .apfsVolume)
                : DiskPalette.mutedVolume(volumeIndex)
            volumeIndex += 1
            nodes.append(HierarchyNode(
                id: "missing:\(container.deviceIdentifier):\(volume.deviceIdentifier)",
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
                color: color,
                children: []))
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
                color: DiskPalette.usedFill,
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

    private func displayName(_ item: KBDiskItem) -> String {
        item.name.isEmpty ? item.deviceIdentifier : item.name
    }

    private func adding(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }

    // MARK: - Types

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
        /// Share of the parent's extent (0...1).
        let fraction: Double
        let color: Color
        let children: [HierarchyNode]
    }

    private enum TreemapAxis {
        case rows
        case columns
    }

    private struct TreemapItem: Identifiable {
        let id: String
        let node: HierarchyNode
        let depth: Int
        let rect: CGRect
        let globalFraction: Double
        let ownerID: String?
        var headerHeight: CGFloat
        var hasDrawableChildren: Bool
    }

    private struct TreemapLayout {
        let bounds: CGRect
        let items: [TreemapItem]
        let diskRect: CGRect
        let diskHeaderHeight: CGFloat
    }
}

private struct VerticalUsageBar: View {
    let slices: [VolumeBarSlice]
    let fraction: Double?
    let tint: Color
    let kindLabel: String?
    let caption: String?
    let height: CGFloat
    let width: CGFloat
    let isMaximized: Bool
    var onSliceTap: ((VolumeBarSlice) -> Void)? = nil

    private var clamped: Double {
        guard let fraction, fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    private var percentText: String {
        fraction == nil ? "—" : KBFormat.percent(clamped)
    }

    /// Two lines are reserved below the bar so a longer caption never
    /// shifts or resizes the bar above it.
    private var captionHeight: CGFloat { 20 }

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

            VolumeBarView(
                slices: slices,
                width: width,
                height: height,
                tint: tint,
                isMaximized: isMaximized,
                onTapSlice: onSliceTap)

            Text(caption ?? "")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: width, height: captionHeight, alignment: .top)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kindLabel.map { "\($0) blocks" }
                            ?? "Disk blocks")
        .accessibilityValue(fraction == nil ? "Unknown" : percentText)
    }
}

/// Collects the Used value frame so the hero can draw its horizontal leader.
private struct UsedLeaderAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
