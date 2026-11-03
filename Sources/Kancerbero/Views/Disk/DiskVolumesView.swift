import AppKit
import SwiftUI
import KancerberoCore

struct DiskVolumesView: View {
    @Environment(DiskModel.self) private var disk
    @Environment(UIState.self) private var ui
    @Environment(\.byteUnitSystem) private var byteUnitSystem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onAnalyze: (String) -> Void

    private let cardSpacing: CGFloat = 12

    private var selection: Binding<String?> {
        Binding(
            get: { disk.selectedItemID },
            set: { disk.select($0) }
        )
    }

    private var layoutAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28)
    }

    private var effectiveMaximized: DiskVolumesPanel? {
        guard let requested = ui.disk.maximizedVolumesPanel else { return nil }
        switch requested {
        case .tree:
            return .tree
        case .details:
            return disk.selectedItem == nil ? nil : .details
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if !ui.cardsCollapsed(for: .disk), effectiveMaximized == nil {
                cards
                    .transition(.opacity)
            }

            Group {
                if let maximized = effectiveMaximized {
                    maximizedCard(maximized)
                        .transition(.opacity)
                } else {
                    GeometryReader { proxy in
                        columns(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(layoutAnimation, value: disk.selectedItemID)
        .animation(layoutAnimation, value: effectiveMaximized)
        .task {
            await disk.refreshInventory()
            pruneExpanded()
            expandVolumesIfNeeded()
            reconcileSelection()
            reconcileMaximize()
        }
        .onChange(of: disk.inventory?.generatedAt) { _, _ in
            pruneExpanded()
            expandVolumesIfNeeded()
            reconcileSelection()
            reconcileMaximize()
        }
        .onChange(of: ui.disk.volumesFocus) { _, _ in
            reconcileSelection()
        }
        .onChange(of: disk.selectedItemID) { _, _ in
            reconcileMaximize()
        }
        .onDisappear {
            ui.disk.maximizedVolumesPanel = nil
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func columns(width: CGFloat, height: CGFloat) -> some View {
        let hasSelection = disk.selectedItem != nil
        let usable = max(0, width - (hasSelection ? cardSpacing : 0))
        let third = usable / 3
        let treeWidth = hasSelection ? third : width
        let detailWidth = usable - third

        HStack(spacing: cardSpacing) {
            treeCard(isMaximized: false)
                .frame(width: treeWidth, height: height)

            if let item = disk.selectedItem {
                detailCard(item: item, isMaximized: false)
                    .frame(width: detailWidth, height: height)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    @ViewBuilder
    private func maximizedCard(_ panel: DiskVolumesPanel) -> some View {
        switch panel {
        case .tree:
            treeCard(isMaximized: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .details:
            if let item = disk.selectedItem {
                detailCard(item: item, isMaximized: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detailCard(item: KBDiskItem, isMaximized: Bool) -> some View {
        DiskVolumeDetailView(
            item: item,
            inventory: disk.inventory,
            onSelectItem: selectItem,
            isMaximized: isMaximized,
            onToggleMaximize: { toggleMaximize(.details) },
            onAnalyze: onAnalyze,
            onClose: closeInspector
        )
    }

    // MARK: - Cards

    private var cards: some View {
        let inventory = disk.inventory
        let disks = DiskMetrics.physicalDiskCount(inventory)
        let containers = DiskMetrics.apfsContainerCount(inventory)
        let volumes = DiskMetrics.mountedVolumeCount(inventory)
        let capacity = DiskMetrics.capacityBytes(inventory)
        let free = DiskMetrics.freeBytes(inventory)

        return LazyVGrid(columns: KBTheme.summaryColumns,
                         spacing: KBTheme.summaryGridSpacing) {
            SummaryCard(
                title: "All",
                value: KBFormat.compactCount(inventory?.allItems.count ?? 0),
                caption: "items across the tree",
                systemImage: "square.grid.2x2.fill",
                tint: Color(red: 0.42, green: 0.46, blue: 0.54),
                action: { showAll() },
                isSelected: ui.disk.volumesFocus == nil,
                filterHint: "Show all disks, containers and volumes", compact: true
            )
            SummaryCard(
                title: "Disks",
                value: "\(disks)",
                caption: "physical and virtual media",
                systemImage: "internaldrive",
                tint: Color(red: 0.94, green: 0.56, blue: 0.18),
                action: { toggleFocus(.disks) },
                isSelected: ui.disk.volumesFocus == .disks,
                filterHint: "Show only top-level media", compact: true
            )
            SummaryCard(
                title: "Containers",
                value: "\(containers)",
                caption: "APFS containers",
                systemImage: "square.stack.3d.up",
                tint: Color(red: 0.85, green: 0.65, blue: 0.20),
                action: { toggleFocus(.containers) },
                isSelected: ui.disk.volumesFocus == .containers,
                filterHint: "Show only APFS containers", compact: true
            )
            SummaryCard(
                title: "Volumes",
                value: "\(volumes)",
                caption: "mounted filesystems",
                systemImage: "externaldrive.fill",
                tint: Color(red: 0.20, green: 0.70, blue: 0.62),
                action: { toggleFocus(.volumes) },
                isSelected: ui.disk.volumesFocus == .volumes,
                filterHint: "Show only mounted volumes", compact: true
            )
            SummaryCard(
                title: "Capacity",
                value: KBFormat.bytes(capacity, units: byteUnitSystem),
                caption: "across all media",
                systemImage: "square.stack.3d.up.fill",
                tint: Color(red: 0.16, green: 0.62, blue: 0.94),
                action: { toggleFocus(.capacity) },
                isSelected: ui.disk.volumesFocus == .capacity,
                filterHint: "Show items ordered by size", compact: true
            )
            SummaryCard(
                title: "Free",
                value: KBFormat.bytes(free, units: byteUnitSystem),
                caption: "deduplicated across APFS containers",
                systemImage: "circle.dashed",
                tint: Color(red: 0.62, green: 0.42, blue: 0.95),
                action: { toggleFocus(.free) },
                isSelected: ui.disk.volumesFocus == .free,
                filterHint: "Show items with the least free space first", compact: true
            )
        }
    }

    private func treeCard(isMaximized: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Disks")
                    .font(.system(size: 11, weight: .semibold))
                if let inventory = disk.inventory {
                    Text("\(inventory.items.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
                DiskExpandButton(isMaximized: isMaximized, subject: "Disks panel") {
                    toggleMaximize(.tree)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.5)

            if let inventory = disk.inventory, !inventory.items.isEmpty {
                List(selection: selection) {
                    ForEach(displayedRows(inventory), id: \.item.deviceIdentifier) { row in
                        HStack(spacing: 6) {
                            if row.item.children.isEmpty || ui.disk.volumesFocus != nil {
                                Color.clear
                                    .frame(width: 14, height: 14)
                            } else {
                                Button {
                                    toggle(row.item.deviceIdentifier)
                                } label: {
                                    Image(systemName: ui.disk.expanded.contains(row.item.deviceIdentifier)
                                          ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .frame(width: 14, height: 14)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }

                            DiskTreeRow(item: row.item)
                        }
                        .padding(.leading, ui.disk.volumesFocus == nil ? CGFloat(row.depth) * 14 : 0)
                        .tag(row.item.deviceIdentifier)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .padding(6)
            } else if disk.isLoadingInventory {
                ProgressView("Reading disks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No disks",
                    systemImage: "internaldrive",
                    description: Text(disk.inventoryError ?? "No mounted volumes were found.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    // MARK: - Navigation

    private func toggleMaximize(_ panel: DiskVolumesPanel) {
        withAnimation(layoutAnimation) {
            ui.disk.maximizedVolumesPanel =
                ui.disk.maximizedVolumesPanel == panel ? nil : panel
        }
    }

    private func selectItem(_ id: String) {
        guard let inventory = disk.inventory,
              let item = inventory.allItems.first(where: {
                  $0.deviceIdentifier == id
              }) else { return }

        if ui.disk.volumesFocus != nil {
            ui.disk.volumesFocus = nil
        }
        revealInTree(item)
        withAnimation(layoutAnimation) {
            disk.select(id)
        }
    }

    private func closeInspector() {
        withAnimation(layoutAnimation) {
            disk.select(nil)
            ui.disk.maximizedVolumesPanel = nil
        }
    }

    private func reconcileMaximize() {
        // The inventory loads asynchronously, so the selected item cannot be
        // resolved yet on the first pass. Clearing here would drop a
        // `--volumes-maximized details` set before the row appears.
        guard disk.inventory != nil else { return }
        if ui.disk.maximizedVolumesPanel == .details,
           disk.selectedItem == nil {
            ui.disk.maximizedVolumesPanel = nil
        }
    }

    private func revealInTree(_ item: KBDiskItem) {
        guard let inventory = disk.inventory else { return }
        func expandAncestors(of id: String, in items: [KBDiskItem]) -> Bool {
            for candidate in items {
                if candidate.deviceIdentifier == id { return true }
                if expandAncestors(of: id, in: candidate.children) {
                    ui.disk.expanded.insert(candidate.deviceIdentifier)
                    return true
                }
            }
            return false
        }
        _ = expandAncestors(of: item.deviceIdentifier, in: inventory.items)
    }

    // MARK: - Tree helpers

    private struct VisibleRow {
        let item: KBDiskItem
        let depth: Int
    }

    private func visibleRows(_ items: [KBDiskItem]) -> [VisibleRow] {
        var rows: [VisibleRow] = []
        func visit(_ item: KBDiskItem, depth: Int) {
            rows.append(VisibleRow(item: item, depth: depth))
            guard ui.disk.expanded.contains(item.deviceIdentifier) else { return }
            for child in item.children {
                visit(child, depth: depth + 1)
            }
        }
        for item in items { visit(item, depth: 0) }
        return rows
    }

    private func displayedRows(_ inventory: KBDiskInventorySnapshot) -> [VisibleRow] {
        guard let focus = ui.disk.volumesFocus else { return visibleRows(inventory.items) }
        switch focus {
        case .disks:
            return inventory.items.map { VisibleRow(item: $0, depth: 0) }
        case .containers:
            return inventory.allItems
                .filter { $0.kind == .apfsContainer }
                .sorted { $0.sizeBytes > $1.sizeBytes }
                .map { VisibleRow(item: $0, depth: 0) }
        case .volumes:
            return inventory.mountedVolumes
                .sorted { $0.sizeBytes > $1.sizeBytes }
                .map { VisibleRow(item: $0, depth: 0) }
        case .capacity:
            return inventory.allItems
                .filter { $0.kind != .snapshot }
                .sorted { $0.sizeBytes > $1.sizeBytes }
                .map { VisibleRow(item: $0, depth: 0) }
        case .free:
            return inventory.allItems
                .filter { $0.freeBytes != nil }
                .sorted { ($0.freeBytes ?? 0) < ($1.freeBytes ?? 0) }
                .map { VisibleRow(item: $0, depth: 0) }
        }
    }

    private func toggleFocus(_ newFocus: DiskVolumesFocus) {
        withAnimation(.snappy(duration: 0.2)) {
            ui.disk.volumesFocus = ui.disk.volumesFocus == newFocus ? nil : newFocus
        }
    }

    private func showAll() {
        withAnimation(.snappy(duration: 0.2)) {
            ui.disk.volumesFocus = nil
        }
        expandAll()
    }

    private func expandVolumesIfNeeded() {
        guard !ui.disk.didExpandVolumesOnce, disk.inventory != nil else { return }
        expandAll()
        ui.disk.didExpandVolumesOnce = true
    }

    private func pruneExpanded() {
        guard let inventory = disk.inventory else { return }
        let ids = Set(inventory.allItems.map(\.deviceIdentifier))
        ui.disk.expanded.formIntersection(ids)
    }

    private func reconcileSelection() {
        guard let inventory = disk.inventory,
              let selected = disk.selectedItemID else { return }
        let visible = displayedRows(inventory)
            .contains { $0.item.deviceIdentifier == selected }
        if !visible {
            disk.select(nil)
        }
    }

    private func toggle(_ identifier: String) {
        if ui.disk.expanded.contains(identifier) {
            ui.disk.expanded.remove(identifier)
        } else {
            ui.disk.expanded.insert(identifier)
        }
    }

    private func expandAll() {
        guard let inventory = disk.inventory else { return }
        var identifiers = Set<String>()
        func visit(_ item: KBDiskItem) {
            if !item.children.isEmpty {
                identifiers.insert(item.deviceIdentifier)
            }
            for child in item.children { visit(child) }
        }
        for item in inventory.items { visit(item) }
        ui.disk.expanded.formUnion(identifiers)
    }
}

private struct DiskTreeRow: View {
    let item: KBDiskItem
    @Environment(\.byteUnitSystem) private var byteUnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? item.deviceIdentifier : item.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(item.deviceIdentifier)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let fileSystem = item.fileSystem {
                            Text(fileSystem)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(spaceSummary)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .help(spaceHelp)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(KBFormat.bytes(item.sizeBytes, units: byteUnitSystem))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                    if let fraction = item.volumeUsedFraction {
                        HStack(spacing: 4) {
                            CapacityBar(fraction: fraction,
                                        tint: barTint,
                                        height: 5,
                                        outline: DiskPalette.ink.opacity(0.30))
                                .frame(width: 64)
                            Text(KBFormat.percent(fraction))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            if let mount = item.mountPoint, !mount.isEmpty {
                Text(mount)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(mount)
                    .padding(.leading, 26)
            }
        }
        .padding(.vertical, 3)
    }

    /// Volumes share their container's free space, so they only report used
    /// bytes; disks, partitions and containers report used and free.
    private var spaceSummary: String {
        let usage = item.spaceUsage
        switch item.kind {
        case .apfsVolume, .snapshot:
            guard let used = usage.usedBytes else { return "—" }
            return "\(KBFormat.bytes(used, units: byteUnitSystem)) used"
        case .physicalDisk, .partition, .apfsContainer:
            guard let used = usage.usedBytes else { return "—" }
            let usedText = KBFormat.bytes(used, units: byteUnitSystem)
            guard let free = usage.freeBytes else { return "\(usedText) used" }
            return "\(usedText) used · \(KBFormat.bytes(free, units: byteUnitSystem)) free"
        }
    }

    private var spaceHelp: String {
        let usage = item.spaceUsage
        if !usage.isKnown {
            return "Usage unknown: no mounted filesystem reports capacity."
        }
        if usage.isPartial {
            return "Some volumes are not mounted; used and free space are partial."
        }
        if item.kind == .apfsVolume {
            return "Free space is shared with the APFS container."
        }
        return spaceSummary
    }

    private var icon: String {
        switch item.kind {
        case .physicalDisk: return "internaldrive"
        case .partition: return "square.split.2x1"
        case .apfsContainer: return "square.stack.3d.up"
        case .apfsVolume: return "externaldrive.fill"
        case .snapshot: return "clock.arrow.circlepath"
        }
    }

    private var barTint: Color {
        DiskPalette.tint(for: item.kind)
    }

    private var tint: Color {
        switch item.kind {
        case .physicalDisk: return Color(red: 0.94, green: 0.56, blue: 0.18)
        case .partition: return Color(red: 0.55, green: 0.45, blue: 0.92)
        case .apfsContainer: return Color(red: 0.16, green: 0.62, blue: 0.94)
        case .apfsVolume: return Color(red: 0.20, green: 0.70, blue: 0.62)
        case .snapshot: return Color(red: 0.90, green: 0.42, blue: 0.25)
        }
    }
}
