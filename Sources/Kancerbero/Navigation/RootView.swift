import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("selectedSection") private var sectionRaw = AppSection.networking.rawValue
    @AppStorage("networkingTab") private var tabRaw = NetworkingTab.interfaces.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility

    init() {
        // Command-line overrides are used only by the screenshot mode. They are
        // written before @AppStorage reads its value so the capture shows the
        // requested section.
        if let section = AppSection.fromCommandLine() {
            UserDefaults.standard.set(section.rawValue, forKey: "selectedSection")
        }
        if let tab = NetworkingTab.fromCommandLine() {
            UserDefaults.standard.set(tab.rawValue, forKey: "networkingTab")
        }
        let collapsed = CommandLine.arguments.contains("--sidebar-collapsed")
        _columnVisibility = State(initialValue: collapsed ? .detailOnly : .all)
    }

    private var currentSection: AppSection {
        AppSection(rawValue: sectionRaw) ?? .networking
    }

    private var selection: Binding<AppSection?> {
        Binding(
            get: { currentSection },
            set: { value in
                guard let value else { return }
                withAnimation(.snappy(duration: 0.3)) {
                    sectionRaw = value.rawValue
                }
            }
        )
    }

    private var networkingTab: Binding<NetworkingTab> {
        Binding(
            get: { NetworkingTab(rawValue: tabRaw) ?? .interfaces },
            set: { tabRaw = $0.rawValue }
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
                        DiskView()
                    case .daemons:
                        DaemonsView()
                    }
                }
                .id(currentSection)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().opacity(0.5)
                StatusBar()
            }
            .background(KBTheme.background)
            .animation(.snappy(duration: 0.3), value: sectionRaw)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle sidebar")
                .accessibilityLabel("Toggle sidebar")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if currentSection == .networking {
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
            withAnimation(.snappy(duration: 0.3)) {
                sectionRaw = section.rawValue
            }
        }
    }
}
