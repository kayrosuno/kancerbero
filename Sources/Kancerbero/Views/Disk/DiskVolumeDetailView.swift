import AppKit
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider().opacity(0.5)
                if let inventory {
                    VolumeHierarchyChart(
                        item: item,
                        inventory: inventory,
                        isMaximized: isMaximized,
                        onSelectItem: onSelectItem,
                        stats: heroStats,
                        usageFraction: item.volumeUsedFraction,
                        usageCaption: usageCaption,
                        notes: structureNotes)
                }
                Divider().opacity(0.5)
                metadata
                Divider().opacity(0.5)
                actions
            }
            .padding(14)
        }
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [kindTint.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [kindTint.opacity(0.42),
                                 kindTint.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if let parent = parentItem, let onSelectItem {
                Button { onSelectItem(parent.deviceIdentifier) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(kindTint)
                        .frame(width: 24, height: 24)
                        .background {
                            Circle().fill(kindTint.opacity(0.12))
                        }
                        .overlay {
                            Circle().strokeBorder(kindTint.opacity(0.32),
                                                  lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Up to \(parent.name.isEmpty ? parent.deviceIdentifier : parent.name)")
                .accessibilityLabel("Up one level")
            }

            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(KBTheme.gradient(kindTint))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? item.deviceIdentifier : item.name)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .textSelection(.enabled)
                Text("\(item.kind.displayName) · \(item.deviceIdentifier)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

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

    private var heroStats: [VolumeHierarchyStat] {
        [
            VolumeHierarchyStat(
                id: "capacity",
                title: "Capacity",
                value: KBFormat.bytes(item.sizeBytes, units: byteUnitSystem)),
            VolumeHierarchyStat(
                id: "used",
                title: "Used",
                value: usedText),
            VolumeHierarchyStat(
                id: "free",
                title: item.kind == .apfsVolume || item.kind == .snapshot
                    ? "Free (container)" : "Free",
                value: freeText)
        ]
    }

    private var usageCaption: String {
        guard item.volumeUsedFraction != nil else { return "usage unknown" }
        return item.kind == .apfsVolume || item.kind == .snapshot
            ? "of container" : "of capacity"
    }

    private var structureNotes: [String] {
        var notes: [String] = []
        if usage.isPartial && !containerSpaceUnknown {
            notes.append("Some volumes are not mounted; used and free space are partial.")
        }
        if item.kind == .apfsVolume || item.kind == .apfsContainer {
            notes.append("APFS volumes share the container's free space.")
        }
        return notes
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 7) {
            row("Kind", item.kind.displayName)
            row("Identifier", item.deviceIdentifier)
            row("Filesystem", item.fileSystem ?? "—")
            if let content = item.content {
                row("Content", content)
            }
            row("Mount point", item.mountPoint ?? "Not mounted",
                path: item.mountPoint != nil)
            row("Used", usedText)
            row(item.kind == .apfsVolume || item.kind == .apfsContainer
                ? "Free (container)" : "Free",
                freeText)
            row(item.kind == .apfsVolume || item.kind == .apfsContainer
                ? "Available (container)" : "Available",
                item.availableBytes.map { KBFormat.bytes($0, units: byteUnitSystem) } ?? "—")
            row("Volume UUID", item.volumeUUID ?? "—")
            row("Media UUID", item.mediaUUID ?? "—")
            if let group = item.volumeGroupUUID {
                row("APFS group", group)
            }
            if !item.roles.isEmpty {
                row("APFS roles", item.roles.joined(separator: ", "))
            }
            row("Model", item.deviceModel ?? "—")
            row("Protocol", item.deviceProtocol ?? "—")
            row("Bus", item.busName ?? "—")
            row("Internal", yesNo(item.isInternal))
            row("Removable", yesNo(item.isRemovable))
            row("Writable", yesNo(item.isWritable))
            row("Encrypted", yesNo(item.isEncrypted))
            row("SMART", "Unavailable via public APIs")
        }
    }

    private func row(_ title: String, _ value: String,
                     path: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 11,
                              design: path ? .monospaced : .default))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(path ? 2 : 3)
                .truncationMode(.middle)
                .help(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Button {
                    if let mount = item.mountPoint {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            URL(fileURLWithPath: mount)
                        ])
                    }
                } label: {
                    Label("Reveal", systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(item.mountPoint == nil)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.deviceIdentifier, forType: .string)
                } label: {
                    Label("Copy ID", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                if let mount = item.mountPoint {
                    onAnalyze(mount)
                }
            } label: {
                Label("Analyze this volume", systemImage: "chart.pie")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppSection.disk.tint)
            .disabled(item.mountPoint == nil)
        }
    }

    private var parentItem: KBDiskItem? {
        guard let parentID = item.parentID else { return nil }
        return inventory?.allItems.first {
            $0.deviceIdentifier == parentID
        }
    }

    private var kindTint: Color {
        switch item.kind {
        case .physicalDisk: return Color(red: 0.94, green: 0.56, blue: 0.18)
        case .partition: return Color(red: 0.55, green: 0.45, blue: 0.92)
        case .apfsContainer: return Color(red: 0.16, green: 0.62, blue: 0.94)
        case .apfsVolume: return Color(red: 0.20, green: 0.70, blue: 0.62)
        case .snapshot: return Color(red: 0.90, green: 0.42, blue: 0.25)
        }
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

    private func yesNo(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "Yes" : "No"
    }
}
