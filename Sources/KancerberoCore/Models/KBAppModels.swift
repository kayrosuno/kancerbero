import Foundation

public enum KBAppKind: String, Codable, Sendable, CaseIterable, Hashable {
    case application
    case widget
    case plugin

    public var title: String {
        switch self {
        case .application: return "Application"
        case .widget: return "Widget"
        case .plugin: return "Plugin"
        }
    }

    public var pluralTitle: String {
        switch self {
        case .application: return "Applications"
        case .widget: return "Widgets"
        case .plugin: return "Plugins"
        }
    }
}

/// Categories of files left behind by an installed bundle, mirroring the
/// groups Activity Monitor-style uninstallers use.
public enum KBLeftoverKind: String, Codable, Sendable, CaseIterable, Hashable {
    case preferences
    case byHost
    case syncedPreferences
    case appSupport
    case cache
    case cookie
    case httpStorage
    case webKit
    case container
    case groupContainer
    case appScripts
    case savedState
    case launchAgent
    case launchDaemon
    case log
    case safariExtension
    case service
    case shared

    public var title: String {
        switch self {
        case .preferences: return "Preferences"
        case .byHost: return "Preferences (ByHost)"
        case .syncedPreferences: return "Synced Preferences"
        case .appSupport: return "Application Support"
        case .cache: return "Caches"
        case .cookie: return "Cookies"
        case .httpStorage: return "HTTP Storage"
        case .webKit: return "WebKit"
        case .container: return "Containers"
        case .groupContainer: return "Group Containers"
        case .appScripts: return "Application Scripts"
        case .savedState: return "Saved Application State"
        case .launchAgent: return "Launch Agents"
        case .launchDaemon: return "Launch Daemons"
        case .log: return "Logs"
        case .safariExtension: return "Safari Extensions"
        case .service: return "Services"
        case .shared: return "Shared"
        }
    }

    /// Order used by the leftovers panel.
    public var sortOrder: Int {
        switch self {
        case .preferences, .byHost, .syncedPreferences: return 0
        case .appSupport: return 1
        case .cache: return 2
        case .container, .groupContainer, .appScripts: return 3
        case .savedState: return 4
        case .launchAgent, .launchDaemon: return 5
        case .log: return 6
        case .cookie, .httpStorage, .webKit: return 7
        case .safariExtension, .service: return 8
        case .shared: return 9
        }
    }
}

public struct KBAppBundle: Identifiable, Codable, Sendable, Hashable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var displayName: String?
    public var bundleIdentifier: String?
    public var version: String?
    public var executable: String?
    public var kind: KBAppKind
    public var isApple: Bool
    public var isProtected: Bool
    public var sizeBytes: Int64?

    public init(path: String, name: String, displayName: String? = nil,
                bundleIdentifier: String? = nil, version: String? = nil,
                executable: String? = nil, kind: KBAppKind = .application,
                isApple: Bool = false, isProtected: Bool = false,
                sizeBytes: Int64? = nil) {
        self.path = path
        self.name = name
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.executable = executable
        self.kind = kind
        self.isApple = isApple
        self.isProtected = isProtected
        self.sizeBytes = sizeBytes
    }
}

public struct KBLeftover: Identifiable, Codable, Sendable, Hashable {
    public var id: String { path }
    public var path: String
    public var kind: KBLeftoverKind
    public var sizeBytes: Int64?
    /// Checked when the bundle is selected for removal.
    public var selectedByDefault: Bool
    /// Outside the user's writable area; removing it needs the root daemon.
    public var requiresPrivilege: Bool
    public var matchReason: String

    public init(path: String, kind: KBLeftoverKind, sizeBytes: Int64? = nil,
                selectedByDefault: Bool = true, requiresPrivilege: Bool = false,
                matchReason: String = "") {
        self.path = path
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.selectedByDefault = selectedByDefault
        self.requiresPrivilege = requiresPrivilege
        self.matchReason = matchReason
    }
}

public struct KBAppCandidate: Identifiable, Codable, Sendable, Hashable {
    public var id: String { bundle.id }
    public var bundle: KBAppBundle
    public var leftovers: [KBLeftover]

    public init(bundle: KBAppBundle, leftovers: [KBLeftover]) {
        self.bundle = bundle
        self.leftovers = leftovers
    }

    public var totalBytes: Int64 {
        (bundle.sizeBytes ?? 0) + leftovers.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }
}
