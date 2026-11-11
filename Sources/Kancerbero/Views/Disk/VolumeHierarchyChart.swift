import AppKit
import SwiftUI
import KancerberoCore

/// One big number shown beside the chart.
struct VolumeHierarchyStat: Identifiable {
    let id: String
    let title: String
    let value: String
    var subtitle: String? = nil
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
    var onAnalyze: ((String) -> Void)? = nil
    var stats: [VolumeHierarchyStat] = []
    var usageFraction: Double? = nil
    /// Height of the detail-card viewport. The chart and the bar are capped
    /// to it so the bar stays fully visible when the window shrinks.
    var availableHeight: CGFloat? = nil
    @Binding var selectedFreeContainerID: String?
    @Binding var detailSelectionHidden: Bool

    @Environment(\.byteUnitSystem) private var byteUnitSystem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredNodeID: String?
    @State private var contextItemID: String?

    private var palette: DiskTreemapPalette {
        DiskPalette.treemap(for: colorScheme)
    }

    var body: some View {
        let scope = scopeItem(in: inventory)
        let nodes = makeNodes(for: scope)
        let highlightID = highlightID(in: nodes)

        // Match the bar to the visible treemap, excluding its bottom inset.
        let treemapHeight = availableHeight.map {
            max(treemapMinimumHeight, $0)
        } ?? adaptiveTreemapHeight(for: nodes)
        let trackHeight = max(0, treemapHeight - treemapTopInset - rootInset)
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
            contextItemID = nil
        }
    }

    // MARK: - Hero

    private var chartColumnSpacing: CGFloat { isMaximized ? 10 : 6 }

    private var statsWidth: CGFloat { isMaximized ? 150 : 130 }
    private var heroSpacing: CGFloat { isMaximized ? 12 : 6 }
    private var barWidth: CGFloat { isMaximized ? 66 : 58 }
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
                height: trackHeight,
                width: barWidth,
                isMaximized: isMaximized,
                onSliceTap: handleBarTap,
                fallbackItemID: item.deviceIdentifier,
                itemResolver: { id in
                    inventory.allItems.first {
                        $0.deviceIdentifier == id
                    }
                },
                onAnalyze: onAnalyze)
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

    /// Item behind the treemap tile under the cursor; the selected item is
    /// used when the pointer is over the background.
    private var contextItem: KBDiskItem? {
        let id = contextItemID ?? item.deviceIdentifier
        return inventory.allItems.first { $0.deviceIdentifier == id }
    }

    /// Clicking a bar segment selects the disk item behind it. Free-space
    /// segments keep their own container highlight, and clicking the already
    /// selected item toggles the detail highlight as before.
    private func handleBarTap(_ slice: VolumeBarSlice) {
        if slice.isFree {
            detailSelectionHidden = false
            selectedFreeContainerID =
                selectedFreeContainerID == slice.ownerID
                    ? nil : slice.ownerID
            return
        }
        selectedFreeContainerID = nil
        guard let itemID = slice.ownerID else { return }
        if itemID == item.deviceIdentifier && !detailSelectionHidden {
            detailSelectionHidden = true
            return
        }
        detailSelectionHidden = false
        if itemID != item.deviceIdentifier {
            onSelectItem?(itemID)
        }
    }

    private var statRowHeight: CGFloat {
        labelLineHeight(9.5) + 1 + labelLineHeight(statValueSize)
    }

    private var statSubtitleSize: CGFloat { isMaximized ? 10 : 9 }

    private var capacitySubtitle: String? {
        stats.first { $0.id == "capacity" }?.subtitle
    }

    /// Height reserved under the Capacity value for its sharing note, so the
    /// Used row keeps its alignment with the selected bar segment.
    private var capacitySubtitleHeight: CGFloat {
        guard let subtitle = capacitySubtitle, !subtitle.isEmpty else {
            return 0
        }
        let font = NSFont.systemFont(ofSize: statSubtitleSize)
        let bounding = (subtitle as NSString).boundingRect(
            with: CGSize(width: statsWidth,
                         height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        return ceil(bounding.height) + 1
    }

    private var capacitySubtitleBlock: CGFloat {
        guard let subtitle = capacitySubtitle, !subtitle.isEmpty else {
            return 0
        }
        return capacitySubtitleHeight + 1
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
            + capacitySubtitleBlock
        // A free-space selection is highlighted in the bar but has no Used
        // leader: the Used value keeps its normal position.
        guard !detailSelectionHidden,
              selectedFreeContainerID == nil,
              let center = VolumeBarLayout.selectedCenterY(
                  for: barSlices, height: trackHeight,
                  isMaximized: isMaximized) else {
            return minimumTop
        }
        let target = center - usedValueMidOffset
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
            + capacitySubtitleBlock
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
            if let subtitle = stat.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: statSubtitleSize))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        /// Text shown inside the bar segment: the device identifier, or
        /// "Free" for free space.
        let label: String
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
                isHighlighted: highlighted,
                label: block.label,
                ownerID: block.ownerID)
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
                    isFree: true,
                    label: "Free"))
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
                    isFree: false,
                    label: volume.deviceIdentifier))
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
                    isFree: false,
                    label: node.deviceIdentifier))
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
                        isFree: false,
                        label: node.deviceIdentifier))
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
                    isFree: false,
                    label: node.deviceIdentifier))
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
                isFree: false,
                label: scope.deviceIdentifier))
        }
        if free > 0 {
            blocks.append(BarBlock(
                id: "free:\(scope.deviceIdentifier)",
                ownerID: scope.deviceIdentifier,
                containerID: scope.deviceIdentifier,
                bytes: free,
                isFree: true,
                label: "Free"))
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
                .padding(.top, treemapTopInset)
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
            .contextMenu {
                if let target = contextItem {
                    DiskItemContextMenu(item: target,
                                        onAnalyze: onAnalyze)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let hovered = treemapItem(at: location, in: layout)
                    contextItemID = hovered?.ownerID
                    if hovered?.node.id != hoveredNodeID {
                        withAnimation(reduceMotion ? nil
                                       : .easeOut(duration: 0.12)) {
                            hoveredNodeID = hovered?.node.id
                        }
                    }
                case .ended:
                    // Keep the last tile for the context menu; only the
                    // hover outline goes away.
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

    /// The bar has no header above it, so the disk panel starts flush with
    /// the top of the hero instead of leaving the usual inset there.
    private var treemapTopInset: CGFloat { 0 }

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
                .foregroundStyle(palette.textInk.opacity(0.8))
            Text(scope.deviceIdentifier)
                .font(.system(size: 11.5, weight: .semibold,
                              design: .monospaced))
                .foregroundStyle(palette.textInk)
            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.textInk.opacity(0.72))
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
            y: treemapTopInset,
            width: max(0, size.width - 2 * rootInset),
            height: max(0, size.height - treemapTopInset - rootInset))
        let bounds = CGRect(
            x: diskRect.minX + diskContentInset,
            y: diskRect.minY + diskHeaderHeight,
            width: max(0, diskRect.width - 2 * diskContentInset),
            height: max(0, diskRect.height - diskHeaderHeight
                - diskContentInset))
        var items: [TreemapItem] = []
        layoutTreemap(nodes, in: bounds, depth: 0, axis: .rows,
                      path: "", parentFraction: 1,
                      ownerID: scopeID, parentRole: nil, items: &items)
        return TreemapLayout(bounds: bounds, items: items,
                             diskRect: diskRect,
                             diskHeaderHeight: diskHeaderHeight)
    }

    private func layoutTreemap(_ nodes: [HierarchyNode], in rect: CGRect,
                               depth: Int, axis: TreemapAxis, path: String,
                               parentFraction: Double, ownerID: String?,
                               parentRole: SliceRole?,
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
                                      axis: axis, depth: depth,
                                      parentRole: parentRole)
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

            // If the remaining area cannot fit the labels of the children,
            // keep this tile as a labeled leaf instead of drawing unlabeled
            // slivers.
            let innerAxis = childAxis(for: node)
            let neededHeight = minimumChildHeight(
                of: node.children, axis: innerAxis, depth: depth + 1)
            let neededWidth = minimumChildWidth(
                of: node.children, axis: innerAxis, depth: depth + 1)
            if inner.height < neededHeight || inner.width < neededWidth {
                items[index].headerHeight = 0
                continue
            }

            let before = items.count
            layoutTreemap(node.children, in: inner, depth: depth + 1,
                          axis: childAxis(for: node),
                          path: childPath, parentFraction: global,
                          ownerID: resolvedOwner, parentRole: node.role,
                          items: &items)
            let hasChildren = items.count > before
            items[index].hasDrawableChildren = hasChildren
            if !hasChildren {
                items[index].headerHeight = 0
            }
        }
    }

    /// Guarantees a visible floor for every sibling, then spreads the rest
    /// proportionally to the real fraction. When a container holds volumes
    /// with very different sizes, the proportional share takes precedence
    /// over the per-tile floor so the largest volume can grow.
    private func allocateExtents(_ entries: [HierarchyNode],
                                 available: CGFloat,
                                 axis: TreemapAxis,
                                 depth: Int,
                                 parentRole: SliceRole?) -> [CGFloat] {
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
        let positiveWeights = weights.filter { $0 > 0 }
        let spread = positiveWeights.isEmpty
            ? 1
            : (positiveWeights.max() ?? 1)
                / max(positiveWeights.min() ?? 1, .leastNonzeroMagnitude)

        var extents: [CGFloat]
        let fits = requestedTotal <= available
        if spread >= 6,
           parentRole == .container || !fits {
            extents = proportionalExtents(entries, available: available,
                                          weights: weights, axis: axis,
                                          depth: depth)
        } else if weightTotal > 0, weightTotal.isFinite {
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

    /// Allocates the available length in proportion to the real fraction,
    /// keeping a floor that still fits one line of tile text. Used for
    /// container children when the size spread is wide, so a large volume
    /// does not collapse to the same extent as the small ones and every
    /// tile keeps its name visible.
    private func proportionalExtents(_ entries: [HierarchyNode],
                                     available: CGFloat,
                                     weights: [Double],
                                     axis: TreemapAxis,
                                     depth: Int) -> [CGFloat] {
        let count = entries.count
        guard count > 0 else { return [] }

        let visibility = entries.map {
            visibilityFloor(for: $0, axis: axis)
        }
        let labels = entries.map {
            floorExtent(for: $0, axis: axis, depth: depth)
        }
        let floors = allocateFloors(visibility: visibility, labels: labels,
                                    weights: weights, available: available)
        let weightTotal = weights.reduce(0, +)
        let targets: [CGFloat]
        if weightTotal > 0, weightTotal.isFinite {
            targets = weights.map {
                available * CGFloat($0 / weightTotal)
            }
        } else {
            targets = Array(repeating: available / CGFloat(count),
                            count: count)
        }

        var extents = zip(targets, floors).map { max($0, $1) }
        let total = extents.reduce(0, +)
        if total > available {
            let above = zip(extents, floors).map { max(0, $0 - $1) }
            let aboveTotal = above.reduce(0, +)
            let excess = total - available
            if aboveTotal > 0 {
                // Never shrink a tile below its floor: take at most the
                // amount that sits above it.
                let scale = min(1, excess / aboveTotal)
                extents = zip(extents, above).map { $0 - $1 * scale }
            } else {
                let scale = available / max(total, .leastNonzeroMagnitude)
                extents = floors.map { $0 * scale }
            }
        }
        return extents
    }

    /// Assigns each tile the largest floor it can get: every tile first
    /// receives its selectable visibility floor, then the remaining space
    /// is handed out (proportionally to size) up to the label floor. This
    /// keeps the text legible instead of leaving tiles too short to draw it.
    private func allocateFloors(visibility: [CGFloat],
                                labels: [CGFloat],
                                weights: [Double],
                                available: CGFloat) -> [CGFloat] {
        let labelTotal = labels.reduce(0, +)
        if labelTotal <= available { return labels }

        let visibilityTotal = visibility.reduce(0, +)
        guard visibilityTotal < available else {
            let scale = available / max(visibilityTotal,
                                        .leastNonzeroMagnitude)
            return visibility.map { $0 * scale }
        }

        var floors = visibility
        var budget = available - visibilityTotal
        var capacity = zip(labels, visibility).map { max(0, $0 - $1) }
        let weightTotal = weights.reduce(0, +)

        // Redistribute leftovers left by capped tiles until the budget is
        // spent or no tile can grow further.
        while budget > 0.001 {
            let open = capacity.indices.filter { capacity[$0] > 0.001 }
            guard !open.isEmpty else { break }
            let openWeight = open.reduce(0) { $0 + max(0, weights[$1]) }
            var spent: CGFloat = 0
            for index in open {
                let share = openWeight > 0 && weights[index] > 0
                    ? budget * CGFloat(max(0, weights[index]) / openWeight)
                    : budget / CGFloat(open.count)
                let grant = min(share, capacity[index])
                floors[index] += grant
                capacity[index] -= grant
                spent += grant
            }
            guard spent > 0.001 else { break }
            budget -= spent
        }
        return floors
    }

    /// Smallest extent that stays visible and selectable, even when there
    /// is no room for the label.
    private func visibilityFloor(for node: HierarchyNode,
                                 axis: TreemapAxis) -> CGFloat {
        switch node.role {
        case .volume, .free, .residual, .unknown, .unallocated, .used:
            return axis == .rows ? 10 : 24
        default:
            return axis == .rows ? 20 : 40
        }
    }

    /// Smallest extent that fits the tile's own label: the header band for
    /// partitions and containers, one text line for leaves.
    private func floorExtent(for node: HierarchyNode,
                             axis: TreemapAxis,
                             depth: Int) -> CGFloat {
        switch axis {
        case .rows:
            switch node.role {
            case .partition, .container:
                let base: CGFloat = isMaximized ? 20 : 18
                return base + nestedInset(depth: depth) * 2 + 2
            default:
                return tileLabelFloor(axis: .rows, depth: depth)
            }
        case .columns:
            switch node.role {
            case .partition, .container:
                return isMaximized ? 70 : 60
            default:
                return tileLabelFloor(axis: .columns, depth: depth)
            }
        }
    }

    /// Smallest extent that fits one line of tile text. Mirrors the guard
    /// used by `drawTreemapLabel`.
    private func tileLabelFloor(axis: TreemapAxis, depth: Int) -> CGFloat {
        switch axis {
        case .rows:
            return minimumTileNameHeight
        case .columns:
            return 36
        }
    }

    private var minimumTileNameHeight: CGFloat {
        ceil(1.5 + labelLineHeight(minimumTileTextSize) + 1)
    }

    /// Vertical space a subtree needs so all of its labels fit. Rows stack
    /// their children; columns take the tallest child.
    private func minimumChildHeight(of nodes: [HierarchyNode],
                                    axis: TreemapAxis,
                                    depth: Int) -> CGFloat {
        let heights = nodes
            .filter { $0.fraction.isFinite }
            .map { labelContentHeight(for: $0, depth: depth) }
        guard !heights.isEmpty else { return 0 }
        if axis == .rows {
            let gap = siblingGap(depth: depth)
            return heights.reduce(0, +)
                + gap * CGFloat(max(0, heights.count - 1))
        }
        return heights.max() ?? 0
    }

    /// Horizontal space a subtree needs for its tiles and labels.
    private func minimumChildWidth(of nodes: [HierarchyNode],
                                   axis: TreemapAxis,
                                   depth: Int) -> CGFloat {
        let widths = nodes
            .filter { $0.fraction.isFinite }
            .map { floorExtent(for: $0, axis: .columns, depth: depth) }
        guard !widths.isEmpty else { return 0 }
        if axis == .columns {
            let gap = siblingGap(depth: depth)
            return widths.reduce(0, +)
                + gap * CGFloat(max(0, widths.count - 1))
        }
        return widths.max() ?? 0
    }

    /// Recursive height of a tile plus its descendants when every label is
    /// given its floor. Partitions and containers add their header band and
    /// insets; children add their own requirement.
    private func labelContentHeight(for node: HierarchyNode,
                                    depth: Int) -> CGFloat {
        let children = node.children.filter { $0.fraction.isFinite }
        guard !children.isEmpty else {
            return floorExtent(for: node, axis: .rows, depth: depth)
        }
        let inset = nestedInset(depth: depth)
        let header: CGFloat = isMaximized ? 20 : 18
        let innerAxis = childAxis(for: node)
        let childFloors = children.map {
            labelContentHeight(for: $0, depth: depth + 1)
        }
        let childContent: CGFloat
        if innerAxis == .rows {
            let gap = siblingGap(depth: depth + 1)
            childContent = childFloors.reduce(0, +)
                + gap * CGFloat(max(0, children.count - 1))
        } else {
            childContent = childFloors.max() ?? 0
        }
        return header + inset * 2 + childContent
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
            if node.children.isEmpty { return big ? 24 : 22 }
            let required = nodeContentHeight(node, axis: .rows,
                                             depth: depth)
            let cap: CGFloat = big ? 600 : 520
            return min(required, cap)
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

    /// Children are arranged by their parent's role, not by depth, so a
    /// container directly under a physical disk (no partition level) still
    /// stacks its volumes as rows like every other container.
    private func childAxis(for node: HierarchyNode) -> TreemapAxis {
        switch node.role {
        case .partition: return .columns
        case .container: return .rows
        default: return .rows
        }
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
            axis: childAxis(for: node),
            depth: depth + 1)
        return header + inset * 2 + childContent
    }

    private func adaptiveTreemapHeight(for nodes: [HierarchyNode]) -> CGFloat {
        let content = contentHeight(of: nodes, axis: .rows, depth: 0)
        let chrome = treemapTopInset + rootInset
            + diskHeaderHeight + diskContentInset
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
        context.fill(path, with: .color(palette.paper))

        var headerContext = context
        headerContext.clip(to: path)
        let band = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width,
                          height: layout.diskHeaderHeight)
        headerContext.fill(Path(band),
                           with: .color(palette.sand.opacity(0.45)))

        let separatorY = rect.minY + layout.diskHeaderHeight
        var separator = Path()
        separator.move(to: CGPoint(x: rect.minX + 8, y: separatorY))
        separator.addLine(to: CGPoint(x: rect.maxX - 8, y: separatorY))
        context.stroke(separator,
                       with: .color(palette.textInk.opacity(0.16)),
                       lineWidth: 0.75)
        context.stroke(path,
                       with: .color(palette.textInk.opacity(0.22)),
                       lineWidth: 1)

        if diskSelected || highlightID == scope.deviceIdentifier {
            let inset: CGFloat = 1.1
            let selected = Path(
                roundedRect: rect.insetBy(dx: inset, dy: inset),
                cornerRadius: max(0, radius - inset))
            context.stroke(selected,
                           with: .color(palette.textInk),
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
                Gradient(colors: [.white.opacity(colorScheme == .dark
                                                ? 0.10 : 0.16),
                                  .clear]),
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
        let schemeScale: CGFloat = colorScheme == .dark ? 0.7 : 1
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
            return (content.opacity(opacity * 0.8 * schemeScale),
                    width * 0.8)
        }
        return (content.opacity(opacity * schemeScale), width)
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
        guard item.rect.width >= 34,
              item.rect.height >= minimumTileNameHeight else { return }

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

    /// Children of a physical disk can be partitions or, when the disk has no
    /// partition scheme, APFS containers directly (disk images and other
    /// synthesized stores). Both shapes must reach the treemap.
    private func partitionNodes(for scope: KBDiskItem) -> [HierarchyNode] {
        let entries = scope.children
            .filter { $0.kind != .snapshot && $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        guard !entries.isEmpty else { return usageNodes(for: scope) }

        var accounted: UInt64 = 0
        for entry in entries {
            accounted = adding(accounted, entry.sizeBytes)
        }
        let denominator = max(scope.sizeBytes, accounted)
        var nodes: [HierarchyNode] = []

        for entry in entries {
            if entry.kind == .apfsContainer {
                nodes.append(containerNode(for: entry,
                                           denominator: denominator))
                continue
            }

            let usage = entry.spaceUsage
            let children = containerNodes(
                for: entry,
                parentBytes: entry.sizeBytes)
            nodes.append(HierarchyNode(
                id: "partition:\(entry.deviceIdentifier)",
                itemID: entry.deviceIdentifier,
                role: .partition,
                label: displayName(entry),
                detail: entry.mountPoint,
                kindLabel: "Partition",
                fileSystem: entry.fileSystem
                    ?? entry.children.first?.fileSystem,
                bytes: entry.sizeBytes,
                capacityBytes: entry.sizeBytes,
                usedBytes: usage.usedBytes,
                freeBytes: usage.freeBytes,
                fraction: Double(entry.sizeBytes) / Double(max(denominator, 1)),
                color: palette.fill(level: 0),
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
                color: palette.unallocated,
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
            nodes.append(containerNode(for: container,
                                       denominator: denominator))
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
                color: palette.unallocated,
                children: []))
        }
        return nodes
    }

    private func containerNode(for container: KBDiskItem,
                               denominator: UInt64) -> HierarchyNode {
        let usage = container.spaceUsage
        let volumes = container.children.filter { $0.kind == .apfsVolume }
        return HierarchyNode(
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
            color: palette.fill(level: 1),
            children: volumeNodes(for: container))
    }

    private func volumeNodes(for container: KBDiskItem) -> [HierarchyNode] {
        guard let context = inventory.apfsSpaceContext(for: container) else {
            return []
        }

        var nodes: [HierarchyNode] = []
        let selectedVolumeID = item.kind == .apfsVolume
            ? item.deviceIdentifier : nil

        // Bands depend on the whole volume set, including the unmounted or
        // empty volumes that only get a minimum-size tile.
        let represented = Set(context.segments.compactMap { segment in
            segment.role == .volume ? segment.itemID : nil
        })
        let missing = container.children
            .filter { $0.kind == .apfsVolume }
            .filter { !represented.contains($0.deviceIdentifier) }
        var volumeSizes: [(id: String, bytes: UInt64)] = []
        for segment in context.segments where segment.role == .volume {
            guard let itemID = segment.itemID else { continue }
            volumeSizes.append((itemID, segment.bytes))
        }
        volumeSizes.append(contentsOf: missing.map {
            ($0.deviceIdentifier, $0.usedBytes ?? 0)
        })
        let volumeBands = volumeCapacityBands(for: volumeSizes)

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
                    let band = segment.itemID.flatMap {
                        volumeBands[$0]
                    } ?? 1
                    color = palette.volumeShade(band)
                }
            case .free:
                color = palette.free
            case .residual:
                color = palette.residual
            case .unknown:
                color = palette.unknown
            case .container:
                color = palette.fill(level: 1)
            case .partition, .unallocated, .used:
                color = palette.unallocated
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
        }

        // Unmounted or empty volumes have no area; keep them selectable in
        // the chart.
        for volume in missing {
            let isSelected = selectedVolumeID != nil
                && volume.deviceIdentifier == selectedVolumeID
            let color: Color = isSelected
                ? DiskPalette.tint(for: .apfsVolume)
                : palette.volumeShade(
                    volumeBands[volume.deviceIdentifier] ?? 1)
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

    /// Up to three capacity bands: 0 is the smallest volume and 2 the
    /// largest. Equal sizes share a band; one distinct size keeps the middle
    /// shade and two distinct sizes use the light/dark extremes.
    private func volumeCapacityBands(
        for volumes: [(id: String, bytes: UInt64)]
    ) -> [String: Int] {
        guard !volumes.isEmpty else { return [:] }
        let sizes = Set(volumes.map(\.bytes)).sorted()
        var bandBySize: [UInt64: Int] = [:]
        if sizes.count == 1 {
            bandBySize[sizes[0]] = 1
        } else if sizes.count == 2 {
            bandBySize[sizes[0]] = 0
            bandBySize[sizes[1]] = 2
        } else {
            for (index, size) in sizes.enumerated() {
                bandBySize[size] = min(2, index * 3 / sizes.count)
            }
        }

        var bands: [String: Int] = [:]
        for volume in volumes {
            bands[volume.id] = bandBySize[volume.bytes] ?? 1
        }
        return bands
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
                color: palette.usedFill,
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
                color: palette.free,
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
    let height: CGFloat
    let width: CGFloat
    let isMaximized: Bool
    var onSliceTap: ((VolumeBarSlice) -> Void)? = nil
    var fallbackItemID: String? = nil
    var itemResolver: ((String) -> KBDiskItem?)? = nil
    var onAnalyze: ((String) -> Void)? = nil

    private var clamped: Double {
        guard let fraction, fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    private var percentText: String {
        fraction == nil ? "—" : KBFormat.percent(clamped)
    }

    var body: some View {
        VolumeBarView(
                slices: slices,
                width: width,
                height: height,
                tint: tint,
                isMaximized: isMaximized,
                onTapSlice: onSliceTap,
                fallbackItemID: fallbackItemID,
                itemResolver: itemResolver,
                onAnalyze: onAnalyze)
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
