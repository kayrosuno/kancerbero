import AppKit
import Foundation

/// Headless-friendly visual check:
///
///     Kancerbero --screenshot /tmp/kancerbero-ui.png
///
/// The app renders its own window, writes a PNG and exits. No Screen
/// Recording permission is involved.
enum ScreenshotMode {
    @MainActor
    static func runIfRequested() async {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--screenshot") else {
            return
        }
        guard flagIndex + 1 < arguments.count else {
            fail("usage: --screenshot <path>")
        }
        let url = URL(fileURLWithPath: arguments[flagIndex + 1])

        NSApp.activate(ignoringOtherApps: true)

        var window: NSWindow?
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            window = NSApp.windows.first {
                $0.isVisible && ($0.contentView?.bounds.width ?? 0) > 100
            }
            if window != nil { break }
        }
        guard let window else {
            fail("no visible window after 5s")
        }
        window.makeKeyAndOrderFront(nil)
        window.setContentSize(NSSize(width: 1200, height: 720))
        window.center()

        // Let the first daemon/local snapshot arrive and the table lay out.
        try? await Task.sleep(for: .seconds(3))

        do {
            try WindowSnapshot.capture(window, to: url)
            print("screenshot: \(url.path)")
            fflush(stdout)
        } catch {
            fail("capture failed: \(error)")
        }

        NSApp.terminate(nil)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(2)
    }
}
