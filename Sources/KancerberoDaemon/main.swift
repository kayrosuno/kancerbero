import Darwin
import Foundation
import KancerberoCore
import os

private let logger = Logger(subsystem: "uno.kayros.kancerbero", category: "daemon.lifecycle")

let isDaemon = CommandLine.arguments.contains("--daemon")

guard isDaemon else {
    print("kancerbero daemon \(KBVersion.current) (core \(KBVersion.coreVersion), euid \(geteuid()))")
    print("run with --daemon to start the XPC service")
    exit(0)
}

if geteuid() != 0 {
    logger.warning("daemon is not running as root; only same-uid processes will be visible")
}

let listener = NSXPCListener(machServiceName: KancerberoXPCNames.machService)
// One collector for the daemon's lifetime: it owns the single NStatManager
// and its source table, so a client reconnect must not start a new one.
let collector = CollectionActor()
let delegate = DaemonDelegate(collector: collector)
listener.delegate = delegate
listener.resume()
logger.notice("listening on \(KancerberoXPCNames.machService, privacy: .public)")
RunLoop.main.run()
