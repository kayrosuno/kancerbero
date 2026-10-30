import AppKit
import SwiftUI
import KancerberoCore

struct LeftoversPanel: View {
    @Environment(ApplicationsModel.self) private var model
    let onTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider().opacity(0.4)

            if model.isScanningLeftovers, model.leftovers.isEmpty {
                ProgressView("Looking for related files…")
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.leftovers.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    Text("No related files found")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.kind) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.kind.title.uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(0.4)
                                    .foregroundStyle(.tertiary)
                                ForEach(group.items) { item in
                                    row(item)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider().opacity(0.4)
            footer
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private var groups: [(kind: KBLeftoverKind, items: [KBLeftover])] {
        Dictionary(grouping: model.leftovers, by: \.kind)
            .map { (kind: $0.key, items: $0.value) }
            .sorted { $0.kind.sortOrder < $1.kind.sortOrder }
    }

    private var header: some View {
        let bundle = model.selectedBundle
        return HStack(alignment: .center, spacing: 8) {
            if let bundle {
                Image(nsImage: ApplicationsTable.icon(for: bundle.path))
                    .resizable()
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(bundle?.name ?? "Selection")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(bundle?.bundleIdentifier ?? "—")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let bundle, bundle.isProtected {
                Label("Protected", systemImage: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else {
                Text(bundle?.version.map { "v\($0)" } ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ item: KBLeftover) -> some View {
        let checked = model.checkedLeftovers.contains(item.path)
        return HStack(spacing: 6) {
            Button {
                model.toggleLeftover(item.path)
            } label: {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(checked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.kind.title)

            Text(abbreviated(item.path))
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.path)

            Spacer(minLength: 4)

            if item.requiresPrivilege {
                Text("admin")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.orange)
                    .help("Needs the root daemon")
            }
            Text(item.sizeBytes.map { KBFormat.bytes($0) } ?? "—")
                .font(.system(size: 9, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(model.selectedLeftovers.count) files · "
                 + KBFormat.bytes(model.selectedBytes))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

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
}
