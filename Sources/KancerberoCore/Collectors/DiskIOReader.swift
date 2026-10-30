import Foundation

/// Cumulative disk counters from IOBlockStorageDriver.
public struct DiskIOReading: Sendable {
    public var bytesRead: UInt64
    public var bytesWritten: UInt64
    public var readOperations: UInt64
    public var writeOperations: UInt64
}

/// Host-wide disk bytes/operations. Readable without privileges so the Disk
/// I/O tab and the Dock graph work with any daemon version.
public enum DiskIOReader {
    public static func current() -> DiskIOReading? {
        var read: UInt64 = 0
        var written: UInt64 = 0
        var readOps: UInt64 = 0
        var writeOps: UInt64 = 0
        guard kb_disk_io_read(&read, &written, &readOps, &writeOps) == 0 else {
            return nil
        }
        return DiskIOReading(bytesRead: read,
                             bytesWritten: written,
                             readOperations: readOps,
                             writeOperations: writeOps)
    }
}
