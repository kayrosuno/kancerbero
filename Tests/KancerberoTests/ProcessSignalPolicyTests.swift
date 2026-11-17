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

        expectRefused(target(0), .invalidPID, base, "pid 0")
        expectRefused(target(1), .invalidPID, base, "pid 1")
        expectRefused(target(daemonPID), .daemonTarget, base, "daemon pid")
        expectRefused(target(clientPID), .clientTarget, base, "client pid")
        expectRefused(target(otherPID, start: 0), .unknownIdentity, base,
                      "zero start time")
        expectRefused(target(otherPID, zombie: true), .zombie, base, "zombie")
        expectRefused(target(otherPID, path: ""), .unknownPath, base,
                      "empty path")
        expectRefused(target(otherPID, name: "launchd",
                             path: "/sbin/launchd"),
                      .protectedProcess, base, "launchd")
        expectRefused(target(otherPID, name: "loginwindow",
                             path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"),
                      .protectedProcess, base, "loginwindow")
        expectRefused(target(otherPID, uid: 88, name: "_windowserver",
                             path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"),
                      .protectedProcess, base, "windowserver")
        expectRefused(target(otherPID, name: "helper",
                             path: "/usr/libexec/helper"),
                      .protectedProcess, base, "usr libexec")
        expectRefused(target(otherPID, name: "Kancerbero",
                             path: "/Applications/Kancerbero.app/Contents/MacOS/Kancerbero"),
                      .protectedProcess, base, "Kancerbero app")
        expectRefused(target(otherPID, uid: 88, name: "system"),
                      .systemUser, base, "system uid")

        precondition(KBProcessSignalPolicy.decide(target: target(otherPID),
                                                  context: base)
                     == .allowed(requiresAdministrator: false),
                     "same uid should be allowed locally")
        precondition(KBProcessSignalPolicy.decide(target: target(otherPID, uid: 502),
                                                  context: base)
                     == .allowed(requiresAdministrator: true),
                     "other uid should require administrator")
        precondition(KBProcessSignalPolicy.decide(target: target(otherPID, uid: 0,
                                                                 name: "sudo",
                                                                 path: "/bin/sleep"),
                                                  context: base)
                     == .allowed(requiresAdministrator: true),
                     "root target should require administrator")
        let rootContext = KBProcessSignalContext(localUID: 0,
                                                 daemonPID: daemonPID,
                                                 clientPID: clientPID,
                                                 isRoot: true)
        precondition(KBProcessSignalPolicy.decide(target: target(otherPID, uid: 0),
                                                  context: rootContext)
                     == .allowed(requiresAdministrator: false),
                     "root app should signal root locally")

        precondition(KBProcessSignal.terminate.signalNumber == SIGTERM)
        precondition(KBProcessSignal.forceKill.signalNumber == SIGKILL)

        print("ProcessSignalPolicyTests: ok")
    }
}
