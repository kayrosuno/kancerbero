import Darwin
import Foundation

public enum KBDaemonDomain: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case system
    case gui
    case user

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .gui: return "GUI"
        case .user: return "User"
        }
    }

    public var domainString: String {
        switch self {
        case .system: return "system"
        case .gui: return "gui/\(getuid())"
        case .user: return "user/\(getuid())"
        }
    }

    public var plistDirectories: [String] {
        switch self {
        case .system:
            return ["/System/Library/LaunchDaemons", "/Library/LaunchDaemons"]
        case .gui, .user:
            return [
                "/System/Library/LaunchAgents",
                "/Library/LaunchAgents",
                (("~/Library/LaunchAgents") as NSString).expandingTildeInPath
            ]
        }
    }

    public static func fromCommandLine() -> KBDaemonDomain? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--daemon-domain"),
              flag + 1 < arguments.count else {
            return nil
        }
        return KBDaemonDomain(rawValue: arguments[flag + 1].lowercased())
    }
}

public enum KBDaemonState: String, Codable, Sendable {
    case running
    case stopped
    case disabled
    case unloaded

    public var displayName: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .disabled: return "Disabled"
        case .unloaded: return "Not loaded"
        }
    }
}

public struct KBDaemonService: Codable, Sendable, Identifiable, Hashable {
    public var label: String
    public var domain: KBDaemonDomain
    public var uid: UInt32?
    public var pid: Int32?
    public var lastExitStatus: Int32?
    public var statusToken: String
    public var isLoaded: Bool
    public var isDisabled: Bool
    public var program: String
    public var arguments: String
    public var plistPath: String
    public var runAtLoad: Bool
    public var keepAlive: Bool
    public var startInterval: Int?
    public var workingDirectory: String
    public var environment: [String: String]
    public var onDemand: Bool

    public var id: String { "\(domain.rawValue):\(label)" }

    public var isRunning: Bool { (pid ?? 0) > 0 }

    public var state: KBDaemonState {
        if isRunning { return .running }
        if isDisabled { return .disabled }
        if isLoaded { return .stopped }
        return .unloaded
    }

    public init(label: String, domain: KBDaemonDomain, uid: UInt32? = nil,
                pid: Int32? = nil, lastExitStatus: Int32? = nil, statusToken: String = "",
                isLoaded: Bool = false, isDisabled: Bool = false,
                program: String = "", arguments: String = "", plistPath: String = "",
                runAtLoad: Bool = false, keepAlive: Bool = false, startInterval: Int? = nil,
                workingDirectory: String = "", environment: [String: String] = [:],
                onDemand: Bool = false) {
        self.label = label
        self.domain = domain
        self.uid = uid
        self.pid = pid
        self.lastExitStatus = lastExitStatus
        self.statusToken = statusToken
        self.isLoaded = isLoaded
        self.isDisabled = isDisabled
        self.program = program
        self.arguments = arguments
        self.plistPath = plistPath
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.startInterval = startInterval
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.onDemand = onDemand
    }
}

public struct KBDaemonSnapshot: Codable, Sendable {
    public var services: [KBDaemonService]
    public var generatedAt: Date
    public var error: String?
    public var source: String

    public init(services: [KBDaemonService], generatedAt: Date = Date(),
                error: String? = nil, source: String) {
        self.services = services
        self.generatedAt = generatedAt
        self.error = error
        self.source = source
    }
}

public enum KBDaemonAction: String, Codable, Sendable {
    case start
    case stop
    case restart
    case enable
    case disable
    case load
    case unload
}

public struct KBDaemonActionRequest: Codable, Sendable {
    public var label: String
    public var domain: KBDaemonDomain
    public var action: KBDaemonAction
    public var plistPath: String?

    public init(label: String, domain: KBDaemonDomain, action: KBDaemonAction,
                plistPath: String? = nil) {
        self.label = label
        self.domain = domain
        self.action = action
        self.plistPath = plistPath
    }
}

public struct KBDaemonActionResult: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var snapshot: KBDaemonSnapshot?

    public init(ok: Bool, message: String, snapshot: KBDaemonSnapshot? = nil) {
        self.ok = ok
        self.message = message
        self.snapshot = snapshot
    }
}
