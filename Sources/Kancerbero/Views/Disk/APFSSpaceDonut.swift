import SwiftUI
import KancerberoCore

/// Donut chart for the APFS space of the selected disk, container or volume.
/// Large slices are labelled inside the ring; small ones get callout labels
/// with leader lines. Hovering shows a tooltip and clicking a container (or
/// volume) slice selects it.
struct APFSSpaceDonut: View {
    let context: APFSSpaceContext
    /// Maximum ring diameter; the actual ring shrinks in narrow columns.
    var diameter: CGFloat = 168
    var ringWidth: CGFloat = 26
    var highlightOverride: String? = nil
    var onSelect: ((APFSSpaceSegment) -> Void)? = nil

    @Environment(\.byteUnitSystem) private var byteUnitSystem
    @State private var hoveredID: String?
    @State private var hoverPoint: CGPoint?

    private static let canvasHeight: CGFloat = 240

    private struct SliceLayout: Identifiable {
        let segment: APFSSpaceSegment
        let startAngle: Double
        let endAngle: Double
        let midAngle: Double
        let anchor: CGPoint
        let inside: Bool
        let insideText: String
        var id: String { segment.id }
    }

    private struct Callout: Identifiable {
        let slice: SliceLayout
        let text: String
        let textPoint: CGPoint
        let rightSide: Bool
        let elbowX: CGFloat
        var id: String { slice.id }
    }

    private struct DonutLayout {
        let center: CGPoint
        let outer: CGFloat
        let inner: CGFloat
        let slices: [SliceLayout]
        let callouts: [Callout]
    }

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

            GeometryReader { proxy in
                let size = proxy.size
                let layout = makeLayout(in: size)

                ZStack {
                    Canvas { graphics, canvasSize in
                        draw(&graphics, size: canvasSize, layout: layout)
                    }

                    center

                    if let hovered = hoveredSegment(in: layout),
                       let point = hoverPoint {
                        tooltip(hovered)
                            .position(
                                x: min(max(point.x, 88), max(88, size.width - 88)),
                                y: min(max(point.y - 34, 26), size.height - 26)
                            )
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let location):
                        hoverPoint = location
                        let next = slice(at: location, layout: layout)?.id
                        if next != hoveredID { hoveredID = next }
                    case .ended:
                        hoveredID = nil
                        hoverPoint = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        guard let slice = slice(at: value.location, layout: layout),
                              slice.segment.itemID != nil,
                              slice.segment.role == .container
                                || slice.segment.role == .volume else { return }
                        onSelect?(slice.segment)
                    }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("APFS space")
                .accessibilityValue(accessibilityValue)
                .accessibilityHint("Use the legend to select a container")
            }
            .frame(height: Self.canvasHeight)

