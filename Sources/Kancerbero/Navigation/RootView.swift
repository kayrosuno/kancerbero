import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("selectedSection") private var sectionRaw = AppSection.networking.rawValue
    @AppStorage("networkingTab") private var tabRaw = NetworkingTab.interfaces.rawValue
    @AppStorage("diskTab") private var diskTabRaw = DiskTab.volumes.rawValue
    @AppStorage(KBPreferences.tabAnimationsKey)
    private var tabAnimations = KBPreferences.tabAnimationsDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility

    init() {
        let collapsed = CommandLine.arguments.contains("--sidebar-collapsed")
        _columnVisibility = State(initialValue: collapsed ? .detailOnly : .all)
    }

    /// Command-line values are screenshot-only overrides; they win over the
    /// persisted selection without writing to UserDefaults.
    private var currentSection: AppSection {
        AppSection.fromCommandLine()
            ?? AppSection(rawValue: sectionRaw)
            ?? .networking
    }

    /// The section binding setter and the menu notification are the only
    /// transaction owners for section changes; the sidebar highlight and the
    /// detail transition animate from this same transaction.
    private var sectionAnimation: Animation? {
        KBPreferences.tabAnimation(stored: tabAnimations,
                                   reduceMotion: reduceMotion,
                                   duration: 0.3)
    }

    private var sectionTransition: AnyTransition {
        KBPreferences.enabled(stored: tabAnimations, reduceMotion: reduceMotion)
            ? .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                          removal: .opacity)
            : .identity
    }

    private var selection: Binding<AppSection?> {
        Binding(
            get: { currentSection },
            set: { value in
                guard let value else { return }
                withAnimation(sectionAnimation) {
                    sectionRaw = value.rawValue
                }
            }
        )
    }

    private var networkingTab: Binding<NetworkingTab> {
        Binding(
            get: {
                NetworkingTab.fromCommandLine()
                    ?? NetworkingTab(rawValue: tabRaw)
                    ?? .interfaces
            },
            set: { tabRaw = $0.rawValue }
        )
    }

    private var diskTab: Binding<DiskTab> {
        Binding(
            get: {
                DiskTab.fromCommandLine()
                    ?? DiskTab(rawValue: diskTabRaw)
                    ?? .volumes
            },
            set: { diskTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: selection)
                .navigationSplitViewColumnWidth(min: 220,
                                                ideal: KBTheme.sidebarWidth,
                                                max: 320)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch currentSection {
                    case .networking:
                        NetworkingView(tab: networkingTab)
                    case .disk:
                        DiskView(tab: diskTab)
                    case .daemons:
                        DaemonsView()
                    case .cpu:
                        CPUView()
                    }
                }
                .id(currentSection)
                .transition(sectionTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().opacity(0.5)
                StatusBar(section: currentSection)
            }
            .background(KBTheme.background)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if currentSection == .networking || currentSection == .cpu {
                    Button {
                        model.refreshNow()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh now")

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            model.isPaused.toggle()
                        }
                    } label: {
                        Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    }
                    .help(model.isPaused ? "Resume" : "Pause")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kbSelectSection)) { notification in
            guard let raw = notification.object as? String,
                  let section = AppSection(rawValue: raw) else { return }
            withAnimation(sectionAnimation) {
                sectionRaw = section.rawValue
            }
        }
    }
}
