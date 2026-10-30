import Foundation
import UniformTypeIdentifiers

public enum AppInventoryCollector {
    public struct Snapshot: Sendable {
        public var bundles: [KBAppBundle]
        public var generatedAt: Date

        public init(bundles: [KBAppBundle], generatedAt: Date = Date()) {
            self.bundles = bundles
            self.generatedAt = generatedAt
        }
    }

    private static let pluginExtensions: Set<String> = [
        "bundle", "plugin", "prefpane", "qlgenerator", "mdimporter",
        "saver", "appex", "wdgt"
    ]

    private static let pluginDirectories = [
        "Library/PreferencePanes",
        "Library/Services",
        "Library/Safari/Extensions",
        "Library/Internet Plug-Ins",
        "Library/QuickLook",
        "Library/Spotlight",
        "Library/Audio/Plug-Ins",
        "Library/ColorPickers",
        "Library/Screen Savers",
        "Library/ScriptingAdditions"
    ]

    private static let widgetDirectories = [
        "Library/Widgets"
    ]

    public static func snapshot() -> Snapshot {
        let home = NSHomeDirectory()
        var bundles: [KBAppBundle] = []

        for root in ["/Applications", home + "/Applications"] {
            bundles.append(contentsOf: applications(in: root))
        }
        for suffix in widgetDirectories {
            bundles.append(contentsOf: widgets(in: "/" + suffix))
            bundles.append(contentsOf: widgets(in: home + "/" + suffix))
        }
        for suffix in pluginDirectories {
            bundles.append(contentsOf: plugins(in: "/" + suffix))
            bundles.append(contentsOf: plugins(in: home + "/" + suffix))
        }

        var seen = Set<String>()
        bundles = bundles.filter { seen.insert($0.path).inserted }
        bundles.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return Snapshot(bundles: bundles)
    }

    // MARK: - Discovery

    private static func applications(in path: String) -> [KBAppBundle] {
        let root = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .contentTypeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var result: [KBAppBundle] = []
        for case let url as URL in enumerator {
            if enumerator.level > 3 {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                continue
            }
            if let bundle = bundle(at: url, kind: .application) {
                result.append(bundle)
            }
            enumerator.skipDescendants()
        }
        return result
    }

    private static func widgets(in path: String) -> [KBAppBundle] {
        let widgetType = UTType("com.apple.dashboard.widget")
        return directChildren(in: path) { url in
            if url.pathExtension.caseInsensitiveCompare("wdgt") == .orderedSame {
                return true
            }
            guard let widgetType else { return false }
            let values = try? url.resourceValues(forKeys: [.contentTypeKey])
            return values?.contentType == widgetType
        }.compactMap { bundle(at: $0, kind: .widget) }
    }

    private static func plugins(in path: String) -> [KBAppBundle] {
        directChildren(in: path) { url in
            pluginExtensions.contains(url.pathExtension.lowercased())
        }.compactMap { bundle(at: $0, kind: .plugin) }
    }

    private static func directChildren(in path: String,
                                      matching: (URL) -> Bool) -> [URL] {
        let url = URL(fileURLWithPath: path)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return items.filter(matching)
    }

    private static func bundle(at url: URL, kind: KBAppKind) -> KBAppBundle? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        var info: [String: Any] = [:]
        if let data = try? Data(contentsOf: infoURL),
           let plist = try? PropertyListSerialization.propertyList(
               from: data, format: nil
           ) as? [String: Any] {
            info = plist
        }

        let bundleIdentifier = info["CFBundleIdentifier"] as? String
        let name = (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let displayName = info["CFBundleDisplayName"] as? String
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
        let executable = info["CFBundleExecutable"] as? String
        let isSystemPath = url.path.hasPrefix("/System/")
        let isApple = isSystemPath || (bundleIdentifier?.hasPrefix("com.apple.") ?? false)
        let isOwnBundle = url.lastPathComponent == "Kancerbero.app"
        let isProtected = isApple || isOwnBundle || KBPathPolicy.isProtected(url.path)

        return KBAppBundle(
            path: url.path,
            name: name,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            version: version,
            executable: executable,
            kind: kind,
            isApple: isApple,
            isProtected: isProtected
        )
    }
}
