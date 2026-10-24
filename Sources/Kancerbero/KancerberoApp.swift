import SwiftUI

@main
struct KancerberoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 640)
                .task {
                    model.start()
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

            CommandGroup(after: .newItem) {
                Button("Refresh Now") { model.refreshNow() }
                    .keyboardShortcut("r")
                Button(model.isPaused ? "Resume" : "Pause") {
                    model.isPaused.toggle()
                }
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }
}
