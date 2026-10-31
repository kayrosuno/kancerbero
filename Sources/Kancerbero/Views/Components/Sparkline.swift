import SwiftUI

struct Sparkline: View {
    var values: [Double]
    var tint: Color
    /// Fixed denominator for the vertical scale. When `nil`, the line is
    /// normalised to the series peak (the historical behaviour); pass 100 for
    /// percentage series that should keep a fixed 0...100 scale.
    var scale: Double? = nil

    var body: some View {
        GeometryReader { geometry in
            let points = makePoints(in: geometry.size)
            ZStack {
                if points.count > 1 {
                    areaPath(points, in: geometry.size)
                        .fill(LinearGradient(
                            colors: [tint.opacity(0.32), tint.opacity(0.015)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    linePath(points)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.6,
                                                         lineCap: .round,
                                                         lineJoin: .round))
                } else {
                    Capsule()
                        .fill(tint.opacity(0.15))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: values)
    }

    private func makePoints(in size: CGSize) -> [CGPoint] {
        let data = Array(values.suffix(60))
        guard data.count > 1, size.width > 1, size.height > 1 else { return [] }
        let peak = max(scale ?? data.max() ?? 0, 1)
        let stepX = size.width / CGFloat(data.count - 1)
        return data.enumerated().map { index, value in
            let normalized = min(max(value / peak, 0), 1)
            return CGPoint(x: size.width - CGFloat(index) * stepX,
                           y: size.height - CGFloat(normalized) * size.height)
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func areaPath(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = linePath(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
