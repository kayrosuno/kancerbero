import SwiftUI
import KancerberoCore

struct DiskView: View {
    @Binding var tab: DiskTab
    @Environment(DiskModel.self) private var disk
    @AppStorage(KBPreferences.tabAnimationsKey)
    private var tabAnimations = KBPreferences.tabAnimationsDefault
    @AppStorage(KBPreferences.diskUnitSystemKey)
    private var storedUnitSystem = KBPreferences.diskUnitSystemDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var unitSystem: KBByteUnitSystem {
        KBByteUnitSystem.fromCommandLine()
            ?? KBByteUnitSystem(rawValue: storedUnitSystem)
            ?? .decimal
    }

    private var unitSystemBinding: Binding<KBByteUnitSystem> {
        Binding(
            get: { unitSystem },
            set: { storedUnitSystem = $0.rawValue }
        )
    }

    private var pillAnimation: Animation? {
        KBPreferences.tabAnimation(stored: tabAnimations,
                                   reduceMotion: reduceMotion,
                                   duration: 0.28)
    }

    private var tabTransition: AnyTransition {
        KBPreferences.enabled(stored: tabAnimations, reduceMotion: reduceMotion)
            ? .opacity
            : .identity
    }

    var body: some View {
        VStack(spacing: 14) {
            CollapsibleSectionHeader(
                section: .disk,
                title: "Disk",
                subtitle: "Volumes, filesystems, analysis and disk I/O"
            )

            HStack(spacing: 12) {
                PillTabBar(selection: $tab, selectionAnimation: pillAnimation)

                GraphModeSelector(
                    mode: unitSystemBinding,
                    accessibilityLabel: "Disk size units",
                    help: "Show disk and file sizes in decimal (KB) or binary (KiB) units",
                    legacyWidth: 150)

                Spacer()
                if let label = contextLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            if let progress = disk.operationProgress {
                HStack { ProgressView().controlSize(.small); Text(progress).font(.caption) }
            }
            if let error = disk.operationError {
                HStack(alignment: .top) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { disk.operationError = nil }
                }
            }

            Group {
                switch tab {
                case .volumes:
                    DiskVolumesView { path in
                        withAnimation(pillAnimation) {
                            tab = .analyzer
                        }
#if APP_STORE
                        // A raw mount point has no sandbox scope. The Analyzer
                        // asks for a folder with NSOpenPanel instead.
                        _ = path
#else
                        Task { await disk.startScan(path: path) }
#endif
                    }
                case .filesystems:
                    FilesystemView()
                case .analyzer:
                    DiskAnalyzerView()
                case .io:
                    DiskIOView()
                }
            }
            .id(tab)
            .environment(\.byteUnitSystem, unitSystem)
            .transition(tabTransition)
        }
        .padding(.horizontal, KBTheme.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await disk.refreshInventory()
            await disk.refreshFilesystems()
            if disk.consumeAutoScan() {
                await disk.startScan()
            }
        }
    }

    private var contextLabel: String? {
        switch tab {
        case .volumes:
            let count = disk.inventory?.mountedVolumes.count ?? 0
            return "\(count) mounted volumes"
        case .filesystems:
            let systemCount = disk.filesystemSnapshot?.filesystems.count ?? 0
            return "\(systemCount) filesystems"
        case .analyzer:
            if disk.isScanning {
                if let live = disk.liveSnapshot {
                    return "\(KBFormat.bytes(live.root.allocatedBytes, units: unitSystem)) · \(KBFormat.compactCount(live.root.fileCount)) files"
                }
                return "Scanning…"
            }
            if let node = disk.currentNode {
                return "\(KBFormat.bytes(node.allocatedBytes, units: unitSystem)) · \(KBFormat.compactCount(node.fileCount)) files"
            }
            return "Not scanned"
        case .io:
            return nil
        }
    }
}
