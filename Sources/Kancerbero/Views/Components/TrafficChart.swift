import SwiftUI

/// Mirrored traffic chart: download grows above the center line and upload
/// below it, both on a shared, rounded scale, with grid and level labels.
struct TrafficChart: View {
    let download: [Double]
    let upload: [Double]
    let focus: NetworkingFocus?
    var sampleInterval: TimeInterval = 1
    var downloadTint: Color = KBTheme.downloadTint
    var uploadTint: Color = KBTheme.uploadTint

    @Environment(\.colorScheme) private var colorScheme

    private static let window = 60
    private static let axisHeight: CGFloat = 14
    private static let gutter: CGFloat = 50
    private static let rightInset: CGFloat = 1
    private static let verticalInset: CGFloat = 8
    private static let seriesInset: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Traffic history")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let peak = max(max(download.max() ?? 0, upload.max() ?? 0), 0)
        let span = KBFormat.shortDuration(max(sampleInterval, 0.1) * Double(Self.window))
        return "Peak \(KBFormat.bitRate(peak)) over the last \(span). " +
            "Download \(KBFormat.bitRate(download.last ?? 0)), " +
            "upload \(KBFormat.bitRate(upload.last ?? 0))"
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        guard width > 0, height > 0 else { return }

        let plotHeight = max(height - Self.axisHeight, 1)
        let plot = CGRect(
            x: Self.gutter,
            y: 0,
            width: max(width - Self.gutter - Self.rightInset, 1),
            height: plotHeight
        )
        let midY = plot.midY
        let half = max(plot.height / 2 - Self.verticalInset, 1)

        let rx = sanitized(download)
        let tx = sanitized(upload)
        let peakBytes = max(rx.max() ?? 0, tx.max() ?? 0)
        let ceilingBits = peakBytes > 0
            ? Self.niceCeiling(peakBytes * 8)
            : 1_000
        let ceilingBytes = ceilingBits / 8

