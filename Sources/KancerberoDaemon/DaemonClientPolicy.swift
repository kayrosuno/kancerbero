import Foundation
import Security

/// Release-only client authentication for destructive requests: the caller must
/// be Kancerbero signed by the project's Developer ID team. Debug builds skip
/// this because they are intentionally unsigned; the path check in
/// `DaemonDelegate` is a development convenience, not a security boundary.
enum DaemonClientPolicy {
    static let requirement = "identifier \"uno.kayros.kancerbero\" "
        + "and anchor apple generic "
        + "and certificate leaf[subject.OU] = \"AK37TK8X2Y\""

    static func isTrusted(pid: Int32) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            return false
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            Self.requirement as CFString, [], &requirement
        ) == errSecSuccess, let requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
