import SwiftUI
import KancerberoCore

@main
struct KancerberoApp: App {
    @State private var model = AppModel()
    @State private var disk = DiskModel()
    @State private var applications = ApplicationsModel()
    @State private var ui = UIState()
    @State private var filter = FilterModel()
    @State private var dockIcon = DockIconController()
    @State private var updater = UpdaterModel()
    @AppStorage(KBPreferences.dockIconStyleKey)
    private var dockIconStyle = KBPreferences.dockIconStyleDefault

    init() {
        KBAppearance.applyStored()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(disk)
                .environment(applications)
                .environment(ui)
                .environment(filter)
                .environment(updater)
                .task {
                    if CommandLine.arguments.contains("--register-service") {
                        await model.registerDaemonService()
                        print("service status: \(model.serviceStatus)")
                    } else if CommandLine.arguments.contains("--unregister-service") {
                        await model.unregisterDaemonService()
                        print("service status: \(model.serviceStatus)")
                    }
                    model.start()
                    filter.start()
                    dockIcon.start(model: model)
                    await ScreenshotMode.runIfRequested(model: model)
                }
        }
        .defaultSize(width: 1440, height: 860)
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.isEnabled || !updater.canCheckForUpdates)
            }

            CommandMenu("Sections") {
                ForEach(AppSection.allCases) { section in
                    Button(section.title) {
                        NotificationCenter.default.post(name: .kbSelectSection,
                                                        object: section.rawValue)
                    }
                    .keyboardShortcut(section.shortcut, modifiers: .command)
                }
            }

            CommandMenu("Daemon") {
                Button("Enable Background Daemon") {
                    Task { await model.registerDaemonService() }
                }
                .disabled(model.legacyServiceDetected
                          || model.serviceStatus == .enabled
                          || model.serviceActionInFlight)

                Button("Disable Background Daemon") {
                    Task { await model.unregisterDaemonService() }
                }
                .disabled(model.serviceStatus == .notRegistered
                          || model.serviceActionInFlight)

                Divider()

                Button("Open Login Items Settings…") {
                    model.openLoginItemsSettings()
                }
            }

            CommandMenu("Dock Icon") {
                Picker("Dock icon", selection: $dockIconStyle) {
                    ForEach(DockIconStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Button("Clear History") {
                    model.clearHistories()
                }
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Dashboard Cards") {
                    NotificationCenter.default.post(name: .kbToggleAllCards, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            CommandGroup(after: .newItem) {
                Button("Refresh Now") {
                    model.refreshNow()
                    Task { await disk.refreshInventory(force: true) }
                    Task { await applications.refresh(force: true) }
                }
                .keyboardShortcut("r")
                Button(model.isPaused ? "Resume" : "Pause") {
                    model.isPaused.toggle()
                }
                .keyboardShortcut(.space, modifiers: [])
            }
        }

        Window("System status", id: SystemStatusWindow.id) {
            SystemStatusView()
                .environment(model)
                .environment(filter)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)

        Window("Filter rules", id: FilterRulesWindow.id) {
            FilterRulesView()
                .environment(filter)
        }
        .defaultSize(width: 820, height: 580)
        .windowResizability(.contentMinSize)

        WindowGroup("Disk Info", id: DiskItemInfoWindow.id,
                    for: String.self) { $itemID in
            DiskItemInfoWindowView(itemID: itemID)
                .environment(disk)
        }
        .defaultSize(width: 560, height: 680)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        WindowGroup("Process Inspector", id: ProcessInspectorWindow.id,
                    for: KBProcessKey.self) { $key in
            ProcessInspectorWindowView(key: key)
                .environment(model)
        }
        .defaultSize(width: 1040, height: 660)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(model)
                .environment(filter)
                .environment(updater)
        }
    }
}
