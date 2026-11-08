import AppKit
import SwiftUI
import KancerberoCore

struct DiskVolumesView: View {
    @Environment(DiskModel.self) private var disk
    @Environment(UIState.self) private var ui
    @Environment(\.byteUnitSystem) private var byteUnitSystem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onAnalyze: (String) -> Void

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
        let available = hasSelection
            ? max(0, width - DiskVolumesSplit.dividerWidth)
            : width
        let fraction = DiskVolumesSplit.clampedFraction(
            ui.disk.volumesSplitFraction,
            availableWidth: available)
        let treeWidth = hasSelection
            ? (available * fraction).rounded(.toNearestOrAwayFromZero)
            : width
        let detailWidth = max(0, available - treeWidth)

        HStack(spacing: 0) {
            treeCard(isMaximized: false)
                .frame(width: treeWidth, height: height)

            if let item = disk.selectedItem {
                VolumePanelDivider(
                    height: height,
                    fraction: fraction,
                    availableWidth: available,
                    onResize: { ui.disk.volumesSplitFraction = $0 }
                )
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
                diskTables(inventory: inventory)
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

    // MARK: - Tables

    private func diskTables(inventory: KBDiskInventorySnapshot) -> some View {
        GeometryReader { proxy in
            let visibleWidth = max(0, proxy.size.width - 12)
            let layout = columnLayout(availableWidth: visibleWidth)

            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(visibleDisks(inventory)) { diskItem in
                        diskSection(diskItem,
                                    layout: layout,
                                    visibleWidth: visibleWidth)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func diskSection(_ diskItem: KBDiskItem,
                             layout: VolumeColumnLayout,
                             visibleWidth: CGFloat) -> some View {
        let expanded = ui.disk.expanded.contains(diskItem.deviceIdentifier)
        let rows = sectionRows(for: diskItem, expanded: expanded)
        let showsTable = expanded && !rows.isEmpty

        return VStack(spacing: 0) {
            diskSectionHeader(diskItem, expanded: expanded,
                              width: visibleWidth)

            if showsTable {
                Divider().opacity(0.4)
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        tableHeader(layout: layout)
                        Divider().opacity(0.5)
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()),
                                    id: \.element.item.deviceIdentifier) { pair in
                                tableRow(pair.element, index: pair.offset,
                                         layout: layout)
                            }
                        }
                    }
                    .frame(width: layout.tableWidth, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.25), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func diskSectionHeader(_ diskItem: KBDiskItem,
                                   expanded: Bool,
                                   width: CGFloat) -> some View {
        let selected = disk.selectedItemID == diskItem.deviceIdentifier
        let content = HStack(spacing: 6) {
            Color.clear
                .frame(width: 14, height: 14)

            Image(systemName: "internaldrive")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(kindTint(.physicalDisk))
                .frame(width: 14)

            Text("\(treeName(diskItem)) — \(diskItem.deviceIdentifier)")
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text("· \(diskMediaDescription(diskItem))")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.primary.opacity(0.62))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            Text("\(treeCapacityText(diskItem)) · \(treeUsedText(diskItem)) used · \(treeFreeText(diskItem)) free")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.82))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width)
        .background {
            if selected {
                Color.accentColor.opacity(0.14)
            } else {
                Color.primary.opacity(0.035)
            }
        }
        .contentShape(Rectangle())

        return Button {
            selection.wrappedValue = diskItem.deviceIdentifier
        } label: {
            content
        }
        .buttonStyle(.plain)
        .contextMenu {
            DiskItemContextMenu(item: diskItem, onAnalyze: onAnalyze)
        }
        .overlay(alignment: .leading) {
            if !diskItem.children.isEmpty
                && ui.disk.volumesFocus != .disks {
                Button {
                    toggle(diskItem.deviceIdentifier)
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .accessibilityLabel(
                    expanded
                        ? "Collapse \(treeName(diskItem)) table"
                        : "Expand \(treeName(diskItem)) table")
            }
        }
        .accessibilityLabel(
            "\(treeName(diskItem)) — \(diskItem.deviceIdentifier), "
                + "\(diskMediaDescription(diskItem)), "
                + "capacity \(treeCapacityText(diskItem)), "
                + "used \(treeUsedText(diskItem)), free \(treeFreeText(diskItem))")
        .accessibilityHint("Shows details")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func columnLayout(availableWidth: CGFloat) -> VolumeColumnLayout {
        let stored = ui.disk.volumeColumnWidths
        let name = DiskVolumeColumnWidths.clamp(
            stored.name, to: DiskVolumeColumnWidths.nameRange)
        let disk = DiskVolumeColumnWidths.clamp(
            stored.disk, to: DiskVolumeColumnWidths.diskRange)
        let type = DiskVolumeColumnWidths.clamp(
            stored.type, to: DiskVolumeColumnWidths.typeRange)
        let size = DiskVolumeColumnWidths.clamp(
            stored.size, to: DiskVolumeColumnWidths.sizeRange)
        let used = DiskVolumeColumnWidths.clamp(
            stored.used, to: DiskVolumeColumnWidths.usedRange)
        let free = DiskVolumeColumnWidths.clamp(
            stored.free, to: DiskVolumeColumnWidths.freeRange)
        let mounted = DiskVolumeColumnWidths.clamp(
            stored.mounted, to: DiskVolumeColumnWidths.mountedRange)
        let mountMinimum = DiskVolumeColumnWidths.clamp(
            stored.mountMinimum, to: DiskVolumeColumnWidths.mountMinimumRange)

        let fixed = name + disk + type + size + used + free + mounted
        let chrome = VolumeColumnMetrics.spacing * 7
            + VolumeColumnMetrics.horizontalPadding * 2
        let mount = max(mountMinimum, availableWidth - fixed - chrome)

        return VolumeColumnLayout(
            name: name,
            disk: disk,
            type: type,
            size: size,
            used: used,
            free: free,
            mounted: mounted,
            mount: mount
        )
    }

    private func tableHeader(layout: VolumeColumnLayout) -> some View {
        HStack(spacing: VolumeColumnMetrics.spacing) {
            headerCell(
                "Name", width: layout.name, alignment: .leading,
                resize: VolumeColumnResize(
                    range: DiskVolumeColumnWidths.nameRange
                ) { value in
                    ui.disk.volumeColumnWidths.name = value
                })
            headerCell(
                "Disk", width: layout.disk, alignment: .leading,
                resize: VolumeColumnResize(
                    range: DiskVolumeColumnWidths.diskRange
                ) { value in
                    ui.disk.volumeColumnWidths.disk = value
                })
            headerCell(
                "Type", width: layout.type, alignment: .leading,
                resize: VolumeColumnResize(
                    range: DiskVolumeColumnWidths.typeRange
                ) { value in
                    ui.disk.volumeColumnWidths.type = value
                })
            headerCell(
                "Size", width: layout.size, alignment: .trailing,
                resize: VolumeColumnResize(
                    range: DiskVolumeColumnWidths.sizeRange
                ) { value in
                    ui.disk.volumeColumnWidths.size = value
                })
            headerCell(
                "Used", width: layout.used, alignment: .center,
                resize: VolumeColumnResize(
                    range: DiskVolumeColumnWidths.usedRange
                ) { value in
                    ui.disk.volumeColumnWidths.used = value
                })
            headerCell(
                "Free", width: layout.free, alignment: .center,
                resize: VolumeColumnResize(
                    range: DiskVolumeColumnWidths.freeRange
                ) { value in
                    ui.disk.volumeColumnWidths.free = value
                })
            headerCell(
                "Mounted", width: layout.mounted, alignment: .center,
                resize: VolumeColumnResize(
                    range: DiskVolumeColumnWidths.mountedRange
                ) { value in
                    ui.disk.volumeColumnWidths.mounted = value
                })
            Text("Mount")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: layout.mount, alignment: .leading)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .textCase(.uppercase)
        .tracking(0.4)
        .foregroundStyle(Color.primary.opacity(0.75))
        .padding(.horizontal, VolumeColumnMetrics.horizontalPadding)
        .padding(.vertical, 6)
        .frame(width: layout.tableWidth)
        .background(.quaternary.opacity(0.12))
    }

    private func headerCell(_ title: String, width: CGFloat,
                            alignment: Alignment,
                            resize: VolumeColumnResize? = nil) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 2)
            .frame(width: width, alignment: alignment)
            .overlay(alignment: .trailing) {
                if let resize {
                    VolumeColumnResizeHandle(
                        title: title,
                        width: width,
                        range: resize.range,
                        onResize: resize.set
                    )
                }
            }
    }

    private func tableRow(_ row: VisibleRow, index: Int,
                          layout: VolumeColumnLayout) -> some View {
        let item = row.item
        let selected = disk.selectedItemID == item.deviceIdentifier
        let focused = ui.disk.volumesFocus != nil
        let expanded = ui.disk.expanded.contains(item.deviceIdentifier)

        let content = HStack(alignment: .center,
                             spacing: VolumeColumnMetrics.spacing) {
            HStack(alignment: .center, spacing: 4) {
                Color.clear
                    .frame(width: 14, height: 14)

                Image(systemName: kindIcon(item.kind))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(kindTint(item.kind))
                    .frame(width: 14)

                Text(treeName(item))
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(treeName(item))
            }
            .frame(width: layout.name, alignment: .leading)

            Text(item.deviceIdentifier)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: layout.disk, alignment: .leading)

            Text(typeLabel(item))
                .font(.system(size: 10.5))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: layout.type, alignment: .leading)
                .help(typeHelp(item))

            Text(KBFormat.bytes(item.sizeBytes, units: byteUnitSystem))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: layout.size, alignment: .trailing)
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
            .frame(width: layout.used, alignment: .trailing)
            .help(usedHelp(item))

