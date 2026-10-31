import Darwin

/// Logical-core counts per performance level. Apple silicon exposes
/// `hw.perflevel0` (performance) and `hw.perflevel1` (efficiency); macOS
/// reports the logical CPU indices in that order, so the first
/// `performanceCoreCount` entries are the performance cluster.
public enum CPUTopology {
    public static let performanceCoreCount: Int? = read("hw.perflevel0.logicalcpu")
    public static let efficiencyCoreCount: Int? = read("hw.perflevel1.logicalcpu")

    private static func read(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else {
            return nil
        }
        return Int(value)
    }
}
