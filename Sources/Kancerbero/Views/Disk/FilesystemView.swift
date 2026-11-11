import SwiftUI
import KancerberoCore

struct FilesystemView: View {
    @Environment(DiskModel.self) private var disk
    @Environment(\.byteUnitSystem) private var unitSystem
    @State private var search = ""
    @State private var selectedFilesystemIDs: Set<KBFilesystem.ID> = []
    @State private var sortOrder = [KeyPathComparator(\KBFilesystem.mountPoint)]

    private var filesystems: [KBFilesystem] {
        disk.filesystemSnapshot?.filesystems ?? []
    }

    private var rows: [KBFilesystem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return filesystems.filter {
            query.isEmpty || $0.filesystem.localizedCaseInsensitiveContains(query)
                || $0.mountPoint.localizedCaseInsensitiveContains(query)
                || $0.type.localizedCaseInsensitiveContains(query)
        }.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let error = disk.filesystemError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            table
                .overlay {
                    if disk.isLoadingFilesystems && disk.filesystemSnapshot == nil {
                        ProgressView("Loading filesystems…")
                    } else if rows.isEmpty {
                        ContentUnavailableView(
                            search.isEmpty ? "No mounted filesystems" : "No matching filesystems",
                            systemImage: "internaldrive",
                            description: Text(search.isEmpty
                                ? "Refresh to read the system mount table."
                                : "Try a different device, type or mount point."))
                    }
                }

            Text("APFS volumes share available space; row sizes are not additive. Network and automount statistics use the kernel cache to avoid blocking on unavailable servers.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
        .onChange(of: disk.filesystemSnapshot?.generatedAt) { _, _ in
            selectedFilesystemIDs.formIntersection(Set(filesystems.map(\.id)))
        }
        .task {
            await disk.refreshInventory()

            while !Task.isCancelled {
                await disk.refreshFilesystems()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Filesystems", systemImage: "internaldrive")
                .font(.system(size: 12, weight: .semibold))

            TextField("Filter filesystems", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)

            Spacer(minLength: 8)

            Text("\(rows.count) of \(filesystems.count)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if disk.isLoadingFilesystems {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await disk.refreshFilesystems() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(disk.isLoadingFilesystems)
            .help("Refresh mounted filesystem statistics (also updated every 5 seconds)")
        }
    }

    private var table: some View {
        Table(rows, selection: $selectedFilesystemIDs, sortOrder: $sortOrder) {
            TableColumn("Filesystem", value: \.filesystem) { row in
                HStack(spacing: 5) {
                    Text(row.filesystem)
                        .lineLimit(1)
                    if row.warning != nil {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else if row.isCached {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                    }
                }
                .help(rowHelp(row))
            }
            .width(min: 120, ideal: 160)

            TableColumn("Type", value: \.type) { row in
                Text(row.type.uppercased()).lineLimit(1)
            }
            .width(min: 50, ideal: 55)

            TableColumn("Mounted on", value: \.mountPoint) { row in
                Text(row.mountPoint)
                    .lineLimit(1)
                    .help(rowHelp(row))
            }
            .width(min: 160, ideal: 200)

            TableColumn("Size", value: \.sizeBytes) { row in
                bytes(row.sizeBytes)
            }
            .width(min: 70, ideal: 75)

            TableColumn("Used", value: \.usedBytes) { row in
                bytes(row.usedBytes)
            }
            .width(min: 70, ideal: 75)

            TableColumn("Available", value: \.availableBytes) { row in
                bytes(row.availableBytes)
            }
            .width(min: 70, ideal: 75)

            TableColumn("Capacity", value: \.capacityPercent) { row in
                HStack(spacing: 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(capacityColor(row.capacityPercent))
                                .frame(width: geometry.size.width
                                       * min(max(row.capacityPercent / 100, 0), 1))
                        }
                    }
                    .frame(width: 36, height: 5)
                    Text("\(Int(row.capacityPercent))%")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .help("Used / (Used + Available), rounded up as in df")
            }
            .width(min: 85, ideal: 90)

            TableColumn("iused", value: \.usedInodes) { row in
                inodeCount(row.usedInodes)
            }
            .width(min: 45, ideal: 50)

            TableColumn("ifree", value: \.freeInodes) { row in
                inodeCount(row.freeInodes)
            }
            .width(min: 50, ideal: 60)

            TableColumn("%iused", value: \.inodePercent) { row in
                Text(row.inodePercent < 0 ? "—" : "\(Int(row.inodePercent))%")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 45, ideal: 50)

        }
        .contextMenu(forSelectionType: KBFilesystem.ID.self) { ids in
            let row = ids.count == 1 ? filesystems.first { ids.contains($0.id) } : nil
            DiskOperationMenu(target: row.map { .filesystem($0) }, name: row?.mountPoint ?? "Filesystems")
        }
    }

    private func bytes(_ value: UInt64) -> some View {
        Text(KBFormat.bytes(value, units: unitSystem))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .help("\(value.formatted()) bytes")
    }

    private func inodeCount(_ value: UInt64) -> some View {
        Text(value >= 1_000_000_000_000
             ? value.formatted(.number.notation(.scientific).precision(.significantDigits(2)))
             : KBFormat.compactCount(Int(clamping: value)))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .help("\(value.formatted()) inodes")
    }

    private func rowHelp(_ row: KBFilesystem) -> String {
        var details = [row.filesystem, row.mountPoint,
                       row.isReadOnly ? "Read-only" : "Read/write"]
        if row.isCached {
            details.append("Kernel-cached statistics; no synchronous network/automount query")
        }
        if let warning = row.warning { details.append(warning) }
        return details.joined(separator: "\n")
    }

    private func capacityColor(_ percent: Double) -> Color {
        if percent >= 95 { return .red }
        if percent >= 80 { return .orange }
        return .accentColor
    }
}
