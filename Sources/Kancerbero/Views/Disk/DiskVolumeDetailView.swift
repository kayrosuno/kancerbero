import AppKit
import SwiftUI
import KancerberoCore

struct DiskVolumeDetailView: View {
    let item: KBDiskItem
    let onAnalyze: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider().opacity(0.5)
                stats
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
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KBTheme.gradient(AppSection.disk.tint))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? item.deviceIdentifier : item.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text("\(item.kind.displayName) · \(item.deviceIdentifier)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

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
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                stat("Capacity", KBFormat.bytes(item.sizeBytes))
                stat("Used", item.usedBytes.map(KBFormat.bytes) ?? "—")
                stat("Free", item.freeBytes.map(KBFormat.bytes) ?? "—")
            }
            if item.kind == .apfsVolume || item.kind == .apfsContainer {
                Text("APFS volumes share the container's free space.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
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
            row("Mount point", item.mountPoint ?? "Not mounted")
            row("Used", item.usedBytes.map(KBFormat.bytes) ?? "—")
            row(item.kind == .apfsVolume || item.kind == .apfsContainer
                ? "Free (container)" : "Free",
                item.freeBytes.map(KBFormat.bytes) ?? "—")
            row(item.kind == .apfsVolume || item.kind == .apfsContainer
                ? "Available (container)" : "Available",
                item.availableBytes.map(KBFormat.bytes) ?? "—")
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

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .textSelection(.enabled)
                .lineLimit(3)
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
