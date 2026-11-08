import SwiftUI
import KancerberoCore

struct DiskVolumeDetailView: View {
    let item: KBDiskItem
    let inventory: KBDiskInventorySnapshot?
    var onSelectItem: ((String) -> Void)? = nil
    var isMaximized = false
    var onToggleMaximize: (() -> Void)? = nil
    let onAnalyze: (String) -> Void
    let onClose: () -> Void

    @Environment(\.byteUnitSystem) private var byteUnitSystem
    @State private var freeSelectionContainerID: String?
    @State private var hidesDetailSelection = false
    @State private var headerBlockHeight: CGFloat = 39

    private var usage: KBDiskSpaceUsage { item.spaceUsage }

    /// A container with no mounted volume reports used/free as 0 in the
    /// inventory; treat it as unknown in the stats.
    private var containerSpaceUnknown: Bool {
        item.kind == .apfsContainer && !usage.isKnown
    }

    private var usedText: String {
        containerSpaceUnknown
            ? "—"
            : (usage.usedBytes.map { KBFormat.bytes($0, units: byteUnitSystem) } ?? "—")
    }

    private var freeText: String {
        if containerSpaceUnknown { return "—" }
        if item.kind == .apfsVolume || item.kind == .snapshot {
            return item.freeBytes.map {
                KBFormat.bytes($0, units: byteUnitSystem)
            } ?? "—"
        }
        return usage.freeBytes.map {
            KBFormat.bytes($0, units: byteUnitSystem)
        } ?? "—"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content(viewportHeight: proxy.size.height)
            }
            .background {
                RoundedRectangle(cornerRadius: KBTheme.cardRadius,
                                 style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: KBTheme.cardRadius,
                                         style: .continuous)
                            .fill(LinearGradient(
                                colors: [diskTint.opacity(0.07),
                                         softTeal.opacity(0.035),
                                         .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: KBTheme.cardRadius,
                                 style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [diskTint.opacity(0.26),
                                     softTeal.opacity(0.18),
                                     Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }

    private func content(viewportHeight: CGFloat) -> some View {
        let chartHeight = max(
            0,
            viewportHeight - 28 - headerBlockHeight - 14 - 6)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                header
                softRule
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DetailHeaderBlockHeightKey.self,
                        value: proxy.size.height)
                }
            }
            if let inventory {
                VolumeHierarchyChart(
                    item: item,
                    inventory: inventory,
                    isMaximized: isMaximized,
                    onSelectItem: onSelectItem,
                    onAnalyze: onAnalyze,
                    stats: heroStats,
                    usageFraction: item.volumeUsedFraction,
                    usageCaption: usageCaption,
                    availableHeight: chartHeight,
                    selectedFreeContainerID: $freeSelectionContainerID,
                    detailSelectionHidden: $hidesDetailSelection)
            }
        }
        .padding(14)
        .onPreferenceChange(DetailHeaderBlockHeightKey.self) {
            headerBlockHeight = $0
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Clicking outside the treemap and the bar removes the detail's
            // selection highlight; the panel and its data stay visible.
            hidesDetailSelection = true
            freeSelectionContainerID = nil
        }
        .contextMenu {
            DiskItemContextMenu(item: item, onAnalyze: onAnalyze)
        }
    }

    private var diskTint: Color { AppSection.disk.tint }

    private var capacityTint: Color {
        Color(.sRGB, red: 0.161, green: 0.620, blue: 0.941, opacity: 1)
    }

    private var softTeal: Color {
        Color(.sRGB, red: 0.200, green: 0.702, blue: 0.620, opacity: 1)
    }

