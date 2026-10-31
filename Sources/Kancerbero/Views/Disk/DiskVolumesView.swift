import AppKit
import SwiftUI
import KancerberoCore

struct DiskVolumesView: View {
    @Environment(DiskModel.self) private var disk
    @Environment(UIState.self) private var ui
    let onAnalyze: (String) -> Void

    private var selection: Binding<String?> {
        Binding(
            get: { disk.selectedItemID },
            set: { disk.select($0) }
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            if !ui.cardsCollapsed(for: .disk) {
                cards
                    .transition(.opacity)
            }

            HStack(spacing: 12) {
                treeCard

                if let item = disk.selectedItem {
                    DiskVolumeDetailView(
                        item: item,
                        onAnalyze: onAnalyze,
                        onClose: { disk.select(nil) }
                    )
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.28), value: disk.selectedItemID)
        }
        .task {
            await disk.refreshInventory()
            pruneExpanded()
            expandVolumesIfNeeded()
            reconcileSelection()
        }
        .onChange(of: disk.inventory?.generatedAt) { _, _ in
            pruneExpanded()
            expandVolumesIfNeeded()
            reconcileSelection()
        }
        .onChange(of: ui.disk.volumesFocus) { _, _ in
            reconcileSelection()
        }
    }

    private var cards: some View {
        let inventory = disk.inventory
        let disks = DiskMetrics.physicalDiskCount(inventory)
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
                filterHint: "Show all disks, containers and volumes"
            )
            SummaryCard(
                title: "Disks",
                value: "\(disks)",
                caption: "physical and virtual media",
                systemImage: "internaldrive",
                tint: Color(red: 0.94, green: 0.56, blue: 0.18),
                action: { toggleFocus(.disks) },
                isSelected: ui.disk.volumesFocus == .disks,
                filterHint: "Show only top-level media"
            )
            SummaryCard(
                title: "Volumes",
                value: "\(volumes)",
                caption: "mounted filesystems",
                systemImage: "externaldrive.fill",
                tint: Color(red: 0.20, green: 0.70, blue: 0.62),
                action: { toggleFocus(.volumes) },
                isSelected: ui.disk.volumesFocus == .volumes,
                filterHint: "Show only mounted volumes"
            )
            SummaryCard(
                title: "Capacity",
                value: KBFormat.bytes(capacity),
                caption: "across all media",
                systemImage: "square.stack.3d.up.fill",
                tint: Color(red: 0.16, green: 0.62, blue: 0.94),
                action: { toggleFocus(.capacity) },
                isSelected: ui.disk.volumesFocus == .capacity,
                filterHint: "Show items ordered by size"
            )
            SummaryCard(
                title: "Free",
                value: KBFormat.bytes(free),
                caption: "deduplicated across APFS containers",
                systemImage: "circle.dashed",
                tint: Color(red: 0.62, green: 0.42, blue: 0.95),
                action: { toggleFocus(.free) },
                isSelected: ui.disk.volumesFocus == .free,
                filterHint: "Show items with the least free space first"
            )
        }
    }

    private var treeCard: some View {
        VStack(spacing: 0) {
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? item.deviceIdentifier : item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.deviceIdentifier)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let fileSystem = item.fileSystem {
                        Text(fileSystem)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    if let mount = item.mountPoint {
                        Text(mount)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text(KBFormat.bytes(item.sizeBytes))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                if let fraction = item.volumeUsedFraction {
                    CapacityBar(fraction: fraction, tint: tint, height: 4)
                        .frame(width: 78)
                }
            }
        }
        .padding(.vertical, 2)
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