        drawGrid(context: &context, plot: plot, midY: midY, half: half)
        drawSeries(values: rx, peakBytes: ceilingBytes, plot: plot, midY: midY,
                   half: half, tint: downloadTint, upward: true,
                   opacity: focus == .upload ? 0.25 : 1, context: &context)
        drawSeries(values: tx, peakBytes: ceilingBytes, plot: plot, midY: midY,
                   half: half, tint: uploadTint, upward: false,
                   opacity: focus == .download ? 0.25 : 1, context: &context)
        drawBaseline(context: &context, plot: plot, midY: midY)
        drawLevelLabels(context: &context, midY: midY, half: half,
                        ceilingBits: ceilingBits)
        drawTimeAxis(context: &context, plot: plot)
    }

    // MARK: - Grid and axes

    private func drawGrid(context: inout GraphicsContext, plot: CGRect,
                          midY: CGFloat, half: CGFloat) {
        let gridColor = Color.secondary.opacity(colorScheme == .dark ? 0.20 : 0.14)

        for fraction in [1.0, 0.5, -0.5, -1.0] {
            let y = midY - CGFloat(fraction) * half
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 1)
        }

        for fraction in [0.0, 0.5, 1.0] {
            let x = plot.minX + plot.width * CGFloat(fraction)
            var path = Path()
            path.move(to: CGPoint(x: x, y: plot.minY))
            path.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(
                path,
                with: .color(gridColor.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 3])
            )
        }
    }

    private func drawBaseline(context: inout GraphicsContext, plot: CGRect, midY: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: plot.minX, y: midY))
        path.addLine(to: CGPoint(x: plot.maxX, y: midY))
        context.stroke(
            path,
            with: .color(.secondary.opacity(colorScheme == .dark ? 0.38 : 0.28)),
            lineWidth: 1
        )
    }

    private func drawLevelLabels(context: inout GraphicsContext,
                                 midY: CGFloat, half: CGFloat, ceilingBits: Double) {
        let topColor = downloadTint.opacity(0.85)
        let bottomColor = uploadTint.opacity(0.85)
        let zeroColor = Color.secondary.opacity(colorScheme == .dark ? 0.75 : 0.65)
        let entries: [(Double, Color)] = [
            (1, topColor), (0.5, topColor), (0, zeroColor),
            (-0.5, bottomColor), (-1, bottomColor)
        ]

        for (fraction, color) in entries {
            let y = midY - CGFloat(fraction) * half
            let bits = ceilingBits * abs(fraction)
            let text = context.resolve(
                Text(KBFormat.bitRate(bits / 8))
                    .font(.system(size: 8, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(color)
            )
            context.draw(text, at: CGPoint(x: Self.gutter - 5, y: y), anchor: .trailing)
        }
    }

    private func drawTimeAxis(context: inout GraphicsContext, plot: CGRect) {
        let span = max(sampleInterval, 0.1) * Double(Self.window)
        let y = plot.maxY + Self.axisHeight / 2
        let color = Color.secondary.opacity(colorScheme == .dark ? 0.7 : 0.6)
        let entries: [(String, CGFloat, UnitPoint)] = [
            ("-" + KBFormat.shortDuration(span), plot.minX, .leading),
            ("-" + KBFormat.shortDuration(span / 2), plot.midX, .center),
            ("now", plot.maxX, .trailing)
        ]

        for (label, x, anchor) in entries {
            let text = context.resolve(
                Text(label)
                    .font(.system(size: 8))
                    .foregroundColor(color)
            )
            context.draw(text, at: CGPoint(x: x, y: y), anchor: anchor)
        }
    }

    // MARK: - Series

    private func drawSeries(values: [Double], peakBytes: Double, plot: CGRect,
                            midY: CGFloat, half: CGFloat, tint: Color,
                            upward: Bool, opacity: Double,
                            context: inout GraphicsContext) {
        guard let maxValue = values.max(), maxValue > 0 else { return }

        let usable = max(plot.width - 2 * Self.seriesInset, 0)
        let step = usable / CGFloat(Self.window - 1)
        let startX = plot.maxX - Self.seriesInset - CGFloat(values.count - 1) * step

        var points: [CGPoint] = []
        points.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            let normalized = min(max(value / peakBytes, 0), 1)
            let offset = CGFloat(normalized) * half
            points.append(CGPoint(
                x: startX + CGFloat(index) * step,
                y: upward ? midY - offset : midY + offset
            ))
        }

        guard let first = points.first, let last = points.last else { return }

        var area = Path()
        area.move(to: CGPoint(x: first.x, y: midY))
        for point in points { area.addLine(to: point) }
        area.addLine(to: CGPoint(x: last.x, y: midY))
        area.closeSubpath()

        let topAlpha = colorScheme == .dark ? 0.34 : 0.28
        let gradient = Gradient(colors: upward
            ? [tint.opacity(topAlpha), tint.opacity(0.02)]
            : [tint.opacity(0.02), tint.opacity(topAlpha)])

        context.opacity = opacity
        context.fill(
            area,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: plot.minY),
                endPoint: CGPoint(x: 0, y: plot.maxY)
            )
        )

        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() { line.addLine(to: point) }
        context.stroke(
            line,
            with: .color(tint),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        )

        if points.count == 1 {
            let dot = CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4)
            context.fill(Path(ellipseIn: dot), with: .color(tint))
        }

        context.opacity = 1
    }

    // MARK: - Helpers

    private func sanitized(_ values: [Double]) -> [Double] {
        Array(values.suffix(Self.window)).map { $0.isFinite ? max($0, 0) : 0 }
    }

    /// 1/2/5 × 10^n in bits, so labels stay stable as samples change.
    private static func niceCeiling(_ bits: Double) -> Double {
        guard bits.isFinite, bits > 0 else { return 1 }
        let exponent = floor(log10(bits))
        let magnitude = pow(10.0, exponent)
        let fraction = bits / magnitude
        let nice: Double
        if fraction <= 1.0001 {
            nice = 1
        } else if fraction <= 2 {
            nice = 2
        } else if fraction <= 5 {
            nice = 5
        } else {
            nice = 10
        }
        return nice * magnitude
    }
}
