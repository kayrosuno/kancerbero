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

    func format(_ value: Double) -> String {
        switch self {
        case .data: return KBFormat.byteRate(value)
        case .operations: return KBFormat.opsRate(value)
        }
    }
}

/// Mirrored read/write history, like Activity Monitor's disk graph: reads on
/// top of the centre line and writes below it, sharing one vertical scale.
struct DiskIOChart: View {
    var mode: DiskIOGraphMode
    var read: [Double]
    var write: [Double]
    var readColor: Color
    var writeColor: Color

    private var count: Int {
        min(60, min(read.count, write.count))
    }

    private var ceiling: Double {
        let n = count
        guard n > 0 else { return 1 }
        let values = Array(read.suffix(n)) + Array(write.suffix(n))
        return niceCeiling(values.max() ?? 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let n = count
            let stepX = n > 1 ? size.width / CGFloat(n - 1) : size.width
            let reads = n > 0 ? Array(read.suffix(n)) : []
            let writes = n > 0 ? Array(write.suffix(n)) : []
            let mid = size.height / 2
            let half = max(1, mid - 10)

            Canvas { context, canvasSize in
                // Grid and centre line.
                for fraction in [0.25, 0.5, 0.75] {
                    var grid = Path()
                    let y = canvasSize.height * fraction
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    context.stroke(grid,
                                   with: .color(.secondary.opacity(0.12)),
                                   lineWidth: 0.5)
                }
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: mid))
                baseline.addLine(to: CGPoint(x: canvasSize.width, y: mid))
                context.stroke(baseline,
                               with: .color(.secondary.opacity(0.25)),
                               lineWidth: 0.7)

                guard n > 1 else { return }

                func x(_ index: Int) -> CGFloat { CGFloat(index) * stepX }
                func topY(_ value: Double) -> CGFloat {
                    mid - CGFloat(min(max(value, 0), ceiling) / ceiling) * half
                }
                func bottomY(_ value: Double) -> CGFloat {
                    mid + CGFloat(min(max(value, 0), ceiling) / ceiling) * half
                }

                func series(_ values: [Double],
                            y: (Double) -> CGFloat,
                            base: CGFloat,
                            color: Color) {
                    var line = Path()
                    var area = Path()
                    area.move(to: CGPoint(x: 0, y: base))
                    for (index, value) in values.enumerated() {
                        let point = CGPoint(x: x(index), y: y(value))
                        if index == 0 {
                            line.move(to: point)
                            area.addLine(to: point)
                        } else {
                            line.addLine(to: point)
                            area.addLine(to: point)
                        }
                    }
                    area.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX,
                                             y: base))
                    area.closeSubpath()
                    context.fill(area, with: .color(color.opacity(0.18)))
                    context.stroke(line, with: .color(color),
                                   style: StrokeStyle(lineWidth: 1.6,
                                                      lineCap: .round,
                                                      lineJoin: .round))
                }

                series(reads, y: topY, base: mid, color: readColor)
                series(writes, y: bottomY, base: mid, color: writeColor)

                // Scale labels at the left edge.
                let top = Text(mode.format(ceiling))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                context.draw(top, at: CGPoint(x: 4, y: 8), anchor: .topLeading)
                let bottom = Text(mode.format(ceiling))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                context.draw(bottom, at: CGPoint(x: 4, y: canvasSize.height - 8),
                             anchor: .bottomLeading)
            }
        }
        .overlay {
            if count < 2 {
                Text("Collecting disk activity…")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk activity")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let n = count
        guard n > 0 else { return "Collecting" }
        let reads = Array(read.suffix(n))
        let writes = Array(write.suffix(n))
        return "Read \(mode.format(reads.last ?? 0)), write \(mode.format(writes.last ?? 0))"
    }

    private func niceCeiling(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        let exponent = floor(log10(value))
        let magnitude = pow(10, exponent)
        let normalized = value / magnitude
        let nice: Double
        if normalized <= 1 { nice = 1 }
        else if normalized <= 2 { nice = 2 }
        else if normalized <= 5 { nice = 5 }
        else { nice = 10 }
        return nice * magnitude
    }
}
