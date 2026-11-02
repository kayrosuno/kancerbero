import SwiftUI

@main
struct KancerberoApp: App {
    @State private var model = AppModel()
    @State private var disk = DiskModel()
    @State private var applications = ApplicationsModel()
    @State private var ui = UIState()
    @State private var filter = FilterModel()
    @State private var dockIcon = DockIconController()
    @AppStorage(KBPreferences.dockIconStyleKey)
    private var dockIconStyle = KBPreferences.dockIconStyleDefault

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(disk)
                .environment(applications)
                .environment(ui)
                .environment(filter)
                .frame(minWidth: 1040, minHeight: 640)
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
        .commands {
            SidebarCommands()

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

        Settings {
            SettingsView()
        }
    }
}
