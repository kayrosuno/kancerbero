import SwiftUI

/// Mirrored bar history shared by the traffic and disk activity charts.
/// `top` bars grow above the centre line and `bottom` below it, packed from the
/// left in fixed 60-sample slots on a shared, rounded scale. Each bar is a
/// solid heat colour, so height and hue both show magnitude. Grid, level labels
/// and the time axis complete the chart.
struct MirroredBarChart: View {
    var top: [Double]
    var bottom: [Double]
    var format: (Double) -> String
    var topTint: Color
    var bottomTint: Color
    var topOpacity: Double = 1
    var bottomOpacity: Double = 1
    /// Multiplier that converts stored values into display units before
    /// rounding the ceiling (8 for bit rates, 1 for byte/packet rates).
    var labelScale: Double = 1
    var fallbackCeiling: Double = 1
    var sampleInterval: TimeInterval = 1
    var accessibilityLabel: String
    var accessibilityValue: String

    @Environment(\.colorScheme) private var colorScheme

    static let window = 60
    private static let axisHeight: CGFloat = 14
    private static let gutter: CGFloat = 54
    private static let rightInset: CGFloat = 1
    private static let verticalInset: CGFloat = 8
    private static let seriesInset: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    /// Nominal duration represented by the fixed 60-slot window.
    var nominalSpan: TimeInterval {
        max(sampleInterval, 0.1) * Double(Self.window)
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

        let topValues = sanitized(top)
        let bottomValues = sanitized(bottom)
        let peak = max(topValues.max() ?? 0, bottomValues.max() ?? 0)
        let scale = max(labelScale, 0.0001)
        let ceilingValue = peak > 0
            ? Self.niceCeiling(peak * scale) / scale
            : fallbackCeiling

        drawGrid(context: &context, plot: plot, midY: midY, half: half)
        drawBars(values: topValues, ceiling: ceilingValue, plot: plot,
                 midY: midY, half: half, upward: true,
                 opacity: topOpacity, context: &context)
        drawBars(values: bottomValues, ceiling: ceilingValue, plot: plot,
                 midY: midY, half: half, upward: false,
                 opacity: bottomOpacity, context: &context)
        drawBaseline(context: &context, plot: plot, midY: midY)
        drawLevelLabels(context: &context, midY: midY, half: half,
                        ceiling: ceilingValue)
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
                                 midY: CGFloat, half: CGFloat, ceiling: Double) {
        let topColor = topTint.opacity(0.85)
        let bottomColor = bottomTint.opacity(0.85)
        let zeroColor = Color.secondary.opacity(colorScheme == .dark ? 0.75 : 0.65)
        let entries: [(Double, Color)] = [
            (1, topColor), (0.5, topColor), (0, zeroColor),
            (-0.5, bottomColor), (-1, bottomColor)
        ]

        for (fraction, color) in entries {
            let y = midY - CGFloat(fraction) * half
            let value = ceiling * abs(fraction)
            let text = context.resolve(
                Text(format(value))
                    .font(.system(size: 8, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(color)
            )
            context.draw(text, at: CGPoint(x: Self.gutter - 5, y: y), anchor: .trailing)
        }
    }

    private func drawTimeAxis(context: inout GraphicsContext, plot: CGRect) {
        let window = nominalSpan
        let y = plot.maxY + Self.axisHeight / 2
        let color = Color.secondary.opacity(colorScheme == .dark ? 0.7 : 0.6)
        let entries: [(String, CGFloat, UnitPoint)] = [
            ("now", plot.minX, .leading),
            ("-" + KBFormat.shortDuration(window / 2), plot.midX, .center),
            ("-" + KBFormat.shortDuration(window), plot.maxX, .trailing)
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

    // MARK: - Bars

    /// Mirrored equalizer bars. Each bar is anchored on the centre line and
    /// grows toward its series' edge, solid-filled with the shared load-heat
    /// ramp so colour and height both encode magnitude.
    private func drawBars(values rawValues: [Double], ceiling: Double,
                          plot: CGRect, midY: CGFloat, half: CGFloat,
                          upward: Bool, opacity: Double,
                          context: inout GraphicsContext) {
        let values = sanitized(rawValues)
        guard !values.isEmpty, ceiling > 0 else { return }

        // Fixed 60 slots: the newest sample sits in the first slot at the
        // left edge and older samples fill consecutive slots, so a short
        // history stays packed instead of stretching across the window.
        let startX = plot.minX + Self.seriesInset
        let usable = max(plot.width - 2 * Self.seriesInset, 1)
        let slot = usable / CGFloat(Self.window)
        let barWidth = min(max(slot * 0.62, 1.5), 12)

        context.opacity = opacity

        var newestBar: CGRect?
        var newestHeight: CGFloat = 0
        for (index, value) in values.enumerated() {
            let normalized = min(max(value / ceiling, 0), 1)
            guard normalized > 0 else { continue }
            let height = max(1, CGFloat(normalized) * half)
            let center = startX + CGFloat(values.count - 1 - index) * slot + slot / 2
            let x = min(max(center - barWidth / 2, plot.minX),
                        plot.maxX - barWidth)
            let radius = min(1, barWidth / 2, height / 2)
            let rect = CGRect(x: x, y: upward ? midY - height : midY,
                              width: barWidth, height: height)
            var bar = Path()
            bar.addRoundedRect(in: rect,
                               cornerSize: CGSize(width: radius, height: radius))
            context.fill(bar, with: .color(KBTheme.loadHeat(normalized * 100)))
            if index == values.count - 1 {
                newestBar = rect
                newestHeight = height
            }
        }

        // Bright cap on the newest sample, like the per-core bar wall.
        if let newestBar, newestHeight >= 2 {
            let cap = CGRect(x: newestBar.minX,
                             y: upward ? newestBar.minY - 1 : newestBar.maxY,
                             width: newestBar.width, height: 1)
            context.fill(Path(cap), with: .color(.primary.opacity(0.85)))
        }

        context.opacity = 1
    }

    // MARK: - Helpers

    private func sanitized(_ values: [Double]) -> [Double] {
        Array(values.suffix(Self.window)).map { $0.isFinite ? max($0, 0) : 0 }
    }

    /// 1/2/5 × 10^n in the mode's display units, so labels stay stable as
    /// samples change.
    private static func niceCeiling(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        let exponent = floor(log10(value))
        let magnitude = pow(10.0, exponent)
        let fraction = value / magnitude
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
