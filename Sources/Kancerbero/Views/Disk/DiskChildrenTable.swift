import AppKit
import SwiftUI
import KancerberoCore

struct DiskChildrenTable: View {
    let node: KBDiskNode
    let showHidden: Bool
    let showPackageContents: Bool
    let onSelect: (KBDiskNode) -> Void

    @State private var selection: String?

    private var rows: [KBDiskNode] {
        node.children
            .filter { showHidden || !$0.isHidden }
            .filter { showPackageContents || !$0.isPackage || $0.allocatedBytes > 0 }
            .sorted { $0.allocatedBytes > $1.allocatedBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Contents")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(rows.count) items")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider().opacity(0.5)

            if rows.isEmpty {
                ContentUnavailableView(
                    "Nothing to show",
                    systemImage: "folder",
                    description: Text("This folder is empty or its contents are hidden.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("Name") { child in
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: child))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(child.isDirectory ? AppSection.disk.tint : .secondary)
                                .frame(width: 14)
                            Text(child.name)
                                .lineLimit(1)
                                .onTapGesture(count: 2) {
                                    onSelect(child)
                                }
                            if child.isAggregate {
                                Text("grouped")
                                    .font(.system(size: 8, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(.quaternary.opacity(0.4)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { reveal(child) }
                            Button("Copy Path") { copy(child.path) }
                            if child.isDirectory && !child.isAggregate {
                                Divider()
                                Button("Open in Analyzer") { onSelect(child) }
                            }
                        }
                    }
                    .width(min: 110, ideal: 160)

                    TableColumn("Size") { child in
                        Text(KBFormat.bytes(child.allocatedBytes))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 76)

                    TableColumn("%") { child in
                        Text(parentPercent(child))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 44, ideal: 54)

                    TableColumn("Items") { child in
                        Text("\(child.folderCount)/\(child.fileCount)")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .help("\(child.folderCount) folders, \(child.fileCount) files")
                    }
                    .width(min: 38, ideal: 46)

                    TableColumn("Flags") { child in
                        Text(flags(for: child))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .width(min: 44, ideal: 70)
                }
                .tableStyle(.inset)
            }
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

    private func parentPercent(_ child: KBDiskNode) -> String {
        guard node.allocatedBytes > 0 else { return "—" }
        return KBFormat.percent(Double(child.allocatedBytes) / Double(node.allocatedBytes))
    }

    private func icon(for child: KBDiskNode) -> String {
        if child.isPackage { return "shippingbox" }
        if child.isDirectory { return "folder" }
        return "doc"
    }

    private func flags(for child: KBDiskNode) -> String {
        var values: [String] = []
        if child.isHidden { values.append("hidden") }
        if child.isPackage { values.append("package") }
        if child.isMountPoint { values.append("mount") }
        if child.accessDenied { values.append("denied") }
        if child.truncated { values.append("truncated") }
        if child.isAggregate { values.append("grouped") }
        return values.isEmpty ? "—" : values.joined(separator: ", ")
    }

    private func reveal(_ child: KBDiskNode) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: child.path)])
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
