import SwiftUI

/// Mirrored traffic chart: download grows above the center line and upload
/// below it, both on a shared scale so their magnitudes are comparable.
struct TrafficChart: View {
    let download: [Double]
    let upload: [Double]
    let focus: NetworkingFocus?
    var downloadTint: Color = KBTheme.downloadTint
    var uploadTint: Color = KBTheme.uploadTint

    @Environment(\.colorScheme) private var colorScheme

    private static let window = 60
    private static let inset: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Traffic history")
        .accessibilityValue(
            "Download \(KBFormat.bitRate(download.last ?? 0)), " +
            "upload \(KBFormat.bitRate(upload.last ?? 0))"
        )
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        guard width > 0, height > 0 else { return }

        let midY = height / 2
        let half = max(height / 2 - Self.inset, 0)

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: midY))
        baseline.addLine(to: CGPoint(x: width, y: midY))
        context.stroke(
            baseline,
            with: .color(.secondary.opacity(colorScheme == .dark ? 0.35 : 0.25)),
            lineWidth: 1
        )

        let rx = sanitized(download)
        let tx = sanitized(upload)
        let peak = max(max(rx.max() ?? 0, tx.max() ?? 0), 1)

        let rxOpacity: Double = focus == .upload ? 0.25 : 1
        let txOpacity: Double = focus == .download ? 0.25 : 1

        drawSeries(values: rx, peak: peak, midY: midY, half: half,
                   width: width, tint: downloadTint, upward: true,
                   opacity: rxOpacity, context: &context, size: size)
        drawSeries(values: tx, peak: peak, midY: midY, half: half,
                   width: width, tint: uploadTint, upward: false,
                   opacity: txOpacity, context: &context, size: size)
    }

    private func sanitized(_ values: [Double]) -> [Double] {
        Array(values.suffix(Self.window)).map { $0.isFinite ? max($0, 0) : 0 }
    }

    private func drawSeries(values: [Double], peak: Double, midY: CGFloat,
                            half: CGFloat, width: CGFloat, tint: Color,
                            upward: Bool, opacity: Double,
                            context: inout GraphicsContext, size: CGSize) {
        guard let maxValue = values.max(), maxValue > 0 else { return }

        let usableWidth = max(width - 2 * Self.inset, 0)
        let step = usableWidth / CGFloat(Self.window - 1)
        let startX = width - Self.inset - CGFloat(values.count - 1) * step

        var points: [CGPoint] = []
        points.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            let normalized = min(max(value / peak, 0), 1)
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
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
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
            let dot = CGRect(x: first.x - 1.5, y: first.y - 1.5, width: 3, height: 3)
            context.fill(Path(ellipseIn: dot), with: .color(tint))
        }

        context.opacity = 1
    }
}