            if let note = context.note {
                Text(note)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            legend
        }
    }

    // MARK: - Highlight

    private var effectiveHighlight: String? {
        if let override = highlightOverride,
           context.segments.contains(where: {
               $0.role == .container && $0.itemID == override
           }) {
            return override
        }
        return context.highlightedItemID
    }

    private var focusRow: APFSSpaceLegendRow? {
        if let hoveredID,
           let row = context.legend.first(where: { $0.id == hoveredID }) {
            return row
        }
        if let highlight = effectiveHighlight,
           let row = context.legend.first(where: { $0.itemID == highlight }) {
            return row
        }
        return nil
    }

    private var containerCount: Int {
        context.legend.filter { $0.role == .container }.count
    }

    private var highlightedRow: APFSSpaceLegendRow? {
        guard let id = context.highlightedItemID else { return nil }
        return context.legend.first { $0.itemID == id }
    }

    // MARK: - Layout

    private func makeLayout(in size: CGSize) -> DonutLayout {
        let sideLabelWidth = min(110, max(52, size.width * 0.20))
        let ringDiameter = min(diameter,
                               max(90, size.width - 2 * sideLabelWidth - 12))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = ringDiameter / 2
        let inner = max(0, outer - ringWidth)
        let gap = min(0.035, 1.2 / max(outer, 1))
        let drawn = context.segments.filter { $0.fraction > 0 }

        var slices: [SliceLayout] = []
        var angle = -Double.pi / 2

        for segment in drawn {
            let sweep = 2 * Double.pi * min(max(segment.fraction, 0), 1)
            let gapAngle = drawn.count > 1 ? min(gap, sweep * 0.35) : 0
            let from = angle + gapAngle / 2
            let to = angle + sweep - gapAngle / 2
            angle += sweep
            guard to > from else { continue }

            let mid = (from + to) / 2
            let midRadius = (inner + outer) / 2
            let chord = 2 * midRadius * CGFloat(sin(min(sweep, .pi) / 2))
            let name = shortName(segment)
            let insideText = truncated(name, maxWidth: max(0, chord - 8))
            let inside = chord >= 52 && !insideText.isEmpty
            let anchor = CGPoint(
                x: center.x + CGFloat(cos(mid)) * outer,
                y: center.y + CGFloat(sin(mid)) * outer)

            slices.append(SliceLayout(
                segment: segment,
                startAngle: from,
                endAngle: to,
                midAngle: mid,
                anchor: anchor,
                inside: inside,
                insideText: inside ? insideText : name))
        }

        let sideWidth = max(0, (size.width - ringDiameter) / 2)
        let callouts = makeCallouts(slices: slices, size: size, center: center,
                                    outer: outer, sideWidth: sideWidth)
        return DonutLayout(center: center, outer: outer, inner: inner,
                           slices: slices, callouts: callouts)
    }

    private struct CalloutCandidate {
        let slice: SliceLayout
        let rightSide: Bool
        let idealY: CGFloat
        let text: String
    }

    private func makeCallouts(slices: [SliceLayout], size: CGSize,
                              center: CGPoint, outer: CGFloat,
                              sideWidth: CGFloat) -> [Callout] {
        let maxTextWidth = max(20, min(160, sideWidth - 26))
        let candidates = slices.filter { !$0.inside }.compactMap { slice -> CalloutCandidate? in
            let text = truncated(shortName(slice.segment), maxWidth: maxTextWidth)
            guard !text.isEmpty else { return nil }
            return CalloutCandidate(
                slice: slice,
                rightSide: cos(slice.midAngle) >= 0,
                idealY: center.y + CGFloat(sin(slice.midAngle)) * (outer + 8),
                text: text)
        }

        var result: [Callout] = []
        let minY: CGFloat = 10
        let maxY = size.height - 10

        for right in [false, true] {
            var side = candidates
                .filter { $0.rightSide == right }
                .sorted { $0.idealY < $1.idealY }

            while !side.isEmpty {
                guard let ys = distributedYs(side.map(\.idealY),
                                             minY: minY, maxY: maxY,
                                             spacing: 12) else {
                    let drop = side.indices.min {
                        side[$0].slice.segment.fraction
                            < side[$1].slice.segment.fraction
                    }!
                    side.remove(at: drop)
                    continue
                }

                let elbowX = center.x + (right ? 1 : -1) * (outer + 10)
                let textX = elbowX + (right ? 4 : -4)
                for (candidate, y) in zip(side, ys) {
                    result.append(Callout(
                        slice: candidate.slice,
                        text: candidate.text,
                        textPoint: CGPoint(x: textX, y: y),
                        rightSide: right,
                        elbowX: elbowX))
                }
                break
            }
        }
        return result
    }

    private func distributedYs(_ ideal: [CGFloat], minY: CGFloat,
                               maxY: CGFloat, spacing: CGFloat) -> [CGFloat]? {
        guard !ideal.isEmpty else { return [] }
        var ys = ideal.map { min(max($0, minY), maxY) }
        for index in 1..<ys.count {
            ys[index] = max(ys[index], ys[index - 1] + spacing)
        }
        if let last = ys.last, last > maxY {
            ys[ys.count - 1] = maxY
            if ys.count > 1 {
                for index in stride(from: ys.count - 2, through: 0, by: -1) {
                    ys[index] = min(ys[index], ys[index + 1] - spacing)
                }
            }
        }
        return (ys.first ?? minY) >= minY ? ys : nil
    }

    // MARK: - Drawing

    private func draw(_ graphics: inout GraphicsContext, size: CGSize,
                      layout: DonutLayout) {
        guard layout.outer > 0, layout.inner < layout.outer else { return }

        for slice in layout.slices {
            var path = Path()
            path.addArc(center: layout.center, radius: layout.outer,
                        startAngle: .radians(slice.startAngle),
                        endAngle: .radians(slice.endAngle),
                        clockwise: false)
            path.addArc(center: layout.center, radius: layout.inner,
                        startAngle: .radians(slice.endAngle),
                        endAngle: .radians(slice.startAngle),
                        clockwise: true)
            path.closeSubpath()

            let hovered = slice.id == hoveredID
            let selected = slice.segment.itemID != nil
                && slice.segment.itemID == effectiveHighlight
            let hasFocus = hoveredID != nil || effectiveHighlight != nil
            let dimmed = hasFocus && !hovered && !selected

            graphics.fill(path, with: .color(color(for: slice.segment)
                .opacity(dimmed ? 0.34 : 1)))
            graphics.stroke(path, with: .color(.black.opacity(0.10)),
                            lineWidth: 0.5)
            if hovered || selected {
                graphics.stroke(path, with: .color(.white.opacity(0.9)),
                                lineWidth: 1.8)
            }
            if slice.segment.role == .unknown {
                graphics.stroke(path,
                                with: .color(.secondary.opacity(0.35)),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            if slice.inside {
                let radius = (layout.inner + layout.outer) / 2
                let point = CGPoint(
                    x: layout.center.x + CGFloat(cos(slice.midAngle)) * radius,
                    y: layout.center.y + CGFloat(sin(slice.midAngle)) * radius)
                let text = graphics.resolve(
                    Text(slice.insideText)
                        .font(.system(size: 8,
                                      weight: hovered || selected ? .semibold : .medium))
                        .foregroundColor(.white))
                graphics.draw(text, at: point, anchor: .center)
            }
        }

        for callout in layout.callouts {
            var line = Path()
            line.move(to: callout.slice.anchor)
            line.addLine(to: CGPoint(x: callout.elbowX,
                                     y: callout.textPoint.y))
            line.addLine(to: callout.textPoint)
            graphics.stroke(line, with: .color(.secondary.opacity(0.45)),
                            lineWidth: 1)

            let hovered = callout.slice.id == hoveredID
            let selected = callout.slice.segment.itemID != nil
                && callout.slice.segment.itemID == effectiveHighlight
            let text = graphics.resolve(
                Text(callout.text)
                    .font(.system(size: 8,
                                  weight: hovered || selected ? .semibold : .regular))
                    .foregroundColor(.primary.opacity(0.85)))
            graphics.draw(text, at: callout.textPoint,
                          anchor: callout.rightSide ? .leading : .trailing)
        }
    }

    // MARK: - Center

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
        if let percent = focusRow?.percent {
            return KBFormat.percent(percent)
        }
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
        if let row = focusRow {
            return row.label
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

    // MARK: - Hit testing

    private func slice(at location: CGPoint, layout: DonutLayout) -> SliceLayout? {
        let dx = location.x - layout.center.x
        let dy = location.y - layout.center.y
        let distance = hypot(dx, dy)
        guard distance >= layout.inner - 1, distance <= layout.outer + 1 else {
            return nil
        }
        var angle = atan2(dy, dx)
        if angle < -Double.pi / 2 { angle += 2 * Double.pi }
        return layout.slices.first {
            angle >= $0.startAngle && angle < $0.endAngle
        }
    }

    private func hoveredSegment(in layout: DonutLayout) -> APFSSpaceSegment? {
        guard let hoveredID else { return nil }
        return layout.slices.first { $0.id == hoveredID }?.segment
    }

    // MARK: - Tooltip

    private func tooltip(_ segment: APFSSpaceSegment) -> some View {
        let row = context.legend.first { $0.id == segment.id }
        let used = row?.bytes
        let capacity = row?.capacityBytes
        let percent = row?.percent
        let detail = row?.detail

        return VStack(alignment: .leading, spacing: 1) {
            Text(segment.label)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
            if let capacity {
                Text("\(used.map { KBFormat.bytes($0, units: byteUnitSystem) } ?? "—") / \(KBFormat.bytes(capacity, units: byteUnitSystem))")
                    .font(.system(size: 8, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if let used {
                Text(KBFormat.bytes(used, units: byteUnitSystem))
                    .font(.system(size: 8, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let percent {
                Text(KBFormat.percent(percent))
                    .font(.system(size: 8, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 7.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(width: 176, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .allowsHitTesting(false)
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(spacing: 3) {
            ForEach(context.legend) { row in
                let highlighted = (row.itemID != nil
                    && row.itemID == effectiveHighlight)
                    || row.id == hoveredID
                let content = legendRowContent(row, highlighted: highlighted)

                if row.role == .container, let onSelect,
                   let segment = context.segments.first(where: { $0.id == row.id }) {
                    Button { onSelect(segment) } label: { content }
                        .buttonStyle(.plain)
                        .accessibilityHint("Show the volumes in this APFS container")
                } else {
                    content
                }
            }
        }
    }

    private func legendRowContent(_ row: APFSSpaceLegendRow,
                                  highlighted: Bool) -> some View {
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
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(highlighted ? "Selected" : "")
    }

    // MARK: - Names and colors

    private func shortName(_ segment: APFSSpaceSegment) -> String {
        switch segment.role {
        case .container:
            return segment.label.split(separator: "·").first?
                .trimmingCharacters(in: .whitespaces) ?? segment.label
        case .residual:
            return segment.label.localizedCaseInsensitiveContains("snapshot")
                ? "Snapshots" : "Metadata"
        case .free:
            return "Free"
        case .unknown:
            return "Unknown"
        case .volume:
            return segment.label
        }
    }

    private func truncated(_ string: String, maxWidth: CGFloat) -> String {
        let maxCharacters = Int(maxWidth / 4.6)
        guard maxCharacters >= 2 else { return "" }
        if string.count <= maxCharacters { return string }
        return String(string.prefix(max(1, maxCharacters - 1))) + "…"
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
            let capacity = row.capacityBytes.map {
                KBFormat.bytes($0, units: byteUnitSystem)
            } ?? "—"
            return "\(used) / \(capacity)"
        case .volume, .residual, .free:
            return row.bytes.map { KBFormat.bytes($0, units: byteUnitSystem) } ?? "—"
        case .unknown:
            return "—"
        }
    }

    private var accessibilityValue: String {
        context.legend.map { row in
            let value = row.bytes.map { KBFormat.bytes($0, units: byteUnitSystem) }
                ?? "unknown"
            return "\(row.label): \(value)"
        }
        .joined(separator: "; ")
    }
}
