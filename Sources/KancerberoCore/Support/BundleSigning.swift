import Foundation
import Security

/// Code-signature helpers shared by the inventory (Apple/SIP detection) and the
/// daemon (revalidating a bundle before it is trashed).
public enum KBBundleSigning {
    public static func entitlements(of url: URL) -> [String: Any]? {
        guard let code = staticCode(for: url) else { return nil }
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard status == errSecSuccess,
              let dictionary = information as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] else {
            return nil
        }
        return entitlements as? [String: Any]
    }

    public static func applicationGroups(of url: URL) -> [String] {
        guard let groups = entitlements(of: url)?["com.apple.security.application-groups"] else {
            return []
        }
        if let value = groups as? String {
            return [value]
        }
        return groups as? [String] ?? []
    }

    public static func isAppleSigned(_ url: URL) -> Bool {
        guard let code = staticCode(for: url) else { return false }
        var requirement: SecRequirement?
        let created = SecRequirementCreateWithString(
            "anchor apple" as CFString, [], &requirement
        )
        guard created == errSecSuccess, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    public static func bundleIdentifier(of url: URL) -> String? {
        guard let code = staticCode(for: url) else { return nil }
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard status == errSecSuccess,
              let dictionary = information as? [String: Any] else {
            return nil
        }
        return dictionary[kSecCodeInfoIdentifier as String] as? String
    }

    private static func staticCode(for url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess else { return nil }
        return code
    }
}
