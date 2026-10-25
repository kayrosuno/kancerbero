import SwiftUI

struct MeterSegment: Identifiable {
    let id: String
    let value: Double
    let color: Color

    init(id: String, value: Double, color: Color) {
        self.id = id
        self.value = max(0, value)
        self.color = color
    }
}

/// Proportional segmented bar used by the per-core CPU meters and the memory
/// breakdown. Values are normalised by their sum; a zero total leaves the
/// background visible.
struct SegmentedMeter: View {
    let segments: [MeterSegment]
    var height: CGFloat = 8
    var accessibilityLabel = "Usage"

    private var total: Double {
        segments.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary.opacity(0.3))
                if total > 0 {
                    HStack(spacing: 0) {
                        ForEach(segments) { segment in
                            Rectangle()
                                .fill(segment.color)
                                .frame(width: proxy.size.width * segment.value / total)
                        }
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        segments
            .map { "\($0.id) \(Int(($0.value / max(total, 1)) * 100))%" }
            .joined(separator: ", ")
    }
}

struct MeterLegendItem: Identifiable {
    let id: String
    let label: String
    let value: String
    let color: Color

    init(_ label: String, value: String, color: Color) {
        self.id = label
        self.label = label
        self.value = value
        self.color = color
    }
}

struct MeterLegend: View {
    let items: [MeterLegendItem]

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.color)
                        .frame(width: 7, height: 7)
                    Text(item.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text(item.value)
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.8))
                }
                .font(.system(size: 10))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }
}
