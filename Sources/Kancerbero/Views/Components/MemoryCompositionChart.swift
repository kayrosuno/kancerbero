import SwiftUI

/// Stacked memory-composition history in the style of Activity Monitor:
/// App at the bottom, then Wired, Compressed and Cached, with Free on top.
/// The scale is fixed at 0...100 % of physical memory so the free band stays
/// meaningful across samples (unlike the peak-normalised sparklines).
struct MemoryCompositionChart: View {
    var app: [Double]
    var wired: [Double]
    var compressed: [Double]
    var cached: [Double]
    var free: [Double]

    var appColor: Color
    var wiredColor: Color
    var compressedColor: Color
    var cachedColor: Color
    var freeColor: Color

    private var count: Int {
        min(60, min(app.count,
                    min(wired.count,
                        min(compressed.count, min(cached.count, free.count)))))
    }

    /// Cumulative tops for each sample, clamped to 0...100 so a sample whose
    /// committed memory exceeds the physical total cannot spill past the top.
    private struct Bounds {
        var app: [Double] = []
        var wired: [Double] = []
        var compressed: [Double] = []
        var cached: [Double] = []
        var total: [Double] = []
    }

    private var bounds: Bounds {
        let n = count
        guard n > 0 else { return Bounds() }

        func clamp(_ value: Double) -> Double { min(100, max(0, value)) }

        let appValues = Array(app.suffix(n))
        let wiredValues = Array(wired.suffix(n))
        let compressedValues = Array(compressed.suffix(n))
        let cachedValues = Array(cached.suffix(n))
        let freeValues = Array(free.suffix(n))

        var result = Bounds()
        for index in 0..<n {
            let appTop = clamp(appValues[index])
            let wiredTop = clamp(appTop + wiredValues[index])
            let compressedTop = clamp(wiredTop + compressedValues[index])
            let cachedTop = clamp(compressedTop + cachedValues[index])
            let totalTop = clamp(cachedTop + freeValues[index])
            result.app.append(appTop)
            result.wired.append(wiredTop)
            result.compressed.append(compressedTop)
            result.cached.append(cachedTop)
            result.total.append(totalTop)
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let data = bounds
            let n = data.app.count
            let stepX = n > 1 ? size.width / CGFloat(n - 1) : size.width

            Canvas { context, canvasSize in
                guard n > 1 else { return }

                // Horizontal grid at 25/50/75 %. Canvas y grows downward.
                for fraction in [0.25, 0.5, 0.75] {
                    var grid = Path()
                    let y = canvasSize.height * (1 - fraction)
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    context.stroke(grid,
                                   with: .color(.secondary.opacity(0.12)),
                                   lineWidth: 0.5)
                }

                // 0 % -> bottom (height), 100 % -> top (0).
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

                let baseline = Array(repeating: 0.0, count: n)

                // Free capacity on top. `freeColor` is already translucent.
                context.fill(band(lower: data.cached, upper: data.total),
                             with: .color(freeColor))

                // Used bands, bottom to top.
                context.fill(band(lower: data.compressed, upper: data.cached),
                             with: .color(cachedColor.opacity(0.75)))
                context.fill(band(lower: data.wired, upper: data.compressed),
                             with: .color(compressedColor.opacity(0.75)))
                context.fill(band(lower: data.app, upper: data.wired),
                             with: .color(wiredColor.opacity(0.75)))
                context.fill(band(lower: baseline, upper: data.app),
                             with: .color(appColor.opacity(0.8)))

                // Thin separators matching each band colour.
                let lineStyle = StrokeStyle(lineWidth: 0.8,
                                            lineCap: .round,
                                            lineJoin: .round)
                context.stroke(topLine(data.app), with: .color(appColor),
                               style: lineStyle)
                context.stroke(topLine(data.wired), with: .color(wiredColor),
                               style: lineStyle)
                context.stroke(topLine(data.compressed),
                               with: .color(compressedColor), style: lineStyle)
                context.stroke(topLine(data.cached), with: .color(cachedColor),
                               style: lineStyle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memory composition history")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let n = count
        guard n > 0,
              let appValue = app.suffix(n).last,
              let wiredValue = wired.suffix(n).last,
              let compressedValue = compressed.suffix(n).last,
              let cachedValue = cached.suffix(n).last,
              let freeValue = free.suffix(n).last else {
            return "Collecting"
        }
        return String(format: "App %.1f percent, wired %.1f percent, compressed %.1f percent, cached %.1f percent, free %.1f percent",
                      appValue, wiredValue, compressedValue, cachedValue, freeValue)
    }
}
