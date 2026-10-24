import AppKit
import SwiftUI
import KancerberoCore

struct DiskVolumesView: View {
    @Environment(DiskModel.self) private var disk
    @State private var expanded: Set<String> = []
    let onAnalyze: (String) -> Void

    private var selection: Binding<String?> {
        Binding(
            get: { disk.selectedItemID },
            set: { disk.select($0) }
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            cards

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
            expandAll()
        }
        .onChange(of: disk.inventory?.generatedAt) { _, _ in
            expandAll()
        }
    }

    private var cards: some View {
        let inventory = disk.inventory
        let disks = inventory?.items.count ?? 0
        let volumes = inventory?.mountedVolumes.count ?? 0
        let capacity = inventory?.items.reduce(UInt64(0)) { $0 &+ $1.sizeBytes } ?? 0
        let free = freeBytes(inventory)

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 12)],
                         spacing: 12) {
            SummaryCard(
                title: "Disks",
                value: "\(disks)",
                caption: "physical and virtual media",
                systemImage: "internaldrive",
                tint: Color(red: 0.94, green: 0.56, blue: 0.18)
            )
            SummaryCard(
                title: "Volumes",
                value: "\(volumes)",
                caption: "mounted filesystems",
                systemImage: "externaldrive.fill",
                tint: Color(red: 0.20, green: 0.70, blue: 0.62)
            )
            SummaryCard(
                title: "Capacity",
                value: KBFormat.bytes(capacity),
                caption: "across all media",
                systemImage: "square.stack.3d.up.fill",
                tint: Color(red: 0.16, green: 0.62, blue: 0.94)
            )
            SummaryCard(
                title: "Free",
                value: KBFormat.bytes(free),
                caption: "deduplicated across APFS containers",
                systemImage: "circle.dashed",
                tint: Color(red: 0.62, green: 0.42, blue: 0.95)
            )
        }
    }

    private var treeCard: some View {
        VStack(spacing: 0) {
            if let inventory = disk.inventory, !inventory.items.isEmpty {
                List(selection: selection) {
                    ForEach(visibleRows(inventory.items), id: \.item.deviceIdentifier) { row in
                        HStack(spacing: 6) {
                            if row.item.children.isEmpty {
                                Color.clear
                                    .frame(width: 14, height: 14)
                            } else {
                                Button {
                                    toggle(row.item.deviceIdentifier)
                                } label: {
                                    Image(systemName: expanded.contains(row.item.deviceIdentifier)
                                          ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .frame(width: 14, height: 14)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }

                            DiskTreeRow(item: row.item)
                        }
                        .padding(.leading, CGFloat(row.depth) * 14)
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
            guard expanded.contains(item.deviceIdentifier) else { return }
            for child in item.children {
                visit(child, depth: depth + 1)
            }
        }
        for item in items { visit(item, depth: 0) }
        return rows
    }

    private func toggle(_ identifier: String) {
        if expanded.contains(identifier) {
            expanded.remove(identifier)
        } else {
            expanded.insert(identifier)
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
        expanded.formUnion(identifiers)
    }

    private func freeBytes(_ inventory: KBDiskInventorySnapshot?) -> UInt64 {
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
