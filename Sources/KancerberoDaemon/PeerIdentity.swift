import Darwin
import Foundation
import KancerberoCore

/// Identity of the process connected over XPC. The uid comes from the
/// connection, never from the request payload.
struct PeerIdentity: Sendable {
    let pid: Int32
    let uid: uid_t
    let gid: gid_t
    let executablePath: String
    let home: String

    init?(pid: Int32, uid: uid_t) {
        guard uid != 0 else { return nil }
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 4096)
        guard getpwuid_r(uid, &record, &buffer, buffer.count, &result) == 0,
              let result else {
            return nil
        }
        self.pid = pid
        self.uid = uid
        self.gid = result.pointee.pw_gid
        self.home = String(cString: result.pointee.pw_dir)
        self.executablePath = ProcessCollector.path(for: pid) ?? ""
    }
}
