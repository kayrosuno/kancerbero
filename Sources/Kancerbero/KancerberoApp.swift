import SwiftUI

@main
struct KancerberoApp: App {
    @State private var model = AppModel()
    @State private var disk = DiskModel()
    @State private var ui = UIState()
    @State private var filter = FilterModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(disk)
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
                    await ScreenshotMode.runIfRequested()
                }
        }
        .defaultSize(width: 1320, height: 820)
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

            CommandGroup(after: .newItem) {
                Button("Refresh Now") {
                    model.refreshNow()
                    Task { await disk.refreshInventory(force: true) }
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
        .defaultSize(width: 480, height: 720)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}
