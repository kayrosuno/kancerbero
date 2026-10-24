import SwiftUI

@main
struct KancerberoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 560)
                .task {
                    model.start()
                    await ScreenshotMode.runIfRequested()
                }
        }
        .defaultSize(width: 1200, height: 720)
        .windowStyle(.titleBar)
        .commands {
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
