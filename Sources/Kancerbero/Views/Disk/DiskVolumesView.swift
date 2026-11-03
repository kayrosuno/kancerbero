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
    private let tableMinWidth: CGFloat = 420
    private let sizeColumnWidth: CGFloat = 54
    private let usedColumnWidth: CGFloat = 56
    private let freeColumnWidth: CGFloat = 56
    private let mountColumnWidth: CGFloat = 64

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
                treeTable(inventory: inventory)
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

    // MARK: - Table

    private func treeTable(inventory: KBDiskInventorySnapshot) -> some View {
        GeometryReader { proxy in
            let tableWidth = max(proxy.size.width, tableMinWidth)
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    tableHeader(width: tableWidth)
                    Divider().opacity(0.5)
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                let rows = displayedRows(inventory)
                                ForEach(Array(rows.enumerated()),
                                        id: \.element.item.deviceIdentifier) { pair in
                                    tableRow(pair.element, index: pair.offset,
                                             width: tableWidth)
                                        .id(pair.element.item.deviceIdentifier)
                                }
                            }
                        }
                        .onChange(of: disk.selectedItemID) { _, id in
                            guard let id else { return }
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                                scrollProxy.scrollTo(id, anchor: .center)
                            }
                        }
                        .onAppear {
                            guard let id = disk.selectedItemID else { return }
                            DispatchQueue.main.async {
                                scrollProxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                .frame(width: tableWidth, height: proxy.size.height,
                       alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
    }

    private func tableHeader(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text("Name")
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: sizeColumnWidth, alignment: .trailing)
            Text("Used")
                .frame(width: usedColumnWidth, alignment: .trailing)
            Text("Free")
                .frame(width: freeColumnWidth, alignment: .trailing)
            Text("Mount")
                .frame(minWidth: mountColumnWidth, maxWidth: .infinity,
                       alignment: .leading)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .textCase(.uppercase)
        .tracking(0.4)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width)
        .background(.quaternary.opacity(0.12))
    }

    private func tableRow(_ row: VisibleRow, index: Int,
                          width: CGFloat) -> some View {
        let item = row.item
        let selected = disk.selectedItemID == item.deviceIdentifier
        let focused = ui.disk.volumesFocus != nil
        let expanded = ui.disk.expanded.contains(item.deviceIdentifier)
        let indent = focused ? 0 : CGFloat(row.depth) * 10

        let content = HStack(alignment: .center, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                Color.clear
                    .frame(width: 14, height: 14)

                Image(systemName: kindIcon(item.kind))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(kindTint(item.kind))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 0) {
                    Text(treeName(item))
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(treeSecondaryLabel(item))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help("\(treeName(item)) · \(treeSecondaryLabel(item))")
            }
            .padding(.leading, indent)
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            Text(KBFormat.bytes(item.sizeBytes, units: byteUnitSystem))
                .font(.system(size: 9.5))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: sizeColumnWidth, alignment: .trailing)
                .help(item.kind == .apfsVolume
                      ? "The volume's size is its container's capacity"
                      : "Capacity")

            VStack(alignment: .trailing, spacing: 2) {
                Text(treeUsedText(item))
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let fraction = usageFraction(for: item) {
                    CapacityBar(
                        fraction: fraction,
                        tint: DiskPalette.tint(for: item.kind),
                        height: 3,
                        outline: DiskPalette.ink.opacity(0.25),
                        accessibilityLabel: item.kind == .apfsVolume
                            ? "Share of container used" : "Capacity used")
                        .frame(width: 36)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: usedColumnWidth, alignment: .trailing)
            .help(usedHelp(item))

            Text(treeFreeText(item))
                .font(.system(size: 9.5))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: freeColumnWidth, alignment: .trailing)
                .help(freeHelp(item))

            Text(item.mountPoint ?? "—")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: mountColumnWidth, maxWidth: .infinity,
                       alignment: .leading)
                .help(item.mountPoint ?? "No mount point")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(width: width)
        .background {
            if selected {
                Color.accentColor.opacity(0.14)
            } else if index.isMultiple(of: 2) {
                Color.secondary.opacity(0.04)
            }
        }
        .contentShape(Rectangle())

        return Button {
            selection.wrappedValue = item.deviceIdentifier
        } label: {
            content
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            if !item.children.isEmpty && !focused {
                Button {
                    toggle(item.deviceIdentifier)
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, 8 + indent)
                .accessibilityLabel(
                    expanded
                        ? "Collapse \(treeName(item))"
                        : "Expand \(treeName(item))")
            }
        }
        .accessibilityLabel(rowAccessibilityLabel(item))
        .accessibilityHint("Shows details")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func treeName(_ item: KBDiskItem) -> String {
        item.name.isEmpty ? item.deviceIdentifier : item.name
    }

    private func treeSecondaryLabel(_ item: KBDiskItem) -> String {
        "\(item.deviceIdentifier) · \(item.fileSystem ?? "—")"
    }

    private func treeUsedText(_ item: KBDiskItem) -> String {
        guard let used = item.spaceUsage.usedBytes else { return "—" }
        return KBFormat.bytes(used, units: byteUnitSystem)
    }

    private func treeFreeText(_ item: KBDiskItem) -> String {
        guard item.kind != .apfsVolume, item.kind != .snapshot else {
            return "—"
        }
        guard let free = item.spaceUsage.freeBytes else { return "—" }
        return KBFormat.bytes(free, units: byteUnitSystem)
    }

    private func usedHelp(_ item: KBDiskItem) -> String {
        guard let fraction = usageFraction(for: item) else {
            return "Usage unavailable"
        }
        return item.kind == .apfsVolume
            ? "Bar: share of the container's used space (\(KBFormat.percent(fraction)))"
            : "Bar: used / capacity (\(KBFormat.percent(fraction)))"
    }

    private func freeHelp(_ item: KBDiskItem) -> String {
        if item.kind == .apfsVolume || item.kind == .snapshot {
            return "Free space is shared with the APFS container; see the container row."
        }
        if item.spaceUsage.isPartial {
            return "Aggregated free space; some volumes are not mounted, so the value is partial."
        }
        return "Free space"
    }

    private func rowAccessibilityLabel(_ item: KBDiskItem) -> String {
        let percent = usageFraction(for: item).map(KBFormat.percent)
        let used = percent.map { "\(treeUsedText(item)) (\($0))" }
            ?? treeUsedText(item)
        return "\(treeName(item)), \(item.kind.displayName), "
            + "size \(KBFormat.bytes(item.sizeBytes, units: byteUnitSystem)), "
            + "used \(used), free \(treeFreeText(item)), "
            + "mount \(item.mountPoint ?? "none")"
    }

    private func kindIcon(_ kind: KBDiskItemKind) -> String {
        switch kind {
        case .physicalDisk: return "internaldrive"
        case .partition: return "square.split.2x1"
        case .apfsContainer: return "square.stack.3d.up"
        case .apfsVolume: return "externaldrive.fill"
        case .snapshot: return "clock.arrow.circlepath"
        }
    }

    private func kindTint(_ kind: KBDiskItemKind) -> Color {
        switch kind {
        case .physicalDisk: return Color(red: 0.94, green: 0.56, blue: 0.18)
        case .partition: return Color(red: 0.55, green: 0.45, blue: 0.92)
        case .apfsContainer: return Color(red: 0.16, green: 0.62, blue: 0.94)
        case .apfsVolume: return Color(red: 0.20, green: 0.70, blue: 0.62)
        case .snapshot: return Color(red: 0.90, green: 0.42, blue: 0.25)
        }
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

    private func expandVolumesIfNeeded() {
        guard !ui.disk.didExpandVolumesOnce, disk.inventory != nil else { return }
        expandAll()
        ui.disk.didExpandVolumesOnce = true
    }

    private func pruneExpanded() {        guard let inventory = disk.inventory else { return }
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

    /// Volumes report their share of the container's used space; the rest of
    /// the rows keep used / capacity.
    private func usageFraction(for item: KBDiskItem) -> Double? {
        guard item.kind == .apfsVolume,
              let inventory = disk.inventory,
              let container = inventory.apfsContainer(enclosing: item) else {
            return item.volumeUsedFraction
        }

        if let containerUsed = container.spaceUsage.usedBytes,
           containerUsed > 0,
           let used = item.usedBytes {
            return min(1, Double(used) / Double(containerUsed))
        }

        let siblings = container.children.filter { $0.kind == .apfsVolume }
        var sum: UInt64 = 0
        for sibling in siblings {
            guard let used = sibling.usedBytes else { continue }
            let (next, overflow) = sum.addingReportingOverflow(used)
            sum = overflow ? UInt64.max : next
        }
        guard let used = item.usedBytes, sum > 0 else { return nil }
        return min(1, Double(used) / Double(sum))
    }
}
