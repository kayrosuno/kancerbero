import Darwin
import Foundation

@main
enum ProcessSignalPolicyTests {
    static func main() {
        let daemonPID: Int32 = 90000
        let clientPID: Int32 = 90001
        let otherPID: Int32 = 90002
        let base = KBProcessSignalContext(localUID: 501, daemonPID: daemonPID,
                                          clientPID: clientPID, isRoot: false)

        func target(_ pid: Int32, uid: UInt32 = 501, start: UInt64 = 1_000,
                    name: String = "sleep", path: String = "/bin/sleep",
                    zombie: Bool = false) -> KBProcessSignalTarget {
            KBProcessSignalTarget(pid: pid, uid: uid, startTimeUS: start,
                                  name: name, path: path, isZombie: zombie)
        }

        func expectRefused(_ target: KBProcessSignalTarget,
                           _ reason: KBProcessSignalRefusal,
                           _ context: KBProcessSignalContext = base,
                           _ label: String) {
            let decision = KBProcessSignalPolicy.decide(target: target,
                                                        context: context)
            precondition(decision == .refused(reason),
                         "\(label): expected \(reason), got \(decision)")
        }

        func expectAllowed(_ target: KBProcessSignalTarget,
                           requiresAdministrator: Bool,
                           _ context: KBProcessSignalContext = base,
                           _ label: String) {
            let decision = KBProcessSignalPolicy.decide(target: target,
                                                        context: context)
            precondition(decision == .allowed(requiresAdministrator: requiresAdministrator),
                         "\(label): expected allowed(admin: \(requiresAdministrator)), got \(decision)")
        }

        expectRefused(target(0), .invalidPID, base, "pid 0")
        expectRefused(target(1), .invalidPID, base, "pid 1")
        expectRefused(target(daemonPID), .daemonTarget, base, "daemon pid")
        expectRefused(target(clientPID), .clientTarget, base, "client pid")
        expectRefused(target(otherPID, start: 0), .unknownIdentity, base,
                      "zero start time")
        expectRefused(target(otherPID, zombie: true), .zombie, base, "zombie")
        expectRefused(target(otherPID, name: "launchd",
                             path: "/sbin/launchd"),
                      .protectedProcess, base, "launchd")
        expectRefused(target(otherPID, name: "loginwindow",
                             path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"),
                      .protectedProcess, base, "loginwindow")
        expectRefused(target(otherPID, name: "tccd",
                             path: "/System/Library/PrivateFrameworks/TCC.framework/Support/tccd"),
                      .protectedProcess, base, "tccd")
        expectRefused(target(otherPID, name: "WindowServer",
                             path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"),
                      .protectedProcess, base, "windowserver by name")
        expectRefused(target(otherPID, uid: 88, name: "_windowserver",
                             path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"),
                      .protectedProcess, base, "windowserver by uid and path")
        expectRefused(target(otherPID, uid: 88, name: "system"),
                      .systemUser, base, "system uid")
        expectRefused(target(otherPID, name: "helper",
                             path: "/Applications/Kancerbero.app/Contents/MacOS/helper"),
                      .protectedProcess, base, "Kancerbero bundle path")

        // Ordinary processes owned by the requester are killable even when
        // they live under system paths; `kill(2)` needs no elevation.
        expectAllowed(target(otherPID, name: "photoanalysisd",
                             path: "/System/Library/PrivateFrameworks/PhotoAnalysis.framework/Versions/A/Support/photoanalysisd"),
                      requiresAdministrator: false, base, "same uid /System")
        expectAllowed(target(otherPID, name: "secd",
                             path: "/usr/libexec/secd"),
                      requiresAdministrator: false, base, "same uid /usr/libexec")
        expectAllowed(target(otherPID, name: "cfprefsd",
                             path: "/usr/sbin/cfprefsd"),
                      requiresAdministrator: false, base, "same uid /usr/sbin")
        expectAllowed(target(otherPID, path: ""),
                      requiresAdministrator: false, base, "same uid empty path")
        expectAllowed(target(otherPID), requiresAdministrator: false, base,
                      "same uid")
        expectAllowed(target(otherPID, uid: 42), requiresAdministrator: false,
                      KBProcessSignalContext(localUID: 42, daemonPID: daemonPID,
                                             clientPID: clientPID, isRoot: false),
                      "same migrated uid below 500")

        // Another uid keeps the full hardening, even for paths that are fine
        // for the owner.
        expectRefused(target(otherPID, uid: 502, name: "agent",
                             path: "/System/Library/agent"),
                      .protectedProcess, base, "other uid /System")
        expectRefused(target(otherPID, uid: 502, name: "helper",
                             path: "/usr/libexec/helper"),
                      .protectedProcess, base, "other uid /usr/libexec")
        expectRefused(target(otherPID, uid: 502, name: "helper", path: ""),
                      .unknownPath, base, "other uid empty path")
        expectRefused(target(otherPID, uid: 42), .systemUser, base,
                      "other system uid")
        expectAllowed(target(otherPID, uid: 502),
                      requiresAdministrator: true, base, "other uid innocuous path")
        expectAllowed(target(otherPID, uid: 0, name: "sudo", path: "/bin/sleep"),
                      requiresAdministrator: true, base, "root target with admin")

        let rootContext = KBProcessSignalContext(localUID: 0,
                                                 daemonPID: daemonPID,
                                                 clientPID: clientPID,
                                                 isRoot: true)
        expectAllowed(target(otherPID, uid: 0), requiresAdministrator: false,
                      rootContext, "root app signals root locally")
        expectRefused(target(otherPID, uid: 0, name: "helper",
                             path: "/usr/libexec/helper"),
                      .protectedProcess, rootContext,
                      "root app keeps system paths protected")
        expectRefused(target(otherPID, uid: 0, name: "helper", path: ""),
                      .unknownPath, rootContext, "root app empty path")

        // The daemon reports isRoot = false even for a root XPC peer, so the
        // uid-0 requester must still skip the administrator form and keep the
        // elevated path checks.
        let rootPeer = KBProcessSignalContext(localUID: 0, daemonPID: daemonPID,
                                              clientPID: clientPID, isRoot: false)
        expectAllowed(target(otherPID, uid: 0), requiresAdministrator: false,
                      rootPeer, "root peer signals root without admin")
        expectRefused(target(otherPID, uid: 0, name: "helper",
                             path: "/System/Library/helper"),
                      .protectedProcess, rootPeer,
                      "root peer keeps system paths protected")

        precondition(KBProcessSignal.terminate.signalNumber == SIGTERM)
        precondition(KBProcessSignal.forceKill.signalNumber == SIGKILL)

        print("ProcessSignalPolicyTests: ok")
    }
}
