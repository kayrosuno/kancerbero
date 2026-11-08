import SwiftUI
import KancerberoCore

enum DiskItemInfoWindow {
    static let id = "disk-item-info"
}

/// Resolves the requested item from the live inventory and hosts its info in
/// its own window. Each device identifier gets an independent window.
struct DiskItemInfoWindowView: View {
    let itemID: String?

    @Environment(DiskModel.self) private var disk
    @AppStorage(KBPreferences.diskUnitSystemKey)
    private var storedUnitSystem = KBPreferences.diskUnitSystemDefault

    private var unitSystem: KBByteUnitSystem {
        KBByteUnitSystem.fromCommandLine()
            ?? KBByteUnitSystem(rawValue: storedUnitSystem)
            ?? .decimal
    }

    private var item: KBDiskItem? {
        guard let itemID else { return nil }
        return disk.inventory?.allItems.first {
            $0.deviceIdentifier == itemID
        }
    }

    var body: some View {
        Group {
            if let item {
                DiskItemInfoView(item: item, inventory: disk.inventory)
                    .environment(\.byteUnitSystem, unitSystem)
            } else {
                ContentUnavailableView(
                    "Item unavailable",
                    systemImage: "internaldrive",
                    description: Text(itemID.map {
                        "\($0) is no longer in the disk inventory."
                    } ?? "No disk item was requested."))
            }
        }
        .frame(minWidth: 440, minHeight: 420)
    }
}

/// Metadata panel shown by the Get Info window.
struct DiskItemInfoView: View {
    let item: KBDiskItem
    let inventory: KBDiskInventorySnapshot?

    @Environment(\.byteUnitSystem) private var byteUnitSystem

    private var usage: KBDiskSpaceUsage { item.spaceUsage }

    /// A container with no mounted volume reports used/free as 0 in the
    /// inventory; treat it as unknown here too.
    private var containerSpaceUnknown: Bool {
        item.kind == .apfsContainer && !usage.isKnown
    }

    private var usedText: String {
        containerSpaceUnknown
            ? "—"
            : (usage.usedBytes.map {
                KBFormat.bytes($0, units: byteUnitSystem)
            } ?? "—")
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

    /// "Shared with" list for containers and volumes; snapshots are omitted.
    private var sharedWithEntries: [String]? {
        guard let inventory else { return nil }
        switch item.kind {
        case .apfsContainer:
            let volumes = containerVolumes
            guard !volumes.isEmpty else { return nil }
            return volumes.map { "\(displayName($0)) (\($0.deviceIdentifier))" }
        case .apfsVolume:
            guard let container = inventory.apfsContainer(enclosing: item) else {
                return nil
            }
            var entries = ["\(container.deviceIdentifier) · \(displayName(container))"]
            entries.append(contentsOf: siblingVolumes(of: container).map {
                "\(displayName($0)) (\($0.deviceIdentifier))"
            })
            return entries
        default:
            return nil
        }
    }

    private var sharedWithText: String? {
        guard let entries = sharedWithEntries else { return nil }
        let visible = entries.prefix(6)
        var text = visible.joined(separator: ", ")
        if entries.count > visible.count {
            text += " and \(entries.count - visible.count) more"
        }
        return text
    }

    private var sharedWithHelp: String? {
        sharedWithEntries?.joined(separator: ", ")
    }

    private func displayName(_ item: KBDiskItem) -> String {
        item.name.isEmpty ? item.deviceIdentifier : item.name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider().opacity(0.5)
                metadata
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(displayName(item))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayName(item))
                .font(.system(size: 17, weight: .semibold,
                              design: .rounded))
                .lineLimit(2)
                .textSelection(.enabled)
            Text("\(item.deviceIdentifier) · \(item.kind.displayName)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
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
                item.availableBytes.map {
                    KBFormat.bytes($0, units: byteUnitSystem)
                } ?? "—")
            if let sharedWithText {
                row("Shared with", sharedWithText,
                    lineLimit: 4, help: sharedWithHelp)
            }
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
                     path: Bool = false, lineLimit: Int? = nil,
                     help: String? = nil) -> some View {
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
                .lineLimit(lineLimit ?? (path ? 2 : 3))
                .truncationMode(.middle)
                .help(help ?? value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func yesNo(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "Yes" : "No"
    }
}
