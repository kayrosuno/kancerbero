import Darwin
import Foundation

/// Resolves uid -> user name with `getpwuid_r`. This can block on network
/// directory accounts, so callers must run it off the main thread and cache
/// the result.
public enum UserCollector {
    public static func name(for uid: UInt32) -> String? {
        var size = 1024
        while size <= 65_536 {
            var entry = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: size)
            let status = getpwuid_r(uid_t(uid), &entry, &buffer, size, &result)
            if status == ERANGE {
                size *= 2
                continue
            }
            guard status == 0, let result else { return nil }
            return String(cString: result.pointee.pw_name)
        }
        return nil
    }
}
