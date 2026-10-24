import AppKit
import SwiftUI
import KancerberoCore

struct DiskAnalyzerView: View {
    @Environment(DiskModel.self) private var disk
    @State private var pathDraft = ""

    private var hiddenBinding: Binding<Bool> {
        Binding(get: { disk.showHidden }, set: { disk.showHidden = $0 })
    }

    private var packagesBinding: Binding<Bool> {
        Binding(get: { disk.showPackageContents }, set: { disk.showPackageContents = $0 })
    }

    private var crossMountsBinding: Binding<Bool> {
        Binding(
            get: { disk.scanOptions.crossMountPoints },
            set: { disk.scanOptions.crossMountPoints = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            controls

            if case .failed(let message) = disk.scanState {
                banner(message, icon: "exclamationmark.triangle.fill", tint: .orange)
            }

            if disk.isScanning {
                progressCard
            }

            if let snapshot = disk.scanSnapshot {
                cards(snapshot)
                if snapshot.cancelled {
                    banner("Scan cancelled. Showing partial results.",
                           icon: "stop.circle", tint: Color.secondary)
                }
                if !disk.deniedPaths.isEmpty {
                    deniedBanner
                }
                HStack(spacing: 12) {
                    mapCard(snapshot)
                    rightPanel(snapshot)
                        .frame(width: 460)
                }
            } else if !disk.isScanning {
                emptyState
            }
        }
        .onAppear { pathDraft = disk.scanRootPath }
        .onChange(of: disk.scanRootPath) { _, newValue in
            pathDraft = newValue
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            TextField("Folder or volume path", text: $pathDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 240)
                .onSubmit { scan() }

            Button("Choose…") { chooseFolder() }
                .buttonStyle(.bordered)

            if disk.isScanning {
                Button("Cancel") { disk.cancelScan() }
                    .buttonStyle(.bordered)
            } else {
                Button("Scan") { scan() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppSection.disk.tint)
            }

            Spacer(minLength: 6)

            Toggle("Hidden", isOn: hiddenBinding)
                .toggleStyle(.checkbox)
                .help("Show hidden files in the map and tables")
            Toggle("Packages", isOn: packagesBinding)
                .toggleStyle(.checkbox)
                .help("Allow drilling into application bundles and other packages")
            Toggle("Cross mounts", isOn: crossMountsBinding)
                .toggleStyle(.checkbox)
                .help("Follow mount points into other file systems")
        }
    }

    private var progressCard: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(disk.scanProgress?.path ?? disk.scanRootPath)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let progress = disk.scanProgress {
                    Text("\(KBFormat.compactCount(progress.files)) files · \(KBFormat.compactCount(progress.folders)) folders · \(KBFormat.bytes(progress.bytes)) · \(String(format: "%.1f", progress.elapsed))s")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("Starting…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Cancel") { disk.cancelScan() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private func cards(_ snapshot: KBDiskScanSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 12)],
                  spacing: 12) {
            SummaryCard(
                title: "Scanned",
                value: KBFormat.bytes(snapshot.root.allocatedBytes),
                caption: String(format: "%.2f s", snapshot.duration),
                systemImage: "chart.pie.fill",
                tint: Color(red: 0.94, green: 0.56, blue: 0.18)
            )
            SummaryCard(
                title: "Files",
                value: KBFormat.compactCount(snapshot.root.fileCount),
                caption: "counted in the tree",
                systemImage: "doc.on.doc",
                tint: Color(red: 0.16, green: 0.62, blue: 0.94)
            )
            SummaryCard(
                title: "Folders",
                value: KBFormat.compactCount(snapshot.root.folderCount),
                caption: "directories visited",
                systemImage: "folder.fill",
                tint: Color(red: 0.20, green: 0.70, blue: 0.62)
            )
            SummaryCard(
                title: "Denied",
                value: KBFormat.compactCount(snapshot.deniedPaths.count),
                caption: "paths without permission",
                systemImage: "lock.fill",
                tint: Color(red: 0.62, green: 0.42, blue: 0.95)
            )
        }
    }

    private func mapCard(_ snapshot: KBDiskScanSnapshot) -> some View {
        VStack(spacing: 0) {
            breadcrumb(snapshot)
            Divider().opacity(0.5)
            if let node = disk.currentNode {
                RadialDiskMap(
                    root: snapshot.root,
                    focus: node,
                    volumeCapacity: volumeCapacity(for: snapshot),
                    showHidden: disk.showHidden,
                    showPackageContents: disk.showPackageContents,
                    onSelect: { disk.drillDown(to: $0) }
                )
                .id(node.id)
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private func breadcrumb(_ snapshot: KBDiskScanSnapshot) -> some View {
        HStack(spacing: 6) {
            Button {
                disk.drillUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(disk.currentNode?.id == snapshot.root.id)
            .help("Go up one level")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(disk.lineToCurrentNode.enumerated()),
                            id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            disk.currentNodeID = node.path
                        } label: {
                            Text(node.name)
                                .font(.system(size: 11,
                                              weight: index == disk.lineToCurrentNode.count - 1
                                                ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 6)

            if let node = disk.currentNode {
                Text("\(KBFormat.compactCount(node.fileCount)) files · \(KBFormat.bytes(node.allocatedBytes))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func rightPanel(_ snapshot: KBDiskScanSnapshot) -> some View {
        VStack(spacing: 12) {
            if let node = disk.currentNode {
                DiskChildrenTable(
                    node: node,
                    showHidden: disk.showHidden,
                    showPackageContents: disk.showPackageContents,
                    onSelect: { disk.drillDown(to: $0) }
                )
                .frame(maxHeight: .infinity)
            }

            DiskLargestFilesTable(files: snapshot.largestFiles)
                .frame(height: 190)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Analyze disk space", systemImage: "chart.pie")
        } description: {
            Text("Choose a folder or volume and scan it to see its largest folders and files.")
        } actions: {
            Button("Scan Home Folder") {
                Task {
                    await disk.startScan(
                        path: FileManager.default.homeDirectoryForCurrentUser.path
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppSection.disk.tint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            Text("\(disk.deniedPaths.count) paths could not be read. Grant Full Disk Access to scan them.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 10))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private func banner(_ message: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private func volumeCapacity(for snapshot: KBDiskScanSnapshot) -> UInt64? {
        guard let volume = disk.volume(for: snapshot.root.path),
              let mount = volume.mountPoint,
              (snapshot.root.path as NSString).standardizingPath == mount else {
            return nil
        }
        return volume.sizeBytes
    }

    private func scan() {
        let path = pathDraft
        Task { await disk.startScan(path: path) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: pathDraft)
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            pathDraft = url.path
            Task { await disk.startScan(path: url.path) }
        }
    }
}
