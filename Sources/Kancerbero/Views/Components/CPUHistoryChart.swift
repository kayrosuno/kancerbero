import SwiftUI

/// Stacked CPU history in the style of Activity Monitor: system at the
/// bottom, user stacked above it, nice above user, and the remaining capacity
/// drawn as free. The vertical scale is fixed at 0...100 so the free band is
/// meaningful (unlike the peak-normalised sparklines).
struct CPUHistoryChart: View {
    var user: [Double]
    var system: [Double]
    var nice: [Double]
    var userColor: Color
    var systemColor: Color
    var niceColor: Color
    var freeColor: Color

    private var count: Int {
        min(60, min(user.count, min(system.count, nice.count)))
    }

    private var slices: (user: [Double], system: [Double], nice: [Double]) {
        let n = count
        return (Array(user.suffix(n)),
                Array(system.suffix(n)),
                Array(nice.suffix(n)))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let data = slices
            let n = data.user.count
            let stepX = n > 1 ? size.width / CGFloat(n - 1) : size.width
            let stacked = (0..<n).map { index in
                let system = data.system[index]
                let user = data.user[index]
                let nice = data.nice[index]
                return (system: system,
                        userTop: system + user,
                        totalTop: system + user + nice)
            }

            Canvas { context, canvasSize in
                guard n > 1 else { return }

                // Horizontal grid at 25/50/75 %.
                for fraction in [0.25, 0.5, 0.75] {
                    var grid = Path()
                    let y = canvasSize.height * (1 - fraction)
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    context.stroke(grid,
                                   with: .color(.secondary.opacity(0.12)),
                                   lineWidth: 0.5)
                }

                func y(_ percent: Double) -> CGFloat {
                    let clamped = min(max(percent, 0), 100) / 100
                    return canvasSize.height - CGFloat(clamped) * canvasSize.height
                }

                func band(lower: [Double], upper: [Double]) -> Path {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y(lower[0])))
                    for index in 1..<n {
                        path.addLine(to: CGPoint(x: CGFloat(index) * stepX,
                                                 y: y(lower[index])))
                    }
                    for index in stride(from: n - 1, through: 0, by: -1) {
                        path.addLine(to: CGPoint(x: CGFloat(index) * stepX,
                                                 y: y(upper[index])))
                    }
                    path.closeSubpath()
                    return path
                }

                func topLine(_ values: [Double]) -> Path {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y(values[0])))
                    for index in 1..<n {
                        path.addLine(to: CGPoint(x: CGFloat(index) * stepX,
                                                 y: y(values[index])))
                    }
                    return path
                }

                let systemValues = stacked.map(\.system)
                let userTops = stacked.map(\.userTop)
                let totals = stacked.map(\.totalTop)

                // Free capacity on top.
                context.fill(band(lower: totals, upper: Array(repeating: 100, count: n)),
                             with: .color(freeColor.opacity(0.35)))

                // Stacked usage.
                context.fill(band(lower: userTops, upper: totals),
                             with: .color(niceColor.opacity(0.7)))
                context.fill(band(lower: systemValues, upper: userTops),
                             with: .color(userColor.opacity(0.7)))
                context.fill(band(lower: Array(repeating: 0, count: n), upper: systemValues),
                             with: .color(systemColor.opacity(0.75)))

                let lineStyle = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                context.stroke(topLine(systemValues), with: .color(systemColor), style: lineStyle)
                context.stroke(topLine(userTops), with: .color(userColor), style: lineStyle)
                context.stroke(topLine(totals), with: .color(niceColor), style: lineStyle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU history")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let latest = slices
        guard let user = latest.user.last,
              let system = latest.system.last,
              let nice = latest.nice.last else { return "Collecting" }
        let free = max(0, 100 - user - system - nice)
        return String(format: "System %.1f percent, user %.1f percent, nice %.1f percent, free %.1f percent",
                      system, user, nice, free)
    }
}
