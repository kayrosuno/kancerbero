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
    static func runIfRequested(model: AppModel? = nil) async {
        let arguments = CommandLine.arguments

        // `--screenshot-dock` renders the Dock tile offscreen; it needs no
        // NSWindow and no Screen Recording permission.
        if let dockIndex = arguments.firstIndex(of: "--screenshot-dock") {
            guard dockIndex + 1 < arguments.count else {
                fail("usage: --screenshot-dock <path>")
            }
            guard let model else {
                fail("dock screenshot requires the app model")
            }
            let url = URL(fileURLWithPath: arguments[dockIndex + 1])
            try? await Task.sleep(for: .seconds(screenshotDelay(arguments, default: 4)))

            let styles: [DockIconStyle]
            if value(for: "--dock-style", in: arguments)?.lowercased() == "all" {
                styles = DockIconStyle.allCases.filter { $0 != .applicationIcon }
            } else if let raw = value(for: "--dock-style", in: arguments),
                      let style = DockIconStyle(rawValue: raw) {
                styles = [style]
            } else {
                let raw = UserDefaults.standard.string(forKey: KBPreferences.dockIconStyleKey) ?? ""
                styles = [DockIconStyle(rawValue: raw) ?? .cpuHistory]
            }

            for style in styles {
                let view = DockIconView()
                view.apply(style: style, snapshot: DockIconSnapshot(model: model))
                let target = styles.count > 1 ? styledURL(url, style: style) : url
                do {
                    try view.renderPNG(to: target, size: 256)
                    print("dock screenshot: \(target.path)")
                } catch {
                    fail("dock capture failed: \(error)")
                }
            }
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }

        guard let flagIndex = arguments.firstIndex(of: "--screenshot") else {
            return
        }
        guard flagIndex + 1 < arguments.count else {
            fail("usage: --screenshot <path>")
        }
        let url = URL(fileURLWithPath: arguments[flagIndex + 1])

        NSApp.activate(ignoringOtherApps: true)

        // `--show-status` opens the System status window; capture that one
        // instead of the main window when both flags are present.
        let wantsStatus = arguments.contains("--show-status")
        var window: NSWindow?
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            window = NSApp.windows.first {
                $0.isVisible
                    && ($0.contentView?.bounds.width ?? 0) > 100
                    && (!wantsStatus || $0.title == "System status")
            }
            if window != nil { break }
        }
        guard let window else {
            let titles = NSApp.windows.map {
                "\($0.title.isEmpty ? "<untitled>" : $0.title)"
                    + ($0.isVisible ? "" : "(hidden)")
            }
            fail("no visible window after 5s: \(titles.joined(separator: ", "))")
        }
        window.makeKeyAndOrderFront(nil)
        if let size = Self.screenshotSize(arguments) {
            window.setContentSize(size)
            window.center()
        } else if wantsStatus {
            // Wide enough for the logo rail and the three status columns.
            window.setContentSize(NSSize(width: 1180, height: 820))
        } else {
            window.setContentSize(NSSize(width: 1440, height: 860))
            window.center()
        }

        // Let the first daemon/local snapshot arrive and the table lay out.
        let delay = screenshotDelay(arguments, default: 4)
        try? await Task.sleep(for: .seconds(delay))

        do {
            try WindowSnapshot.capture(window, to: url)
            print("screenshot: \(url.path)")
            fflush(stdout)
        } catch {
            fail("capture failed: \(error)")
        }

        NSApp.terminate(nil)
    }

    private static func screenshotDelay(_ arguments: [String],
                                        default value: TimeInterval) -> TimeInterval {
        guard let flag = arguments.firstIndex(of: "--screenshot-delay"),
              flag + 1 < arguments.count,
              let seconds = Double(arguments[flag + 1]) else {
            return value
        }
        return seconds
    }

    /// `--screenshot-size 1040x640` for deterministic captures at the minimum
    /// window size.
    private static func screenshotSize(_ arguments: [String]) -> NSSize? {
        guard let raw = value(for: "--screenshot-size", in: arguments) else {
            return nil
        }
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width >= 200, height >= 200 else {
            return nil
        }
        return NSSize(width: width, height: height)
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func styledURL(_ url: URL, style: DockIconStyle) -> URL {
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        return directory.appendingPathComponent("\(base)-\(style.rawValue).\(ext)")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(2)
    }
}
