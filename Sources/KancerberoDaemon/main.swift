import Darwin
import Foundation
import KancerberoCore
import os

private let logger = Logger(subsystem: "com.alejandro.kancerbero", category: "daemon.lifecycle")

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
let delegate = DaemonDelegate()
listener.delegate = delegate
listener.resume()
logger.notice("listening on \(KancerberoXPCNames.machService, privacy: .public)")
RunLoop.main.run()
