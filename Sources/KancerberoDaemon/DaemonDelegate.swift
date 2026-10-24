import Darwin
import Foundation
import KancerberoCore
import os

private let logger = Logger(subsystem: "uno.kayros.kancerbero", category: "daemon.listener")

final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    private let service = DaemonService()

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        let uid = newConnection.effectiveUserIdentifier
        let path = ProcessCollector.path(for: pid) ?? "unknown"

        // Development policy: the app bundle and same-uid clients may control
        // services. Production must set `setCodeSigningRequirement` plus a
        // Team ID check instead of relying on the path.
        let isApp = path.contains("/Kancerbero.app/Contents/MacOS/")
        let sameUser = uid == geteuid()
        let canControl = isApp || sameUser

        logger.notice("incoming pid=\(pid) uid=\(uid) canControl=\(canControl) path=\(path, privacy: .public)")

        service.configure(connection: newConnection, canControl: canControl)
        newConnection.exportedInterface = NSXPCInterface(with: KancerberoDaemonXPC.self)
        newConnection.exportedObject = service
        newConnection.remoteObjectInterface = NSXPCInterface(with: KancerberoClientXPC.self)

        let service = self.service
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
