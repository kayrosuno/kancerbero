import Foundation

/// Shared path policy for the uninstaller. The app uses it to decide whether a
/// leftover can be trashed directly, and the privileged daemon revalidates every
/// path with it before touching the file system.
public enum KBPathPolicy {
    /// `/System/Volumes/Data` is a firmlink prefix on modern macOS; strip it so
    /// both sides of a comparison use the same coordinates.
    public static let firmwarePrefix = "/System/Volumes/Data"

    public static let systemAllowedRoots: [String] = [
        "/Applications",
        "/Users/Shared",
        "/Library/Application Support",
        "/Library/Preferences",
        "/Library/PreferencePanes",
        "/Library/Services",
        "/Library/Safari/Extensions",
        "/Library/Internet Plug-Ins",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
        "/Library/Logs",
        "/Library/Caches",
        "/Library/Widgets",
        "/Library/QuickLook",
        "/Library/Spotlight",
        "/Library/Audio/Plug-Ins",
        "/Library/ColorPickers",
        "/Library/Screen Savers",
        "/Library/ScriptingAdditions"
    ]

    private static let userLibrarySuffixes: [String] = [
        "Library/Application Support",
        "Library/Preferences",
        "Library/Preferences/ByHost",
        "Library/SyncedPreferences",
        "Library/PreferencePanes",
        "Library/Services",
        "Library/Safari/Extensions",
        "Library/Internet Plug-Ins",
        "Library/LaunchAgents",
        "Library/Logs",
        "Library/Caches",
        "Library/Widgets",
        "Library/QuickLook",
        "Library/Spotlight",
        "Library/Audio/Plug-Ins",
        "Library/ColorPickers",
        "Library/Screen Savers",
        "Library/ScriptingAdditions",
        "Library/Containers",
        "Library/Group Containers",
        "Library/Application Scripts",
        "Library/Saved Application State",
        "Library/HTTPStorages",
        "Library/WebKit",
        "Library/Cookies"
    ]

    public static let protectedRoots: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/private",
        "/var",
        "/Library/Apple",
        "/Library/PrivilegedHelperTools",
        "/Library/Extensions",
        "/Library/SystemExtensions",
        "/Library/Keychains",
        "/Library/Security",
        "/Library/Updates"
    ]

    /// Canonical comparison form: firmlink prefix removed, path standardized.
    public static func normalized(_ path: String) -> String {
        let standard = (path as NSString).standardizingPath
        if standard == firmwarePrefix {
            return "/"
        }
        if standard.hasPrefix(firmwarePrefix + "/") {
            return String(standard.dropFirst(firmwarePrefix.count))
        }
        return standard
    }

    public static func allowedRoots(home: String) -> [String] {
        var roots = systemAllowedRoots
        let home = normalized(home)
        for suffix in userLibrarySuffixes {
            roots.append(home + "/" + suffix)
        }
        roots.append(home + "/Applications")
        return roots.map(normalized)
    }

    /// True when `path` is strictly inside an allowed root and not protected.
    public static func isAllowed(_ path: String, home: String) -> Bool {
        let item = normalized(path)
        guard item.hasPrefix("/"), item != "/", !item.contains("/../") else {
            return false
        }
        if isProtected(item) {
            return false
        }
        return allowedRoots(home: home).contains { item.hasPrefix($0 + "/") }
    }

    public static func isProtected(_ path: String) -> Bool {
        let item = normalized(path)
        return protectedRoots.contains { item == $0 || item.hasPrefix($0 + "/") }
    }

    /// Path of the leftover that needs the root daemon rather than the app.
    public static func requiresPrivilege(_ path: String, home: String) -> Bool {
        let item = normalized(path)
        let home = normalized(home)
        if item.hasPrefix(home + "/") || item.hasPrefix("/Users/Shared/") ||
            item.hasPrefix("/Applications/") {
            return !FileManager.default.isWritableFile(atPath: item)
        }
        return true
    }
}
