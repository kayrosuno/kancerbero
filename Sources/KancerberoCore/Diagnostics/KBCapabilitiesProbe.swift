import Darwin
import Foundation

public enum KBCapabilitiesProbe {
    public static func current() -> KBCapabilities {
        var privcheck: Int32 = -1
        _ = kb_sysctl_int("net.statistics_privcheck", &privcheck)
        let nstatAvailable = NStatCollector.availability().available
        let root = geteuid() == 0
        return KBCapabilities(
            nstat: nstatAvailable,
            root: root,
            statisticsPrivcheck: Int(privcheck),
            libprocAllUsers: root,
            interfaceSplits: true,
            trash: true
        )
    }
}
