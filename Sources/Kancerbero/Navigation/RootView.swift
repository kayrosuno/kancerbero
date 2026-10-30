import SwiftUI
import KancerberoFilterContract

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(FilterModel.self) private var filter
    @Environment(\.openWindow) private var openWindow
    @AppStorage("selectedSection") private var sectionRaw = AppSection.networking.rawValue
    @AppStorage("networkingTab") private var tabRaw = NetworkingTab.interfaces.rawValue
    @AppStorage("diskTab") private var diskTabRaw = DiskTab.volumes.rawValue
    @AppStorage(KBPreferences.tabAnimationsKey)
    private var tabAnimations = KBPreferences.tabAnimationsDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility
    /// Request currently on screen. A real state binding (unlike a read-only
    /// Binding over `filter.pending`) so `dismiss()` always closes the sheet.
    @State private var approvalRequest: FilterRequest?

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
                    case .memory:
                        MemoryView()
                    case .energy:
                        EnergyView()
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
                if currentSection == .networking || currentSection == .cpu
            || currentSection == .memory || currentSection == .energy {
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
        .task {
            syncApproval(filter.pending)
            await autoOpenStatusWindowIfRequested()
        }
        .sheet(item: $approvalRequest) { request in
            FilterApprovalSheet(request: request)
                .environment(filter)
        }
        .onChange(of: filter.pending) { _, pending in
            syncApproval(pending)
        }
        .onReceive(NotificationCenter.default.publisher(for: .kbSelectSection)) { notification in
            guard let raw = notification.object as? String,
                  let section = AppSection(rawValue: raw) else { return }
            withAnimation(sectionAnimation) {
                sectionRaw = section.rawValue
            }
        }
    }

    /// Keeps the presented request in step with the extension's pending list:
    /// close it as soon as it is resolved, and show the next one if any.
    private func syncApproval(_ pending: [FilterRequest]) {
        if let presented = approvalRequest,
           pending.contains(where: { $0.id == presented.id }) {
            return
        }
        // Nothing on screen, or the presented request was just resolved:
        // show the next one (or close the sheet when there is none).
        approvalRequest = pending.first
    }

    /// Screenshot hook: `--show-status` opens the System status window after
    /// the first snapshot arrives.
    private func autoOpenStatusWindowIfRequested() async {
        guard CommandLine.arguments.contains("--show-status") else { return }
        try? await Task.sleep(for: .milliseconds(800))
        openWindow(id: SystemStatusWindow.id)
    }
}
