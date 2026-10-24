import AppKit
import SwiftUI
import KancerberoCore

struct DiskLargestFilesTable: View {
    let files: [KBDiskFile]

    @State private var selection: String?

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
                Table(files, selection: $selection) {
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
                        Text(KBFormat.bytes(file.allocatedBytes))
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

    private func reveal(_ file: KBDiskFile) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
