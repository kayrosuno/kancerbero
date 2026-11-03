import AppKit
import SwiftUI
import KancerberoCore

/// APFS space as a single stacked bar plus a clickable legend. Clicking a
/// container/volume slice or legend row selects that item.
struct APFSSpaceBarChart: View {
    let context: APFSSpaceContext
    var onSelect: ((APFSSpaceSegment) -> Void)? = nil

    @Environment(\.byteUnitSystem) private var byteUnitSystem
    @State private var hoveredID: String?

    private var drawnSegments: [APFSSpaceSegment] {
        context.segments.filter { $0.fraction > 0 }
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

            stackedBar

            legend

            if let note = context.note {
                Text(note)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Stacked bar

    private var stackedBar: some View {
        GeometryReader { proxy in
            let segments = drawnSegments
            let gaps = max(0, segments.count - 1)
            let available = max(0, proxy.size.width - CGFloat(gaps))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.25))

                if !segments.isEmpty {
                    HStack(spacing: 1) {
                        ForEach(segments) { segment in
                            segmentCell(segment, available: available)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segmentCell(_ segment: APFSSpaceSegment,
                             available: CGFloat) -> some View {
        let width = max(1, available * CGFloat(min(max(segment.fraction, 0), 1)))
        let focused = hoveredID == segment.id
            || (segment.itemID != nil
                && segment.itemID == context.highlightedItemID)
        // Only a hover dims the rest of the bar: the selected item may have no
        // drawn slice (an empty volume), which would wash out every segment.
        let dimmed = hoveredID != nil && !focused
        let fill = color(for: segment).opacity(dimmed ? 0.45 : 1)
        let selectable = segment.itemID != nil
            && (segment.role == .container || segment.role == .volume)

        if selectable, let onSelect {
            Button { onSelect(segment) } label: {
                Rectangle()
                    .fill(fill)
                    .frame(width: width, height: 18)
                    .contentShape(Rectangle())
                    .overlay {
                        segmentLabel(segment, width: width)
                    }
            }
            .buttonStyle(.plain)
            .onHover { inside in hover(segment.id, inside: inside) }
            .help(segment.label)
        } else {
            Rectangle()
                .fill(fill)
                .frame(width: width, height: 18)
                .overlay {
                    segmentLabel(segment, width: width)
                }
                .onHover { inside in hover(segment.id, inside: inside) }
        }
    }

    private static let labelFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)

    /// Draws `disk3s5 - Macintosh HD - Data` inside the slice, but only when
    /// the whole label fits: tiny slices stay clean and remain readable from
    /// the legend. The width is measured against the slice itself instead of
    /// relying on layout, so a label can never spill over its neighbours.
    @ViewBuilder
    private func segmentLabel(_ segment: APFSSpaceSegment,
                              width: CGFloat) -> some View {
        if let text = barLabel(segment), labelFits(text, in: width) {
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(labelColor(for: segment.role))
                .lineLimit(1)
                .shadow(color: .black.opacity(segment.role == .free ? 0 : 0.3),
                        radius: 1, y: 0.5)
                .padding(.horizontal, 6)
        }
    }

    private func labelFits(_ text: String, in width: CGFloat) -> Bool {
        let size = (text as NSString).size(withAttributes: [.font: Self.labelFont])
        return size.width + 12 <= width
    }

    private func barLabel(_ segment: APFSSpaceSegment) -> String? {
        switch segment.role {
        case .volume:
            guard let id = segment.itemID else { return segment.label }
            return "\(id) - \(segment.label)"
        case .container:
            guard let id = segment.itemID else { return segment.label }
            let name = segment.label.hasPrefix(id)
                ? String(segment.label.dropFirst(id.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ·-"))
                : segment.label
            return name.isEmpty ? id : "\(id) - \(name)"
        case .free, .residual:
            return segment.label
        case .unknown:
            return nil
        }
    }

    private func labelColor(for role: APFSSpaceSegment.Role) -> Color {
        switch role {
        case .volume, .container: return .white
        case .free, .residual, .unknown: return .secondary
        }
    }

    private func hover(_ id: String, inside: Bool) {
        if inside {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(spacing: 3) {
            ForEach(context.legend) { row in
                let highlighted = row.id == hoveredID
                    || (row.itemID != nil
                        && row.itemID == context.highlightedItemID)
                let segment = context.segments.first { $0.id == row.id }
                let selectable = (row.role == .container || row.role == .volume)
                    && row.itemID != nil && onSelect != nil && segment != nil

                if selectable, let segment, let onSelect {
                    Button { onSelect(segment) } label: {
                        legendContent(row, highlighted: highlighted)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in hover(row.id, inside: inside) }
                    .accessibilityHint("Show the details for \(row.label)")
                } else {
                    legendContent(row, highlighted: highlighted)
                        .onHover { inside in hover(row.id, inside: inside) }
                }
            }
        }
    }

    private func legendContent(_ row: APFSSpaceLegendRow,
                               highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color(for: row))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text(row.label)
                    .font(.system(size: 11,
                                  weight: highlighted ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 0) {
                Text(valueText(row))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let percent = row.percent {
                    Text(KBFormat.percent(percent))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
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

    // MARK: - Data

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
            let used = row.bytes.map { KBFormat.bytes($0, units: byteUnitSystem) }
                ?? "—"
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
}
