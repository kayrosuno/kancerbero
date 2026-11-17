import Darwin
import Foundation
import KancerberoCore
import os
import Security

private let logger = Logger(subsystem: "uno.kayros.kancerbero",
                            category: "daemon.signal")

/// Privileged process signaling. Same-UID targets are accepted with the
/// signed-app peer check; other users and root require an administrator
/// AuthorizationExternalForm that the daemon validates without extending rights.
enum ProcessSignalService {
    private static let adminRight = "system.privilege.admin"
    private static let externalFormLength = 32

    static func signal(_ request: KBProcessSignalRequest,
                       peer: PeerIdentity) -> KBProcessSignalResult {
        guard request.pid > 1, request.startTimeUS != 0 else {
            return failure(request, KBProcessSignalCode.invalid,
                           "invalid process identity")
        }
        guard let first = ProcessCollector.identity(pid: request.pid) else {
            return failure(request, KBProcessSignalCode.notFound,
                           "the process is no longer running")
        }
        guard first.startTimeUS == request.startTimeUS,
              first.uid == request.expectedUID else {
            return failure(request, KBProcessSignalCode.stale,
                           "the process identity changed")
        }
        if let expected = request.expectedPath, !expected.isEmpty,
           !first.path.isEmpty, expected != first.path {
            return failure(request, KBProcessSignalCode.stale,
                           "the process executable changed")
        }

        // The daemon's euid is root; the requester's uid comes from the XPC
        // connection, never from the request payload.
        let context = KBProcessSignalContext(localUID: peer.uid,
                                             daemonPID: getpid(),
                                             clientPID: peer.pid,
                                             isRoot: false)
        var authorized = false
        switch KBProcessSignalPolicy.decide(target: .init(process: first),
                                            context: context) {
        case .refused(let reason):
            return failure(request, KBProcessSignalCode.protectedProcess,
                           reason.daemonMessage)
        case .allowed(let requiresAdministrator):
            if requiresAdministrator {
                guard geteuid() == 0 else {
                    return failure(request, KBProcessSignalCode.daemon,
                                   "the root daemon is required")
                }
                guard let form = request.authorizationExternalForm,
                      isAdministratorAuthorized(form) else {
                    return failure(request, KBProcessSignalCode.authorization,
                                   "administrator authorization is required")
                }
            }
            authorized = true
        }

        // Re-fetch immediately before kill: the process can exec a protected
        // binary without changing pid, start time or uid.
        guard let final = ProcessCollector.identity(pid: request.pid),
              final.startTimeUS == request.startTimeUS,
              final.uid == request.expectedUID else {
            return failure(request, KBProcessSignalCode.stale,
                           "the process identity changed")
        }
        switch KBProcessSignalPolicy.decide(target: .init(process: final),
                                            context: context) {
        case .refused(let reason):
            return failure(request, KBProcessSignalCode.protectedProcess,
                           reason.daemonMessage)
        case .allowed(let requiresAdministrator)
            where requiresAdministrator && !authorized:
            return failure(request, KBProcessSignalCode.authorization,
                           "the process identity changed")
        case .allowed:
            break
        }

        let result = ProcessSignaler.send(request.signal, to: request.pid,
                                          startTimeUS: request.startTimeUS)
        logger.notice("signal pid=\(request.pid, privacy: .public) start=\(request.startTimeUS, privacy: .public) target-uid=\(final.uid, privacy: .public) signal=\(request.signal.rawValue, privacy: .public) admin=\(authorized) requester=\(peer.pid, privacy: .public)/\(peer.uid, privacy: .public) result=\(result.code ?? "ok", privacy: .public)")
        return result
    }

    /// The form is a 32-byte bearer handle. Reconstruct it, check the admin
    /// right with default flags, and free the local reference.
    private static func isAdministratorAuthorized(_ data: Data) -> Bool {
        guard data.count == externalFormLength else { return false }

        var form = AuthorizationExternalForm()
        data.withUnsafeBytes { source in
            withUnsafeMutableBytes(of: &form.bytes) { destination in
                destination.copyMemory(
                    from: UnsafeRawBufferPointer(rebasing: source.prefix(externalFormLength)))
            }
        }
        defer {
            withUnsafeMutableBytes(of: &form.bytes) {
                $0.initializeMemory(as: UInt8.self, repeating: 0)
            }
        }

        var authRef: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&form, &authRef) == errAuthorizationSuccess,
              let authRef else {
            return false
        }
        defer { AuthorizationFree(authRef, []) }

        return adminRight.withCString { name -> Bool in
            var item = AuthorizationItem(name: name, valueLength: 0,
                                         value: nil, flags: 0)
            // The rights struct stores the item pointer, so it must stay
            // valid through AuthorizationCopyRights, not just its init.
            return withUnsafeMutablePointer(to: &item) { itemPointer -> Bool in
                var rights = AuthorizationRights(count: 1, items: itemPointer)

                // No ExtendRights: this machine's system.privilege.admin has
                // allow-root = true, so extending here would authorize root
                // without the app's prompt.
                var authorizedPointer: UnsafeMutablePointer<AuthorizationRights>?
                let status = AuthorizationCopyRights(authRef, &rights, nil, [],
                                                     &authorizedPointer)
                defer {
                    if let authorizedPointer {
                        _ = AuthorizationFreeItemSet(authorizedPointer)
                    }
                }
                guard status == errAuthorizationSuccess,
                      let authorizedPointer else {
                    return false
                }
                let authorized = authorizedPointer.pointee
                guard authorized.count == 1,
                      let items = authorized.items else {
                    return false
                }
                return String(cString: items.pointee.name) == adminRight
            }
        }
    }

    private static func failure(_ request: KBProcessSignalRequest,
                                _ code: String,
                                _ message: String) -> KBProcessSignalResult {
        KBProcessSignalResult(ok: false, code: code, message: message,
                              pid: request.pid,
                              startTimeUS: request.startTimeUS)
    }
}
