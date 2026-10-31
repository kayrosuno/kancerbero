import AppKit
import SwiftUI
import KancerberoCore

struct LeftoversPanel: View {
    @Environment(ApplicationsModel.self) private var model
    let onClose: () -> Void
    let onTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().opacity(0.4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if let bundle = model.selectedBundle {
                        appRow(bundle)
                    }
                    if model.isScanningLeftovers, model.leftovers.isEmpty {
                        ProgressView("Looking for related files…")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    } else if model.leftovers.isEmpty {
                        Text("No related files found")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(model.leftovers) { item in
                            fileRow(item)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Divider().opacity(0.4)
            footer
        }
        .padding(14)
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
        let bundle = model.selectedBundle
        return HStack(alignment: .center, spacing: 10) {
            if let bundle {
                Image(nsImage: ApplicationsTable.icon(for: bundle.path))
                    .resizable()
                    .frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(bundle?.name ?? "Selection")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(bundle?.bundleIdentifier ?? "—")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if let bundle, bundle.isProtected {
                Label("Protected", systemImage: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text(bundle?.version.map { "v\($0)" } ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
        }
    }

    /// First entry, like AppCleaner: the application bundle itself. Its check
    /// is always on and cannot be unchecked.
    private func appRow(_ bundle: KBAppBundle) -> some View {
        HStack(spacing: 10) {
            Image(systemName: bundle.isProtected ? "lock.square.fill" : "checkmark.square.fill")
                .font(.system(size: 15))
                .foregroundStyle(bundle.isProtected ? Color.secondary : Color.accentColor)
                .frame(width: 16)
                .help(bundle.isProtected
                    ? "Protected by macOS"
                    : "The application is always removed")

            Image(nsImage: ApplicationsTable.icon(for: bundle.path))
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(bundle.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(abbreviated(bundle.path))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            Text(bundle.sizeBytes.map { KBFormat.bytes($0) } ?? "—")
                .font(.system(size: 12, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func fileRow(_ item: KBLeftover) -> some View {
        let checked = model.checkedLeftovers.contains(item.path)
        let name = (item.path as NSString).lastPathComponent
        return HStack(spacing: 10) {
            Button {
                model.toggleLeftover(item.path)
            } label: {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(checked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16)
            .accessibilityLabel(item.kind.title)

            Image(nsImage: Self.fileIcon(for: item.path))
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if item.requiresPrivilege {
                        Text("admin")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                            .help("Needs the root daemon")
                    }
                }
                Text(abbreviated(item.path))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path)
            }

            Spacer(minLength: 4)

            Text(item.sizeBytes.map { KBFormat.bytes($0) } ?? "—")
                .font(.system(size: 12, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private var footer: some View {
        let bundle = model.selectedBundle
        let appCount = bundle?.isProtected == false ? 1 : 0
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                Text("\(appCount) app + \(model.selectedLeftovers.count) files selected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(KBFormat.bytes(model.selectedBytes))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(KBTheme.gradient(Color.accentColor))
            }

            Spacer(minLength: 4)

            Button("Reveal") {
                if let bundle = model.selectedBundle {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: bundle.path)]
                    )
                }
            }
            .disabled(model.selectedBundle == nil)

            Button("Move to Trash", action: onTrash)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.isTrashing || model.selectedBundle == nil)
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private static let icons = NSCache<NSString, NSImage>()

    private static func fileIcon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = icons.object(forKey: key) {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 20, height: 20)
        icons.setObject(image, forKey: key)
        return image
    }
}
