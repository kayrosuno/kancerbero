import Foundation

/// Standalone model regression tests; compile alongside KBFilesystem.swift.
/// See docs/verification.md for the command (no test target is required).
@main
enum FilesystemModelTests {
    static func main() {
        func filesystem(size: UInt64 = 460, used: UInt64 = 13,
                        available: UInt64 = 50, inodes: UInt64 = 100,
                        freeInodes: UInt64 = 99) -> KBFilesystem {
            KBFilesystem(filesystem: "/dev/disk3s1s1", type: "apfs", mountPoint: "/",
                         sizeBytes: size, usedBytes: used, availableBytes: available,
                         inodeCount: inodes, freeInodes: freeInodes)
        }

        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
        }

        let apfs = filesystem()
        expect(apfs.capacityPercent == 21, "APFS percentage must use used + available")
        expect(filesystem(size: 100, used: 60, available: 30).capacityPercent == 67,
               "Reserved space is not available; df rounds capacity upward")
        expect(filesystem(used: 1, available: 99).capacityPercent == 1,
               "An exact percentage must not be rounded up again")
        expect(filesystem(used: 0, available: 100).capacityPercent == 0,
               "An empty filesystem with available space is 0%")
        expect(filesystem(used: 100, available: 0).capacityPercent == 100,
               "A full filesystem is 100%")
        expect(filesystem(size: 0, used: 0, available: 0).capacityPercent == 100,
               "df reports zero-capacity automounts as 100%")
        expect(filesystem(used: .max, available: .max).capacityPercent == 50,
               "Adding UInt64 counters must not overflow")
        expect(apfs.usedInodes == 1 && apfs.inodePercent == 1,
               "Inode accounting must use total - free")
        expect(filesystem(inodes: 0, freeInodes: 0).inodePercent == -1,
               "A zero inode total has an undefined percentage")
        expect(filesystem(inodes: 1, freeInodes: 2).usedInodes == 0,
               "Inconsistent inode counters must not underflow")
        expect(filesystem(inodes: 3, freeInodes: 2).inodePercent == 33,
               "df rounds inode percentages to nearest, not upward")
        expect(apfs.id == "/" && !apfs.isCached && apfs.warning == nil,
               "Row identity and default collection status must be stable")
        print("Filesystem model: 12 checks passed")
    }
}
