import SwiftUI

/// Activity Monitor-style memory-pressure line. The height is the pressure
/// percentage (`100 - memorystatus_get_level`), and the line colour follows the
/// kernel pressure level: green (normal), yellow (warning), red (critical).
struct MemoryPressureChart: View {
    var values: [Int]
    var levels: [Int]

    private var count: Int {
        min(60, min(values.count, levels.count))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let n = count
            let stepX = n > 1 ? size.width / CGFloat(n - 1) : size.width

            Canvas { context, canvasSize in
                // 50 % reference line.
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: canvasSize.height * 0.5))
                grid.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height * 0.5))
                context.stroke(grid, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)

                guard n > 1 else { return }

                func point(_ index: Int) -> CGPoint {
                    let percent = min(max(Double(values[index]), 0), 100) / 100
                    return CGPoint(x: CGFloat(index) * stepX,
                                   y: canvasSize.height - CGFloat(percent) * canvasSize.height)
                }

                func color(for level: Int) -> Color {
                    switch level {
                    case 1: return .green
                    case 2, 3: return .yellow
                    default: return level >= 4 ? .red : .secondary
                    }
                }

                // Soft area under the line in the current band colour.
                var area = Path()
                area.move(to: CGPoint(x: 0, y: canvasSize.height))
                area.addLine(to: point(0))
                for index in 1..<n {
                    area.addLine(to: point(index))
                }
                area.addLine(to: CGPoint(x: CGFloat(n - 1) * stepX,
                                         y: canvasSize.height))
                area.closeSubpath()
                context.fill(area, with: .color(color(for: levels[n - 1]).opacity(0.10)))

                // Segment-wise line colour so a change of band is visible.
                for index in 1..<n {
                    var segment = Path()
                    segment.move(to: point(index - 1))
                    segment.addLine(to: point(index))
                    context.stroke(segment,
                                   with: .color(color(for: levels[index])),
                                   style: StrokeStyle(lineWidth: 1.6,
                                                      lineCap: .round,
                                                      lineJoin: .round))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memory pressure")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let value = values.suffix(count).last else { return "Collecting" }
        return "\(value) percent"
    }
}
