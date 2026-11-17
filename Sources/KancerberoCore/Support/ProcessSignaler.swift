import Darwin
import Foundation

public extension KBProcessSignalTarget {
    init(process: KBProcessInfo) {
        self.init(pid: process.pid, uid: process.uid,
                  startTimeUS: process.startTimeUS, name: process.name,
                  path: process.path, isZombie: process.state == .zombie)
    }
}

public enum ProcessSignaler {
    /// Same-UID local path. Revalidates the exact process identity before each
    /// signal; cross-UID targets are refused and must go through the daemon.
    public static func signalLocally(_ request: KBProcessSignalRequest,
                                     clientPID: Int32 = getpid(),
                                     daemonPID: Int32? = nil) -> KBProcessSignalResult {
        guard let current = ProcessCollector.identity(pid: request.pid) else {
            return failure(request, KBProcessSignalCode.notFound,
                           "The process is no longer running.")
        }
        guard current.startTimeUS == request.startTimeUS,
              current.uid == request.expectedUID else {
            return failure(request, KBProcessSignalCode.stale,
                           "The process identity changed; refresh and try again.")
        }
        if let expected = request.expectedPath, !expected.isEmpty,
           !current.path.isEmpty, expected != current.path {
            return failure(request, KBProcessSignalCode.stale,
                           "The process executable changed.")
        }

        let root = geteuid() == 0
        let context = KBProcessSignalContext(
            localUID: root ? 0 : getuid(), daemonPID: daemonPID,
            clientPID: clientPID, isRoot: root)
        switch KBProcessSignalPolicy.decide(target: .init(process: current),
                                            context: context) {
        case .refused(let reason):
            return failure(request, KBProcessSignalCode.protectedProcess,
                           reason.uiMessage)
        case .allowed(requiresAdministrator: true):
            return failure(request, KBProcessSignalCode.authorization,
                           "Administrator authorization is required.")
        case .allowed(requiresAdministrator: false):
            break
        }

        // The process can exec a protected binary without changing pid/start.
        guard let final = ProcessCollector.identity(pid: request.pid),
              final.startTimeUS == request.startTimeUS,
              final.uid == request.expectedUID else {
            return failure(request, KBProcessSignalCode.stale,
                           "The process identity changed.")
        }
        switch KBProcessSignalPolicy.decide(target: .init(process: final),
                                            context: context) {
        case .refused(let reason):
            return failure(request, KBProcessSignalCode.protectedProcess,
                           reason.uiMessage)
        case .allowed(requiresAdministrator: true):
            return failure(request, KBProcessSignalCode.authorization,
                           "Administrator authorization is required.")
        case .allowed(requiresAdministrator: false):
            break
        }

        return send(request.signal, to: request.pid,
                    startTimeUS: request.startTimeUS)
    }

    public static func send(_ signal: KBProcessSignal, to pid: Int32,
                            startTimeUS: UInt64) -> KBProcessSignalResult {
        guard pid > 1, pid != getpid() else {
            return KBProcessSignalResult(
                ok: false, code: KBProcessSignalCode.invalid,
                message: "Invalid process id.", pid: pid,
                startTimeUS: startTimeUS)
        }
        if Darwin.kill(pid, signal.signalNumber) == 0 {
            return KBProcessSignalResult(ok: true, pid: pid,
                                         startTimeUS: startTimeUS)
        }
        let code = errno
        let outcome: (String, String)
        switch code {
        case ESRCH:
            outcome = (KBProcessSignalCode.notFound,
                       "The process is no longer running.")
        case EPERM, EACCES:
            outcome = (KBProcessSignalCode.denied,
                       "The system denied the signal.")
        case EINVAL:
            outcome = (KBProcessSignalCode.invalid, "Invalid signal request.")
        default:
            outcome = (KBProcessSignalCode.invalid,
                       "kill failed (errno \(code)).")
        }
        return KBProcessSignalResult(ok: false, code: outcome.0,
                                     message: outcome.1, pid: pid,
                                     startTimeUS: startTimeUS)
    }

    private static func failure(_ request: KBProcessSignalRequest,
                                _ code: String,
                                _ message: String) -> KBProcessSignalResult {
        KBProcessSignalResult(ok: false, code: code, message: message,
                              pid: request.pid,
                              startTimeUS: request.startTimeUS)
    }
}