            Text(treeFreeText(item))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: layout.free, alignment: .trailing)
                .help(freeHelp(item))

            Text(mountedText(item))
                .font(.system(size: 10.5))
                .foregroundStyle(mountedColor(item))
                .lineLimit(1)
                .frame(width: layout.mounted, alignment: .center)
                .help(mountedHelp(item))

            Text(item.mountPoint ?? "—")
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: layout.mount, alignment: .leading)
                .help(item.mountPoint ?? "No mount point")
        }
        .padding(.horizontal, VolumeColumnMetrics.horizontalPadding)
        .padding(.vertical, 4)
        .frame(width: layout.tableWidth)
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
        .contextMenu {
            DiskItemContextMenu(item: item, onAnalyze: onAnalyze)
        }
        .overlay(alignment: .leading) {
            if !item.children.isEmpty && !focused {
                Button {
                    toggle(item.deviceIdentifier)
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
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

    private func treeUsedText(_ item: KBDiskItem) -> String {
        guard let used = item.spaceUsage.usedBytes else { return "—" }
        return KBFormat.bytes(used, units: byteUnitSystem)
    }

    private func treeCapacityText(_ item: KBDiskItem) -> String {
        guard item.sizeBytes > 0 else { return "—" }
        return KBFormat.bytes(item.sizeBytes, units: byteUnitSystem)
    }

    private func diskMediaDescription(_ item: KBDiskItem) -> String {
        if item.isInternal == true { return "Internal" }

        let model = item.deviceModel?.lowercased() ?? ""
        let name = item.name.lowercased()
        let protocolName = item.deviceProtocol?.lowercased() ?? ""
        if model.contains("disk image")
            || name.contains("disk image")
            || protocolName.contains("virtual interface") {
            return "Disk Image"
        }

        let bus = item.busName?.lowercased() ?? ""
        if protocolName.contains("usb") || bus.contains("usb") {
            return "USB"
        }
        if item.isRemovable == true { return "Removable" }
        if let protocolName = item.deviceProtocol, !protocolName.isEmpty {
            return protocolName
        }
        return item.isInternal == false ? "External" : "Disk"
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

    private func kindShortName(_ kind: KBDiskItemKind) -> String {
        switch kind {
        case .physicalDisk: return "Disk"
        case .partition: return "Partition"
        case .apfsContainer: return "Container"
        case .apfsVolume: return "Volume"
        case .snapshot: return "Snapshot"
        }
    }

    private func typeLabel(_ item: KBDiskItem) -> String {
        let kind = kindShortName(item.kind)
        guard let fileSystem = fileSystemLabel(displayFileSystem(for: item)) else {
            return kind
        }
        return "\(kind) \(fileSystem)"
    }

    private func typeHelp(_ item: KBDiskItem) -> String {
        guard let fileSystem = displayFileSystem(for: item), !fileSystem.isEmpty else {
            return item.kind.displayName
        }
        return "\(item.kind.displayName) · \(fileSystem)"
    }

    /// Partitions that host an APFS container do not report their own
    /// filesystem; reuse the container's so Type reads "Partition APFS".
    private func displayFileSystem(for item: KBDiskItem) -> String? {
        if let fileSystem = item.fileSystem {
            return fileSystem
        }
        guard item.kind == .partition else { return nil }
        return item.children.first { $0.kind == .apfsContainer }?.fileSystem
    }

    private func fileSystemLabel(_ fileSystem: String?) -> String? {
        guard let fileSystem else { return nil }
        let trimmed = fileSystem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed.lowercased() {
        case "apfs": return "APFS"
        case "hfs": return "HFS"
        case "msdos": return "MS-DOS"
        case "exfat": return "exFAT"
        case "ntfs": return "NTFS"
        default: return trimmed.uppercased()
        }
    }

    private func isMountable(_ kind: KBDiskItemKind) -> Bool {
        kind == .apfsVolume || kind == .snapshot
    }

    private func mountStatus(_ item: KBDiskItem) -> Bool? {
        guard isMountable(item.kind) else { return nil }
        return item.mountPoint?.isEmpty == false
    }

    private func mountedText(_ item: KBDiskItem) -> String {
        guard let mounted = mountStatus(item) else { return "—" }
        return mounted ? "Yes" : "No"
    }

    private func mountedColor(_ item: KBDiskItem) -> Color {
        guard let mounted = mountStatus(item) else {
            return Color.secondary.opacity(0.6)
        }
        return mounted ? .primary : .secondary
    }

    private func mountedHelp(_ item: KBDiskItem) -> String {
        guard let mounted = mountStatus(item) else {
            return "This object type does not report a mount state"
        }
        guard mounted else { return "Not mounted" }
        return "Mounted at \(item.mountPoint ?? "unknown path")"
    }

    private func mountedAccessibilityText(_ item: KBDiskItem) -> String {
        guard let mounted = mountStatus(item) else { return "not applicable" }
        return mounted ? "yes" : "no"
    }

    private func rowAccessibilityLabel(_ item: KBDiskItem) -> String {
        let percent = usageFraction(for: item).map(KBFormat.percent)
        let used = percent.map { "\(treeUsedText(item)) (\($0))" }
            ?? treeUsedText(item)
        let fileSystem = displayFileSystem(for: item)
            .map { ", filesystem \($0)" } ?? ""
        return "\(treeName(item)), device \(item.deviceIdentifier), "
            + "type \(item.kind.displayName)\(fileSystem), "
            + "size \(KBFormat.bytes(item.sizeBytes, units: byteUnitSystem)), "
            + "used \(used), free \(treeFreeText(item)), "
            + "mounted \(mountedAccessibilityText(item)), "
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

    private func visibleDisks(_ inventory: KBDiskInventorySnapshot) -> [KBDiskItem] {
        guard let focus = ui.disk.volumesFocus else {
            return inventory.items
        }
        if focus == .disks { return inventory.items }
        return inventory.items.filter {
            !focusedRows(for: $0, focus: focus).isEmpty
        }
    }

    private func sectionRows(for diskItem: KBDiskItem,
                             expanded: Bool) -> [VisibleRow] {
        guard expanded else { return [] }
        guard let focus = ui.disk.volumesFocus else {
            return visibleRows(diskItem.children)
        }
        if focus == .disks { return [] }
        return focusedRows(for: diskItem, focus: focus)
    }

    private func focusedRows(for diskItem: KBDiskItem,
                             focus: DiskVolumesFocus) -> [VisibleRow] {
        var descendants: [KBDiskItem] = []
        func visit(_ node: KBDiskItem) {
            descendants.append(node)
            for child in node.children { visit(child) }
        }
        for child in diskItem.children { visit(child) }

        let filtered: [KBDiskItem]
        switch focus {
        case .disks:
            return []
        case .containers:
            filtered = descendants
                .filter { $0.kind == .apfsContainer }
                .sorted { $0.sizeBytes > $1.sizeBytes }
        case .volumes:
            filtered = descendants
                .filter { $0.mountPoint?.isEmpty == false }
                .sorted { $0.sizeBytes > $1.sizeBytes }
        case .capacity:
            filtered = descendants
                .filter { $0.kind != .snapshot }
                .sorted { $0.sizeBytes > $1.sizeBytes }
        case .free:
            filtered = descendants
                .filter { $0.freeBytes != nil }
                .sorted { ($0.freeBytes ?? 0) < ($1.freeBytes ?? 0) }
        }
        return filtered.map { VisibleRow(item: $0, depth: 0) }
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

        let visible: Bool
        if let focus = ui.disk.volumesFocus {
            if focus == .disks {
                visible = inventory.items.contains {
                    $0.deviceIdentifier == selected
                }
            } else {
                visible = inventory.items.contains { diskItem in
                    focusedRows(for: diskItem, focus: focus).contains {
                        $0.item.deviceIdentifier == selected
                    }
                }
            }
        } else {
            visible = inventory.allItems.contains {
                $0.deviceIdentifier == selected
            }
        }
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

// MARK: - Column metrics

private enum VolumeColumnMetrics {
    static let spacing: CGFloat = 5
    static let horizontalPadding: CGFloat = 6
    static let handleWidth: CGFloat = 9
}

private struct VolumeColumnLayout {
    let name: CGFloat
    let disk: CGFloat
    let type: CGFloat
    let size: CGFloat
    let used: CGFloat
    let free: CGFloat
    let mounted: CGFloat
    let mount: CGFloat

    var tableWidth: CGFloat {
        name + disk + type + size + used + free + mounted + mount
            + VolumeColumnMetrics.spacing * 7
            + VolumeColumnMetrics.horizontalPadding * 2
    }
}

private struct VolumeColumnResize {
    let range: ClosedRange<CGFloat>
    let set: (CGFloat) -> Void
}

private struct VolumeColumnResizeHandle: View {
    let title: String
    let width: CGFloat
    let range: ClosedRange<CGFloat>
    let onResize: (CGFloat) -> Void

    @State private var startWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering
                  ? Color.accentColor.opacity(0.8)
                  : Color.primary.opacity(0.18))
            .frame(width: 0.75)
            .frame(width: VolumeColumnMetrics.handleWidth, alignment: .trailing)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil {
                            startWidth = width
                        }
                        let next = DiskVolumeColumnWidths.clamp(
                            base + value.translation.width, to: range)
                        if next != width {
                            onResize(next)
                        }
                    }
                    .onEnded { _ in
                        startWidth = nil
                    }
            )
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .help("Drag to resize the \(title.lowercased()) column")
            .accessibilityLabel("Resize \(title) column")
            .accessibilityHint("Drag left or right")
    }
}

private struct VolumePanelDivider: View {
    let height: CGFloat
    let fraction: CGFloat
    let availableWidth: CGFloat
    let onResize: (CGFloat) -> Void

    @State private var startFraction: CGFloat?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(hovering
                      ? Color.accentColor.opacity(0.8)
                      : Color.primary.opacity(0.18))
                .frame(width: 1)
            Capsule()
                .fill(hovering
                      ? Color.accentColor.opacity(0.9)
                      : Color.primary.opacity(0.22))
                .frame(width: 3, height: 36)
        }
        .frame(width: DiskVolumesSplit.dividerWidth, height: height)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let base = startFraction ?? fraction
                    if startFraction == nil {
                        startFraction = fraction
                    }
                    guard availableWidth > 0 else { return }
                    let candidate = base
                        + value.translation.width / availableWidth
                    let next = DiskVolumesSplit.clampedFraction(
                        candidate, availableWidth: availableWidth)
                    if next != fraction {
                        onResize(next)
                    }
                }
                .onEnded { _ in
                    startFraction = nil
                }
        )
        .onHover { inside in
            hovering = inside
            (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
        }
        .onDisappear {
            NSCursor.arrow.set()
        }
        .help("Drag to resize the panels")
        .accessibilityLabel("Resize disk panels")
        .accessibilityHint("Drag left or right")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}
