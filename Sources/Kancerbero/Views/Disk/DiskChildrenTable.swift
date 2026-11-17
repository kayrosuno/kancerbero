import AppKit
import SwiftUI
import KancerberoCore

struct DiskChildrenTable: View {
    let node: KBDiskNode
    let showHidden: Bool
    let showPackageContents: Bool
    var filter: DiskAnalyzerFocus? = nil
    /// Shared Analyzer selection (exact node path).
    @Binding var selection: String?
    let onSelect: (KBDiskNode) -> Void
    /// Direct files retained for this directory by the scan, largest first.
    var files: [KBDiskFile] = []

    @Environment(\.byteUnitSystem) private var byteUnitSystem

    private var directoryRows: [KBDiskNode] {
        guard filter != .files else { return [] }
        return node.children
            .filter { showHidden || !$0.isHidden }
            .filter { showPackageContents || !$0.isPackage || $0.allocatedBytes > 0 }
    }

    private var fileRows: [KBDiskNode] {
        guard filter != .folders else { return [] }
        return files
            .filter { showHidden || !$0.isHidden }
            .map(KBDiskNode.init(displayFile:))
    }

    private var rows: [KBDiskNode] {
        (directoryRows + fileRows).sorted {
            if $0.allocatedBytes != $1.allocatedBytes {
                return $0.allocatedBytes > $1.allocatedBytes
            }
            // Deterministic tie-break: Swift's sort is not stable.
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var headerText: String {
        let total = node.directFileCount
        guard files.count < total else { return "\(rows.count) items" }
        let retained = "top \(files.count) of \(KBFormat.compactCount(total)) files"
        return filter == .files ? retained : "\(rows.count) items · \(retained)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Contents")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(headerText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider().opacity(0.5)

            if rows.isEmpty {
                if filter == .files, node.directFileCount > 0 {
                    ContentUnavailableView(
                        "No file list",
                        systemImage: "doc",
                        description: Text("The scan did not retain the files of this folder.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "Nothing to show",
                        systemImage: "folder",
                        description: Text("This folder is empty or its contents are hidden.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Table(rows, selection: tableSelection(rows: rows)) {
                    TableColumn("Name") { child in
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: child))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(child.isDirectory ? AppSection.disk.tint : .secondary)
                                .frame(width: 14)
                            Text(child.name)
                                .lineLimit(1)
                                .onTapGesture(count: 2) {
                                    guard child.isDirectory else { return }
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
                        Text(KBFormat.bytes(child.allocatedBytes, units: byteUnitSystem))
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
                        if child.isDirectory {
                            Text("\(child.folderCount)/\(child.fileCount)")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .help("\(child.folderCount) folders, \(child.fileCount) files")
                        } else {
                            Text("—")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
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

    /// The row that represents the selected path: the node itself when it is a
    /// direct child, or its first-level ancestor under the current focus. The
    /// map still highlights the exact nested sector.
    private func ancestorRow(for path: String, rows: [KBDiskNode]) -> KBDiskNode? {
        guard path != node.path else { return nil }
        return rows.first { row in
            path == row.path || path.hasPrefix(row.path + "/")
        }
    }

    private func tableSelection(rows: [KBDiskNode]) -> Binding<String?> {
        Binding(
            get: {
                guard let selection,
                      let row = ancestorRow(for: selection, rows: rows) else { return nil }
                return row.path
            },
            set: { newValue in
                let mapped = selection.flatMap {
                    ancestorRow(for: $0, rows: rows)?.path
                }
                // Table echoes the value it is showing; ignore it so a nested
                // selection is not collapsed to its ancestor row.
                if newValue == mapped { return }
                if let newValue {
                    selection = newValue
                } else if let current = selection,
                          rows.contains(where: { $0.path == current }) {
                    selection = nil
                }
            }
        )
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
