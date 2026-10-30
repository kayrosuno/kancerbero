import SwiftUI
import KancerberoCore

struct DiskView: View {
    @Binding var tab: DiskTab
    @Environment(DiskModel.self) private var disk
    @Environment(AppModel.self) private var model
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
            SectionHeader(title: "Disk",
                          subtitle: "Volumes, analysis and disk I/O")

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
                case .io:
                    DiskIOView()
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
        case .io:
            return "Read \(KBFormat.byteRate(model.diskReadRate)) · Write \(KBFormat.byteRate(model.diskWriteRate))"
        }
    }
}
