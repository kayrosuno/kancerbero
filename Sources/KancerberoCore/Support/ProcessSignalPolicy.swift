import Darwin
import Foundation

public enum KBProcessSignal: String, Codable, Sendable, CaseIterable {
    case terminate
    case forceKill

    public var signalNumber: Int32 {
        switch self {
        case .terminate: return SIGTERM
        case .forceKill: return SIGKILL
        }
    }

    public var displayName: String {
        switch self {
        case .terminate: return "Terminate"
        case .forceKill: return "Force Kill"
        }
    }
}

public enum KBProcessSignalCode {
    public static let notFound = "notfound"
    public static let stale = "stale"
    public static let protectedProcess = "protected"
    public static let authorization = "authorization"
    public static let canceled = "canceled"
    public static let rate = "rate"
    public static let invalid = "invalid"
    public static let daemon = "daemon"
    public static let denied = "denied"
}

public struct KBProcessSignalTarget: Sendable, Equatable {
    public var pid: Int32
    public var uid: UInt32
    public var startTimeUS: UInt64
    public var name: String
    public var path: String
    public var isZombie: Bool

    public init(pid: Int32, uid: UInt32, startTimeUS: UInt64,
                name: String, path: String, isZombie: Bool) {
        self.pid = pid
        self.uid = uid
        self.startTimeUS = startTimeUS
        self.name = name
        self.path = path
        self.isZombie = isZombie
    }
}

public struct KBProcessSignalContext: Sendable, Equatable {
    /// App: the effective uid, or 0 when the app itself runs as root.
    /// Daemon: the peer connection's uid, never the daemon's euid.
    public var localUID: UInt32
    public var daemonPID: Int32?
    public var clientPID: Int32?
    public var isRoot: Bool

    public init(localUID: UInt32, daemonPID: Int32? = nil,
                clientPID: Int32? = nil, isRoot: Bool = false) {
        self.localUID = localUID
        self.daemonPID = daemonPID
        self.clientPID = clientPID
        self.isRoot = isRoot
    }
}

public enum KBProcessSignalRefusal: String, Sendable, Equatable {
    case invalidPID
    case selfTarget
    case daemonTarget
    case clientTarget
    case unknownIdentity
    case unknownPath
    case protectedProcess
    case systemUser
    case zombie

    public var uiMessage: String {
        switch self {
        case .invalidPID: return "Protected system process."
        case .selfTarget, .daemonTarget, .clientTarget:
            return "Kancerbero protects itself and its helper."
        case .unknownIdentity:
            return "The process identity is unavailable; wait for the next refresh."
        case .unknownPath:
            return "The executable path is unavailable; wait for the next refresh."
        case .protectedProcess:
            return "This process is protected by Kancerbero."
        case .systemUser:
            return "Processes owned by system users cannot be killed."
        case .zombie:
            return "The process has already ended."
        }
    }

    public var daemonMessage: String {
        switch self {
        case .invalidPID: return "invalid process id"
        case .selfTarget: return "cannot signal the daemon itself"
        case .daemonTarget: return "cannot signal the daemon"
        case .clientTarget: return "cannot signal the requesting app"
        case .unknownIdentity: return "unknown process identity"
        case .unknownPath: return "unknown executable path"
        case .protectedProcess: return "protected process"
        case .systemUser: return "system user process"
        case .zombie: return "process has already ended"
        }
    }
}

public enum KBProcessSignalDecision: Sendable, Equatable {
    case allowed(requiresAdministrator: Bool)
    case refused(KBProcessSignalRefusal)
}

public enum KBProcessSignalPolicy {
    /// Processes that must never be signaled, even with administrator rights.
    /// Apple apps and system paths are included deliberately; third-party
    /// processes remain killable.
    private static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "windowserver", "loginwindow",
        "securityd", "securityd_system", "syspolicyd", "tccd", "trustd",
        "amfid", "authd", "securityagent", "coreauthd", "configd", "notifyd",
        "distnoted", "opendirectoryd", "directoryservicesd", "launchservicesd",
        "runningboardd", "watchdogd", "powerd", "thermalmonitord",
        "coreduetd", "kancerbero", "kancerberodaemon", "kancerberofilter"
    ]

    private static let protectedPathPrefixes: [String] = [
        "/system/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/library/apple/"
    ]

    public static func decide(target: KBProcessSignalTarget,
                              context: KBProcessSignalContext) -> KBProcessSignalDecision {
        if target.pid <= 1 {
            return .refused(.invalidPID)
        }
        if target.pid == context.daemonPID {
            return .refused(.daemonTarget)
        }
        if target.pid == context.clientPID {
            return .refused(.clientTarget)
        }
        if target.startTimeUS == 0 {
            return .refused(.unknownIdentity)
        }
        if target.isZombie {
            return .refused(.zombie)
        }
        if target.path.isEmpty {
            return .refused(.unknownPath)
        }
        if isProtected(target) {
            return .refused(.protectedProcess)
        }
        if target.uid != 0 && target.uid < 500 {
            return .refused(.systemUser)
        }
        let sameUser = context.isRoot || target.uid == context.localUID
        return .allowed(requiresAdministrator: !sameUser)
    }

    private static func isProtected(_ target: KBProcessSignalTarget) -> Bool {
        let name = target.name.lowercased()
        if protectedNames.contains(name) {
            return true
        }
        let path = target.path.lowercased()
        if path.contains("/kancerbero.app/") || path.contains("/kancerbero.appex/") {
            return true
        }
        return protectedPathPrefixes.contains { path.hasPrefix($0) }
    }
}
