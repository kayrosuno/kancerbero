import SwiftUI

/// Mirrored bar history shared by the traffic and disk activity charts.
/// `top` bars grow above the centre line and `bottom` below it, packed from the
/// left in fixed 120-sample slots on a shared scale that tracks the largest
/// visible sample. Each bar is a solid heat colour, so height and hue both show
/// magnitude. Grid, level labels and the time axis complete the chart.
struct MirroredBarChart: View {
    var top: [Double]
    var bottom: [Double]
    var format: (Double) -> String
    var topTint: Color
    var bottomTint: Color
    var topLabel: String
    var bottomLabel: String
    var topOpacity: Double = 1
    var bottomOpacity: Double = 1
    var fallbackCeiling: Double = 1
    var sampleInterval: TimeInterval = 1
    var accessibilityLabel: String
    var accessibilityValue: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var hover: HoverSlot?

    static let window = 120
    private static let axisHeight: CGFloat = 14
    private static let gutter: CGFloat = 54
    private static let rightInset: CGFloat = 1
    private static let verticalInset: CGFloat = 8
    private static let seriesInset: CGFloat = 2
    private static let tooltipWidth: CGFloat = 150

    private struct HoverSlot: Equatable {
        var index: Int
        var lineX: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    draw(context: &context, size: size, hover: hover)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                if let hover {
                    tooltip(hover)
                        .offset(x: tooltipOriginX(for: hover, width: proxy.size.width),
                                y: 4)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    let next = hoverSlot(at: location, size: proxy.size)
                    if next != hover { hover = next }
                case .ended:
                    hover = nil
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    /// Nominal duration represented by the fixed sample window.
    var nominalSpan: TimeInterval {
        max(sampleInterval, 0.1) * Double(Self.window)
    }

    private func plotRect(in size: CGSize) -> CGRect {
        let plotHeight = max(size.height - Self.axisHeight, 1)
        return CGRect(
            x: Self.gutter,
            y: 0,
            width: max(size.width - Self.gutter - Self.rightInset, 1),
            height: plotHeight
        )
    }

    private func draw(context: inout GraphicsContext, size: CGSize,
                      hover: HoverSlot?) {
        let width = size.width
        let height = size.height
        guard width > 0, height > 0 else { return }

        let plot = plotRect(in: size)
        let midY = plot.midY
        let half = max(plot.height / 2 - Self.verticalInset, 1)

        let topValues = sanitized(top)
        let bottomValues = sanitized(bottom)
        let peak = max(topValues.max() ?? 0, bottomValues.max() ?? 0)
        // Scale to the largest sample currently on screen, so the tallest
        // visible bar always reaches the top of the plot.
        let ceilingValue = peak > 0 ? peak : fallbackCeiling

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
        drawHoverMarker(context: &context, plot: plot, hover: hover)
    }

    // MARK: - Hover

    private func hoverSlot(at point: CGPoint, size: CGSize) -> HoverSlot? {
        let plot = plotRect(in: size)
        guard plot.contains(point) else { return nil }

        let count = max(sanitized(top).count, sanitized(bottom).count)
        guard count > 0 else { return nil }

        let startX = plot.minX + Self.seriesInset
        let usable = max(plot.width - 2 * Self.seriesInset, 1)
        let slot = usable / CGFloat(Self.window)
        let raw = (point.x - startX) / slot
        guard raw >= 0 else { return nil }

        let index = Int(raw)
        guard index < count else { return nil }

        return HoverSlot(index: index,
                         lineX: startX + (CGFloat(index) + 0.5) * slot)
    }

    /// The newest sample sits in the leftmost slot, so `slot` counts back
    /// from the end of the chronological history.
    private func sample(at slot: Int, in values: [Double]) -> Double? {
        let position = values.count - 1 - slot
        guard values.indices.contains(position) else { return nil }
        return values[position]
    }

    private func drawHoverMarker(context: inout GraphicsContext, plot: CGRect,
                                 hover: HoverSlot?) {
        guard let hover else { return }
        var path = Path()
        path.move(to: CGPoint(x: hover.lineX, y: plot.minY))
        path.addLine(to: CGPoint(x: hover.lineX, y: plot.maxY))
        context.stroke(
            path,
            with: .color(.primary.opacity(colorScheme == .dark ? 0.5 : 0.35)),
            lineWidth: 1
        )
    }

    private func tooltipOriginX(for hover: HoverSlot, width: CGFloat) -> CGFloat {
        let half = Self.tooltipWidth / 2
        return min(max(hover.lineX - half, 2),
                   max(width - Self.tooltipWidth - 2, 2))
    }

    private func tooltip(_ hover: HoverSlot) -> some View {
        let topValues = sanitized(top)
        let bottomValues = sanitized(bottom)
        let topValue = sample(at: hover.index, in: topValues).map(format) ?? "—"
        let bottomValue = sample(at: hover.index, in: bottomValues).map(format) ?? "—"
        let elapsed = Double(hover.index) * max(sampleInterval, 0.1)
        let time = hover.index == 0
            ? "now"
            : "-" + KBFormat.shortDuration(elapsed)

        return VStack(alignment: .leading, spacing: 2) {
            Text(time)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)

            tooltipRow(label: topLabel, value: topValue, tint: topTint)
            tooltipRow(label: bottomLabel, value: bottomValue, tint: bottomTint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(width: Self.tooltipWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.55)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tooltipRow(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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

        // Fixed window slots: the newest sample sits in the first slot at the
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
}
