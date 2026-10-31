import SwiftUI

/// Units for the traffic graph. `bits` consumes byte-rate histories and
/// `packets` consumes packet-rate histories; only the chart changes.
enum TrafficGraphMode: String, CaseIterable, Identifiable, Equatable {
    case bits
    case packets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bits: return "Bits"
        case .packets: return "Packets"
        }
    }

    /// Formats a value in the mode's stored unit (bytes/s for bits,
    /// packets/s for packets).
    func format(_ value: Double) -> String {
        switch self {
        case .bits: return KBFormat.bitRate(value)
        case .packets: return KBFormat.packetsRate(value)
        }
    }
}

/// Mirrored traffic chart: download grows above the center line and upload
/// below it, both on a shared, rounded scale, with grid and level labels.
struct TrafficChart: View {
    let download: [Double]
    let upload: [Double]
    let focus: NetworkingFocus?
    var sampleInterval: TimeInterval = 1
    /// Timestamps of each sample, parallel to `download`/`upload`. When present
    /// the X axis is laid out in real time, so history can survive an interval
    /// change without lying about the time span.
    var sampleDates: [Date] = []
    var mode: TrafficGraphMode = .bits
    var downloadTint: Color = KBTheme.downloadTint
    var uploadTint: Color = KBTheme.uploadTint

    @Environment(\.colorScheme) private var colorScheme

    private static let window = 60
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
        .accessibilityLabel("Traffic history, \(mode.title.lowercased())")
        .accessibilityValue(accessibilityValue)
    }

    /// Time covered by the retained samples. Falls back to the nominal window
    /// when the samples do not carry timestamps yet.
    private var span: TimeInterval {
        if sampleDates.count >= 2, let first = sampleDates.first, let last = sampleDates.last {
            return max(last.timeIntervalSince(first), max(sampleInterval, 0.1))
        }
        return max(sampleInterval, 0.1) * Double(Self.window)
    }

    private var accessibilityValue: String {
        let peak = max(max(download.max() ?? 0, upload.max() ?? 0), 0)
        let windowText = KBFormat.shortDuration(span)
        return "Peak \(mode.format(peak)) over the last \(windowText). " +
            "Download \(mode.format(download.last ?? 0)), " +
            "upload \(mode.format(upload.last ?? 0))"
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
        let peak = max(rx.max() ?? 0, tx.max() ?? 0)
        let scale = mode == .bits ? 8.0 : 1.0
        let ceilingValue = peak > 0
            ? Self.niceCeiling(peak * scale) / scale
            : (mode == .bits ? 125.0 : 10.0)

        drawGrid(context: &context, plot: plot, midY: midY, half: half)
        drawSeries(values: rx, dates: sampleDates, ceiling: ceilingValue, plot: plot,
                   midY: midY, half: half, tint: downloadTint, upward: true,
                   opacity: focus == .upload ? 0.25 : 1, context: &context)
        drawSeries(values: tx, dates: sampleDates, ceiling: ceilingValue, plot: plot,
                   midY: midY, half: half, tint: uploadTint, upward: false,
                   opacity: focus == .download ? 0.25 : 1, context: &context)
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
        let topColor = downloadTint.opacity(0.85)
        let bottomColor = uploadTint.opacity(0.85)
        let zeroColor = Color.secondary.opacity(colorScheme == .dark ? 0.75 : 0.65)
        let entries: [(Double, Color)] = [
            (1, topColor), (0.5, topColor), (0, zeroColor),
            (-0.5, bottomColor), (-1, bottomColor)
        ]

        for (fraction, color) in entries {
            let y = midY - CGFloat(fraction) * half
            let value = ceiling * abs(fraction)
            let text = context.resolve(
                Text(mode.format(value))
                    .font(.system(size: 8, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(color)
            )
            context.draw(text, at: CGPoint(x: Self.gutter - 5, y: y), anchor: .trailing)
        }
    }

    private func drawTimeAxis(context: inout GraphicsContext, plot: CGRect) {
        let window = span
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

    // MARK: - Series

    private func drawSeries(values: [Double], dates: [Date], ceiling: Double, plot: CGRect,
                            midY: CGFloat, half: CGFloat, tint: Color,
                            upward: Bool, opacity: Double,
                            context: inout GraphicsContext) {
        guard let maxValue = values.max(), maxValue > 0 else { return }

        let usable = max(plot.width - 2 * Self.seriesInset, 0)
        let step = usable / CGFloat(Self.window - 1)
        let startX = plot.minX + Self.seriesInset
        // Position samples by their timestamp when available so a cadence
        // change keeps the retained history honest on the time axis.
        let useTime = dates.count == values.count && dates.count >= 2
        let lastDate = dates.last
        let window = max(span, 0.1)

        var points: [CGPoint] = []
        points.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            let normalized = min(max(value / ceiling, 0), 1)
            let offset = CGFloat(normalized) * half
            let x: CGFloat
            if useTime, let lastDate {
                let age = lastDate.timeIntervalSince(dates[index])
                x = plot.minX + Self.seriesInset + CGFloat(age / window) * usable
            } else {
                x = startX + CGFloat(values.count - 1 - index) * step
            }
            points.append(CGPoint(
                x: x,
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