    private var softRule: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [diskTint.opacity(0.22),
                         softTeal.opacity(0.14),
                         .clear],
                startPoint: .leading,
                endPoint: .trailing))
            .frame(height: 1)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            // The title yields (truncates) before the chips; the chips are
            // fixed-size, so they can never wrap onto a second line.
            HStack(alignment: .center, spacing: 6) {
                diskTitleLabel
                capacityChip
                componentSummary
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            if let onToggleMaximize {
                DiskExpandButton(isMaximized: isMaximized,
                                 subject: "Details panel") {
                    onToggleMaximize()
                }
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close inspector")
        }
    }

    /// The detail title always describes the physical disk being viewed, so it
    /// stays stable while the user selects volumes or containers.
    private var scopeDisk: KBDiskItem {
        guard let inventory else { return item }
        var byID: [String: KBDiskItem] = [:]
        for entry in inventory.allItems {
            byID[entry.deviceIdentifier] = entry
        }

        var current = item
        var depth = 0
        while depth < 64,
              let parentID = current.parentID,
              let parent = byID[parentID] {
            if parent.kind == .physicalDisk { return parent }
            current = parent
            depth += 1
        }
        return item
    }

    private var diskCapacityText: String {
        let disk = scopeDisk
        return disk.sizeBytes > 0
            ? KBFormat.bytes(disk.sizeBytes, units: byteUnitSystem) : "—"
    }

    private var diskTitleLabel: some View {
        Text(displayName(scopeDisk))
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .textSelection(.enabled)
    }

    private var capacityChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "internaldrive")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(capacityTint)
            Text("Capacity")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(diskCapacityText)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(capacityTint.opacity(0.16))
        }
        .overlay {
            Capsule().strokeBorder(capacityTint.opacity(0.45),
                                   lineWidth: 0.75)
        }
        .fixedSize()
        .help("Disk capacity")
    }

    private struct ComponentCount: Identifiable {
        let id: String
        let value: Int
        let label: String
        let icon: String
        let tint: Color
    }

    private var componentSummary: some View {
        let counts = componentCounts
        return HStack(spacing: 3) {
            if counts.isEmpty {
                Text("No nested items")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                ForEach(counts) { count in
                    HStack(spacing: 3) {
                        Image(systemName: count.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(count.tint)
                        Text(count.label.capitalized)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("\(count.value)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background {
                        Capsule().fill(count.tint.opacity(0.14))
                    }
                    .overlay {
                        Capsule().strokeBorder(count.tint.opacity(0.32),
                                               lineWidth: 0.75)
                    }
                    .fixedSize()
                    .help("\(count.value) \(count.label)")
                }
            }
        }
        .frame(height: 22, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(componentAccessibilityLabel)
    }

    private var componentCounts: [ComponentCount] {
        let disk = scopeDisk
        guard disk.kind == .physicalDisk
            || disk.kind == .partition
            || disk.kind == .apfsContainer else {
            return []
        }

        var partitions = 0
        var containers = 0
        var volumes = 0

        if disk.kind == .apfsContainer {
            // Direct volumes are what the container's chart and shared-space
            // note enumerate; nested volume groups are not separate entries.
            volumes = disk.children.filter { $0.kind == .apfsVolume }.count
        } else {
            func visit(_ node: KBDiskItem) {
                switch node.kind {
                case .partition: partitions += 1
                case .apfsContainer: containers += 1
                case .apfsVolume: volumes += 1
                default: break
                }
                for child in node.children { visit(child) }
            }
            for child in disk.children { visit(child) }
        }

        var result: [ComponentCount] = []
        if partitions > 0 {
            result.append(ComponentCount(
                id: "partitions", value: partitions,
                label: partitions == 1 ? "partition" : "partitions",
                icon: "square.split.2x1",
                tint: Color(red: 0.55, green: 0.45, blue: 0.92)))
        }
        if containers > 0 {
            result.append(ComponentCount(
                id: "containers", value: containers,
                label: containers == 1 ? "container" : "containers",
                icon: "square.stack.3d.up",
                tint: Color(red: 0.16, green: 0.62, blue: 0.94)))
        }
        if volumes > 0 {
            result.append(ComponentCount(
                id: "volumes", value: volumes,
                label: volumes == 1 ? "volume" : "volumes",
                icon: "externaldrive.fill",
                tint: Color(red: 0.20, green: 0.70, blue: 0.62)))
        }
        return result
    }

    private var componentAccessibilityLabel: String {
        let counts = componentCounts
        guard !counts.isEmpty else { return "No nested items" }
        return counts.map { "\($0.value) \($0.label)" }
            .joined(separator: ", ")
    }

    private var capacityTitle: String {
        switch item.kind {
        case .physicalDisk: return "Disk capacity"
        case .partition: return "Partition capacity"
        case .apfsContainer: return "Container capacity"
        case .apfsVolume, .snapshot: return "Container capacity"
        }
    }

    private var heroStats: [VolumeHierarchyStat] {
        [
            VolumeHierarchyStat(
                id: "capacity",
                title: capacityTitle,
                value: KBFormat.bytes(item.sizeBytes, units: byteUnitSystem),
                subtitle: capacitySubtitle),
            VolumeHierarchyStat(
                id: "free",
                title: item.kind == .apfsVolume || item.kind == .snapshot
                    ? "Free (container)" : "Free",
                value: freeText),
            VolumeHierarchyStat(
                id: "used",
                title: "Used",
                value: usedText)
        ]
    }

    private var usageCaption: String {
        guard item.volumeUsedFraction != nil else { return "usage unknown" }
        return item.kind == .apfsVolume || item.kind == .snapshot
            ? "of container" : "of capacity"
    }

    /// Capacity context shown as the subtitle of the Capacity stat: who the
    /// space is shared with, plus the partial-usage caveat when it applies.
    private var capacityNotes: [String] {
        var notes: [String] = []
        switch item.kind {
        case .apfsContainer:
            let volumes = containerVolumes
            if volumes.isEmpty {
                notes.append("No volumes in this container.")
            } else {
                notes.append("Shared with \(volumes.count) volume\(volumes.count == 1 ? "" : "s")")
            }
        case .apfsVolume, .snapshot:
            if let container = inventory?.apfsContainer(enclosing: item) {
                let others = siblingVolumes(of: container)
                if others.isEmpty {
                    notes.append("Shared with \(container.deviceIdentifier)")
                } else {
                    notes.append("Shared with \(container.deviceIdentifier) and \(others.count) other volume\(others.count == 1 ? "" : "s")")
                }
            }
        case .physicalDisk, .partition:
            break
        }
        if usage.isPartial && !containerSpaceUnknown {
            notes.append("Usage is partial: some volumes are not mounted.")
        }
        return notes
    }

    private var capacitySubtitle: String? {
        let notes = capacityNotes
        return notes.isEmpty ? nil : notes.joined(separator: "\n")
    }

    private var containerVolumes: [KBDiskItem] {
        item.children
            .filter { $0.kind == .apfsVolume }
            .sorted { ($0.usedBytes ?? 0) > ($1.usedBytes ?? 0) }
    }

    private func siblingVolumes(of container: KBDiskItem) -> [KBDiskItem] {
        container.children
            .filter {
                $0.kind == .apfsVolume
                    && $0.deviceIdentifier != item.deviceIdentifier
            }
            .sorted { ($0.usedBytes ?? 0) > ($1.usedBytes ?? 0) }
    }

    private func displayName(_ item: KBDiskItem) -> String {
        item.name.isEmpty ? item.deviceIdentifier : item.name
    }
}

private struct DetailHeaderBlockHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
