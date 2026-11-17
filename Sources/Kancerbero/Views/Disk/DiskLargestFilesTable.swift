import AppKit
import SwiftUI
import KancerberoCore

struct DiskLargestFilesTable: View {
    let files: [KBDiskFile]
    /// Shared Analyzer selection (exact node path).
    @Binding var selection: String?

    @Environment(\.byteUnitSystem) private var byteUnitSystem

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Largest files")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(files.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider().opacity(0.5)

            if files.isEmpty {
                ContentUnavailableView(
                    "No files",
                    systemImage: "doc",
                    description: Text("The scan did not find any files.")
                )
                .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                Table(files, selection: tableSelection) {
                    TableColumn("Name") { file in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(file.name)
                                .lineLimit(1)
                                .help(file.path)
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { reveal(file) }
                            Button("Copy Path") { copy(file.path) }
                        }
                    }
                    .width(min: 140, ideal: 190)

                    TableColumn("Size") { file in
                        Text(KBFormat.bytes(file.allocatedBytes, units: byteUnitSystem))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                    }
                    .width(min: 72, ideal: 92)
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

    /// Only shows and clears paths this table actually contains, so a nested
    /// selection made in the map is not cleared when its row is not here.
    private var tableSelection: Binding<String?> {
        Binding(
            get: {
                guard let selection,
                      files.contains(where: { $0.path == selection }) else { return nil }
                return selection
            },
            set: { newValue in
                if newValue == selection { return }
                if let newValue {
                    selection = newValue
                } else if let current = selection,
                          files.contains(where: { $0.path == current }) {
                    selection = nil
                }
            }
        )
    }

    private func reveal(_ file: KBDiskFile) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
