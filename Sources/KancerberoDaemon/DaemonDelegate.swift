import Darwin
import Foundation
import KancerberoCore
import os

private let logger = Logger(subsystem: "uno.kayros.kancerbero", category: "daemon.listener")

final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        let uid = newConnection.effectiveUserIdentifier
        let path = ProcessCollector.path(for: pid) ?? "unknown"

        #if DEBUG
        // Development builds are unsigned, so Release-style signature checks
        // would reject the app. This path check is a convenience, not a
        // security boundary; Release enforces the Developer ID requirement.
        let isApp = uid != 0 && path.contains("/Kancerbero.app/Contents/MacOS/")
        let canControl = isApp || uid == geteuid()
        let canTrash = isApp
        #else
        newConnection.setCodeSigningRequirement(DaemonClientPolicy.requirement)
        let canControl = uid != 0
        let canTrash = DaemonClientPolicy.isTrusted(pid: pid)
        #endif

        guard let peer = PeerIdentity(pid: pid, uid: uid) else {
            logger.error("rejected connection pid=\(pid) uid=\(uid) path=\(path, privacy: .public)")
            return false
        }

        logger.notice("incoming pid=\(pid) uid=\(uid) canControl=\(canControl) canTrash=\(canTrash) path=\(path, privacy: .public)")

        let service = DaemonService(peer: peer,
                                    canControl: canControl,
                                    canTrash: canTrash,
                                    connection: newConnection)
        newConnection.exportedInterface = NSXPCInterface(with: KancerberoDaemonXPC.self)
        newConnection.exportedObject = service
        newConnection.remoteObjectInterface = NSXPCInterface(with: KancerberoClientXPC.self)
        newConnection.invalidationHandler = {
            logger.notice("connection invalidated pid=\(pid)")
            service.connectionInvalidated()
        }
        newConnection.interruptionHandler = {
            logger.notice("connection interrupted pid=\(pid)")
        }

        newConnection.resume()
        return true
    }
}
