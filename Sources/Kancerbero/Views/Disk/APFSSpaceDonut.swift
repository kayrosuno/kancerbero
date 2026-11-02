import SwiftUI
import KancerberoCore

/// Donut chart for the APFS space of the selected disk, container or volume.
struct APFSSpaceDonut: View {
    let context: APFSSpaceContext
    var diameter: CGFloat = 172
    var ringWidth: CGFloat = 26

    @Environment(\.byteUnitSystem) private var byteUnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(context.title)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let caption = context.caption {
                    Text(caption)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            ZStack {
                Canvas { graphics, size in
                    draw(&graphics, size: size)
                }
                center
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("APFS space")
            .accessibilityValue(accessibilityValue)

            if let note = context.note {
                Text(note)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            legend
        }
    }

    // MARK: - Drawing

    private func draw(_ graphics: inout GraphicsContext, size: CGSize) {
        let centerPoint = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = min(size.width, size.height) / 2
        let inner = max(0, outer - ringWidth)
        guard outer > 0, inner < outer else { return }

        let drawn = context.segments.filter { $0.fraction > 0 }
        guard !drawn.isEmpty else { return }

        let gap = min(0.035, 1.2 / max(outer, 1))
        var angle = -Double.pi / 2

        for segment in drawn {
            let sweep = 2 * Double.pi * min(max(segment.fraction, 0), 1)
            let gapAngle = drawn.count > 1 ? min(gap, sweep * 0.35) : 0
            let from = angle + gapAngle / 2
            let to = angle + sweep - gapAngle / 2
            angle += sweep
            guard to > from else { continue }

            var path = Path()
            path.addArc(center: centerPoint, radius: outer,
                        startAngle: .radians(from), endAngle: .radians(to),
                        clockwise: false)
            path.addArc(center: centerPoint, radius: inner,
                        startAngle: .radians(to), endAngle: .radians(from),
                        clockwise: true)
            path.closeSubpath()

            let highlighted = context.highlightedItemID == segment.itemID
            let dimmed = context.highlightedItemID != nil && !highlighted
            graphics.fill(path,
                          with: .color(color(for: segment).opacity(dimmed ? 0.34 : 1)))
            graphics.stroke(path, with: .color(.black.opacity(0.10)), lineWidth: 0.5)
            if highlighted {
                graphics.stroke(path, with: .color(.white.opacity(0.9)),
                                lineWidth: 1.8)
            }
            if segment.role == .unknown {
                graphics.stroke(path,
                                with: .color(.secondary.opacity(0.35)),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }

    private var center: some View {
        VStack(spacing: 1) {
            Text(centerValue)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(centerSubtitle)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .frame(width: max(0, diameter - ringWidth * 2 - 16))
        .allowsHitTesting(false)
    }

    private var centerValue: String {
        guard context.availability == .ready else { return "—" }
        if containerCount > 1 { return "\(containerCount)" }
        if let percent = highlightedRow?.percent {
            return KBFormat.percent(percent)
        }
        if let used = context.usedBytes, context.totalBytes > 0 {
            return KBFormat.percent(Double(used) / Double(context.totalBytes))
        }
        return KBFormat.bytes(context.totalBytes, units: byteUnitSystem)
    }

    private var centerSubtitle: String {
        guard context.availability == .ready else {
            return context.availability == .unmounted
                ? "Free space unknown"
                : "Capacity unavailable"
        }
        if containerCount > 1 {
            return "containers · \(KBFormat.bytes(context.totalBytes, units: byteUnitSystem))"
        }
        if highlightedRow != nil {
            return "of \(KBFormat.bytes(context.totalBytes, units: byteUnitSystem))"
        }
        if let used = context.usedBytes {
            return "\(KBFormat.bytes(used, units: byteUnitSystem)) used"
        }
        return KBFormat.bytes(context.totalBytes, units: byteUnitSystem)
    }

    private var containerCount: Int {
        context.legend.filter { $0.role == .container }.count
    }

    private var highlightedRow: APFSSpaceLegendRow? {
        guard let id = context.highlightedItemID else { return nil }
        return context.legend.first { $0.itemID == id }
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(spacing: 3) {
            ForEach(context.legend) { row in
                let highlighted = row.itemID != nil
                    && row.itemID == context.highlightedItemID
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: row))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.label)
                            .font(.system(size: 10,
                                          weight: highlighted ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let detail = row.detail {
                            Text(detail)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(valueText(row))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                        if let percent = row.percent {
                            Text(KBFormat.percent(percent))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background {
                    if highlighted {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.quaternary.opacity(0.35))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(highlighted ? "Selected" : "")
            }
        }
    }

    private var colorMap: [String: Color] {
        var map: [String: Color] = [:]
        var index = 0
        for row in context.legend
        where row.role == .volume || row.role == .container {
            if map[row.id] == nil {
                map[row.id] = KBTheme.diskChartPalette[
                    index % KBTheme.diskChartPalette.count]
                index += 1
            }
        }
        return map
    }

    private func color(for segment: APFSSpaceSegment) -> Color {
        switch segment.role {
        case .free: return KBTheme.diskChartFree
        case .residual: return KBTheme.diskChartResidual
        case .unknown: return KBTheme.diskChartUnknown
        case .volume, .container:
            return colorMap[segment.id] ?? KBTheme.diskChartPalette[0]
        }
    }

    private func color(for row: APFSSpaceLegendRow) -> Color {
        switch row.role {
        case .free: return KBTheme.diskChartFree
        case .residual: return KBTheme.diskChartResidual
        case .unknown: return KBTheme.diskChartUnknown
        case .volume, .container:
            return colorMap[row.id] ?? KBTheme.diskChartPalette[0]
        }
    }

    private func valueText(_ row: APFSSpaceLegendRow) -> String {
        switch row.role {
        case .container:
            let used = row.bytes.map { KBFormat.bytes($0, units: byteUnitSystem) } ?? "—"
            let capacity = row.capacityBytes.map { KBFormat.bytes($0, units: byteUnitSystem) } ?? "—"
            return "\(used) / \(capacity)"
        case .volume, .residual, .free:
            return row.bytes.map { KBFormat.bytes($0, units: byteUnitSystem) } ?? "—"
        case .unknown:
            return "—"
        }
    }

    private var accessibilityValue: String {
        context.legend.map { row in
            let value = row.bytes.map { KBFormat.bytes($0, units: byteUnitSystem) } ?? "unknown"
            return "\(row.label): \(value)"
        }
        .joined(separator: "; ")
    }
}
