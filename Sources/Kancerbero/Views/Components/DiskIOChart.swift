import SwiftUI

enum DiskIOGraphMode: String, CaseIterable, Identifiable, Equatable {
    case data
    case operations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .data: return "Data"
        case .operations: return "Operations"
        }
    }

    func format(_ value: Double, units: KBByteUnitSystem) -> String {
        switch self {
        case .data: return KBFormat.byteRate(value, units: units)
        case .operations: return KBFormat.opsRate(value)
        }
    }
}

/// Disk read/write history as a mirrored bar equalizer, like the traffic
/// chart: reads on top of the centre line and writes below it, sharing one
/// vertical scale.
struct DiskIOChart: View {
    var mode: DiskIOGraphMode
    var read: [Double]
    var write: [Double]
    var readColor: Color
    var writeColor: Color
    var sampleInterval: TimeInterval = 1
    var units: KBByteUnitSystem = .binary

    private var count: Int {
        min(MirroredBarChart.window, min(read.count, write.count))
    }

    var body: some View {
        MirroredBarChart(
            top: read,
            bottom: write,
            format: { mode.format($0, units: units) },
            topTint: readColor,
            bottomTint: writeColor,
            topLabel: "Read",
            bottomLabel: "Write",
            fallbackCeiling: mode == .data ? 1_048_576 : 10,
            sampleInterval: sampleInterval,
            accessibilityLabel: "Disk activity",
            accessibilityValue: accessibilityValue
        )
        .overlay {
            if count < 2 {
                Text("Collecting disk activity…")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var accessibilityValue: String {
        let n = count
        guard n > 0 else { return "Collecting" }
        let reads = Array(read.suffix(n))
        let writes = Array(write.suffix(n))
        return "Read \(mode.format(reads.last ?? 0, units: units)), write \(mode.format(writes.last ?? 0, units: units))"
    }
}
