import SwiftUI
import KancerberoCore

struct DiskView: View {
    @Binding var tab: DiskTab
    @Environment(DiskModel.self) private var disk
    @AppStorage(KBPreferences.tabAnimationsKey)
    private var tabAnimations = KBPreferences.tabAnimationsDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            header

            HStack(spacing: 12) {
                PillTabBar(selection: $tab, selectionAnimation: pillAnimation)
                Spacer()
                Text(contextLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Group {
                switch tab {
                case .volumes:
                    DiskVolumesView { path in
                        withAnimation(pillAnimation) {
                            tab = .analyzer
                        }
                        Task { await disk.startScan(path: path) }
                    }
                case .analyzer:
                    DiskAnalyzerView()
                }
            }
            .id(tab)
            .transition(tabTransition)
        }
        .padding(.horizontal, KBTheme.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await disk.refreshInventory()
            if disk.consumeAutoScan() {
                await disk.startScan()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Disk")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Volumes, filesystems and space analysis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if disk.isLoadingInventory {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await disk.refreshInventory(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh volumes")
        }
    }

    private var contextLabel: String {
        switch tab {
        case .volumes:
            let count = disk.inventory?.mountedVolumes.count ?? 0
            return "\(count) mounted volumes"
        case .analyzer:
            if disk.isScanning {
                if let live = disk.liveSnapshot {
                    return "\(KBFormat.bytes(live.root.allocatedBytes)) · \(KBFormat.compactCount(live.root.fileCount)) files"
                }
                return "Scanning…"
            }
            if let node = disk.currentNode {
                return "\(KBFormat.bytes(node.allocatedBytes)) · \(KBFormat.compactCount(node.fileCount)) files"
            }
            return "Not scanned"
        }
    }
}
