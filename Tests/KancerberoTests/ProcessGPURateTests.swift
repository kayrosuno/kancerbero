import Foundation

/// Standalone GPU rate regression tests; compile alongside ProcessGPURate.swift.
/// See docs/verification.md for the command (no test target is required).
@main
enum ProcessGPURateTests {
    static func main() {
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
        }

        let second: UInt64 = 1_000_000_000

        expect(ProcessGPURate.percent(current: 10, previous: 10, elapsed: 1) == 0,
               "A flat counter is 0%")
        expect(ProcessGPURate.percent(current: second / 4, previous: 0,
                                      elapsed: 1) == 25,
               "250 ms of GPU time in a 1 s window is 25%")
        expect(ProcessGPURate.percent(current: second / 2, previous: 0,
                                      elapsed: 2) == 25,
               "The percentage uses the actual elapsed window")
        expect(ProcessGPURate.percent(current: 3 * second / 2, previous: 0,
                                      elapsed: 1) == 100,
               "More GPU time than wall time is capped at 100%")
        expect(ProcessGPURate.percent(current: 1, previous: 2, elapsed: 1) == 0,
               "A counter that goes backwards yields 0%, never a negative")
        expect(ProcessGPURate.percent(current: second, previous: 0,
                                      elapsed: 0) == 0,
               "A zero window has no percentage")
        expect(ProcessGPURate.percent(current: second, previous: 0,
                                      elapsed: -.infinity) == 0,
               "A non-finite window has no percentage")
        expect(ProcessGPURate.percent(current: .max, previous: .max - second,
                                      elapsed: 1) == 100,
               "Large counters near UInt64.max must not overflow")
        expect(ProcessGPURate.percent(current: 250_000_000, previous: 0,
                                      elapsed: 0.5) == 50,
               "Sub-second windows keep fractional percentages")

        print("Process GPU rate: 9 checks passed")
    }
}
