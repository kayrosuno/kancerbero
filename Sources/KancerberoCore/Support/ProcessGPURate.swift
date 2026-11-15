import Foundation

/// Turns the cumulative per-process GPU counter into the percentage of the
/// sample window spent on the GPU. Activity Monitor reports 100% when the GPU
/// is busy for the whole window, so the value is capped.
public enum ProcessGPURate {
    public static func percent(current: UInt64, previous: UInt64,
                               elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed > 0, current >= previous else {
            return 0
        }
        let seconds = Double(current - previous) / 1_000_000_000
        return min(100, max(0, seconds / elapsed * 100))
    }
}
