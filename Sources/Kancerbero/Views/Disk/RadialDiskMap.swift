import AppKit
import SwiftUI
import KancerberoCore

/// Sunburst map of the scanned tree. The current node is the center; each ring
/// represents one level of descendants, and each sector's angle is proportional
/// to its allocated size. A single click selects a sector (or clears the
/// selection on empty space, the center or a synthetic sector); double-clicking
/// a directory drills into it, and double-clicking the center drills up.
struct RadialDiskMap: View {
    let root: KBDiskNode
    let focus: KBDiskNode
    let volumeCapacity: UInt64?
    let showHidden: Bool
    let showPackageContents: Bool
    let selectedPath: String?
    /// A file selected in Contents or Largest files. Files are not tree nodes,
    /// so the map draws a synthetic wedge for it when its parent is the focus.
    let selectedFile: KBDiskFile?
    let onSelect: (KBDiskNode) -> Void
    let onPick: (KBDiskNode?) -> Void
    let onCenterTap: () -> Void

    @Environment(\.byteUnitSystem) private var byteUnitSystem

    @State private var hoveredID: String?

    private let maxDepth = 3
    private let minimumLabelAngle = 0.28

    private static let palette = KBTheme.diskChartPalette

    var body: some View {
        GeometryReader { proxy in
            let layout = makeLayout(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    draw(layout: layout, context: &context)
                }

                centerLabel(centerRadius: layout.centerRadius)
                    .position(layout.center)
                    .allowsHitTesting(false)

                if let hoveredID,
                   let sector = layout.sectors.first(where: { $0.id == hoveredID }) {
                    tooltip(sector)
                        .padding(8)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredID = sector(at: location, layout: layout)?.id
                case .ended:
                    hoveredID = nil
                }
            }
            // A single click selects (or clears); a double click navigates.
            // Both recognizers report `location` in this view's local coordinate
            // space, the same one used by `makeLayout`, hover and the hit-test
            // helpers below. They run simultaneously so the count-2 recognizer
            // is never blocked by the count-1 one.
            .gesture(
                SpatialTapGesture(count: 2).onEnded { value in
                    handleDoubleTap(at: value.location, layout: layout)
                }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 1).onEnded { value in
                    handleSingleTap(at: value.location, layout: layout)
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(focus.name), \(KBFormat.bytes(focus.allocatedBytes, units: byteUnitSystem))")
        .accessibilityValue("\(focus.children.count) items")
        .accessibilityAction(named: "Go up one level") {
            onCenterTap()
        }
        .animation(.snappy(duration: 0.25), value: focus.id)
    }

    // MARK: - Layout

    private struct Sector: Identifiable {
        let id: String
        let node: KBDiskNode?
        let depth: Int
        let startAngle: Double
        let endAngle: Double
        let innerRadius: CGFloat
        let outerRadius: CGFloat
        let color: Color
        let label: String
        let size: UInt64
    }

    private struct Layout {
        let sectors: [Sector]
        let center: CGPoint
        let centerRadius: CGFloat
        let maxRadius: CGFloat
        let canvasRadius: CGFloat
    }

    private func makeLayout(in size: CGSize) -> Layout {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let canvasRadius = max(0, side / 2)
        let maxRadius = max(0, canvasRadius - 14)
        let centerRadius = max(40, min(78, side * 0.11))
        let ringWidth = max(0, (maxRadius - centerRadius) / CGFloat(maxDepth))

        var sectors: [Sector] = []
        let start = -Double.pi / 2
        let end = 3 * Double.pi / 2
        let isRootVolume = focus.id == root.id && (volumeCapacity ?? 0) > 0
        let total = isRootVolume
            ? max(focus.allocatedBytes, volumeCapacity ?? 0)
            : max(focus.allocatedBytes, 1)

        let visible = focus.children
            .filter { showHidden || !$0.isHidden }
            .sorted { $0.allocatedBytes > $1.allocatedBytes }

        var angle = start
        for (index, child) in visible.enumerated() {
            let span = (end - start) * Double(child.allocatedBytes) / Double(total)
            guard span > 0 else { continue }
            let sector = Sector(
                id: "\(child.path)|0",
                node: child,
                depth: 0,
                startAngle: angle,
                endAngle: angle + span,
                innerRadius: centerRadius,
                outerRadius: centerRadius + ringWidth,
                color: color(index: index, depth: 0),
                label: child.name,
                size: child.allocatedBytes
            )
            sectors.append(sector)

            if shouldDescend(into: child), span >= 0.004 {
                appendChildren(
                    of: child,
                    depth: 1,
                    start: angle,
                    end: angle + span,
                    colorIndex: index,
                    centerRadius: centerRadius,
                    ringWidth: ringWidth,
                    sectors: &sectors
                )
            }
            angle += span
        }

        if !showHidden {
            let hidden = focus.children.filter(\.isHidden)
            let hiddenSize = hidden.reduce(UInt64(0)) { $0 &+ $1.allocatedBytes }
            if hiddenSize > 0 {
                let span = (end - start) * Double(hiddenSize) / Double(total)
                sectors.append(Sector(
                    id: "\(focus.path)|hidden",
                    node: nil,
                    depth: 0,
                    startAngle: angle,
                    endAngle: angle + span,
                    innerRadius: centerRadius,
                    outerRadius: centerRadius + ringWidth,
                    color: .gray.opacity(0.35),
                    label: "Hidden",
                    size: hiddenSize
                ))
                angle += span
            }
        }

        let visibleSize = visible.reduce(UInt64(0)) { $0 &+ $1.allocatedBytes }
        let hiddenSize = showHidden ? 0 : focus.children
            .filter(\.isHidden)
            .reduce(UInt64(0)) { $0 &+ $1.allocatedBytes }
        let accounted = visibleSize &+ hiddenSize
        let residual = total > accounted ? total - accounted : 0

        // A `largestFiles` row is not a tree node and its bytes live inside the
        // residual ("Other"/"Not scanned"). Draw it as its own wedge only when
        // its direct parent is the focus and carve that size out of the
        // residual, so the ring still spans exactly [-pi/2, 3pi/2).
        var injectedFileSize: UInt64 = 0
        if let selectedFile,
           (selectedFile.path as NSString).deletingLastPathComponent == focus.path {
            let candidate = min(selectedFile.allocatedBytes, residual)
            let span = (end - start) * Double(candidate) / Double(total)
            if candidate > 0, span > 0 {
                sectors.append(Sector(
                    id: "\(selectedFile.path)|file",
                    node: KBDiskNode(displayFile: selectedFile),
                    depth: 0,
                    startAngle: angle,
                    endAngle: min(angle + span, end),
                    innerRadius: centerRadius,
                    outerRadius: centerRadius + ringWidth,
                    color: .accentColor,
                    label: selectedFile.name,
                    size: selectedFile.allocatedBytes
                ))
                angle = min(angle + span, end)
                injectedFileSize = candidate
            }
        }

        let residualSize = residual - injectedFileSize
        if residualSize > 0 && (focus.allocatedBytes > 0 || isRootVolume) {
            let span = (end - start) * Double(residualSize) / Double(total)
            sectors.append(Sector(
                id: "\(focus.path)|residual",
                node: nil,
                depth: 0,
                startAngle: angle,
                endAngle: min(angle + span, end),
                innerRadius: centerRadius,
                outerRadius: centerRadius + ringWidth,
                color: .gray.opacity(0.22),
                label: isRootVolume ? "Not scanned" : "Other",
                size: residualSize
            ))
        }

        return Layout(sectors: sectors, center: center,
                      centerRadius: centerRadius, maxRadius: maxRadius,
                      canvasRadius: canvasRadius)
    }

    private func appendChildren(of node: KBDiskNode,
                                depth: Int,
                                start: Double,
                                end: Double,
                                colorIndex: Int,
                                centerRadius: CGFloat,
                                ringWidth: CGFloat,
                                sectors: inout [Sector]) {
        guard depth < maxDepth else { return }
        let total = max(node.allocatedBytes, 1)
        let visible = node.children
            .filter { showHidden || !$0.isHidden }
            .sorted { $0.allocatedBytes > $1.allocatedBytes }
        guard !visible.isEmpty else { return }

        let inner = centerRadius + CGFloat(depth) * ringWidth
        let outer = inner + ringWidth
        var angle = start

        for child in visible {
            let span = (end - start) * Double(child.allocatedBytes) / Double(total)
            guard span > 0 else { continue }
            sectors.append(Sector(
                id: "\(child.path)|\(depth)",
                node: child,
                depth: depth,
                startAngle: angle,
                endAngle: angle + span,
                innerRadius: inner,
                outerRadius: outer,
                color: color(index: colorIndex, depth: depth),
                label: child.name,
                size: child.allocatedBytes
            ))
            if shouldDescend(into: child), depth + 1 < maxDepth, span >= 0.004 {
                appendChildren(
                    of: child,
                    depth: depth + 1,
                    start: angle,
                    end: angle + span,
                    colorIndex: colorIndex,
                    centerRadius: centerRadius,
                    ringWidth: ringWidth,
                    sectors: &sectors
                )
            }
            angle += span
        }

        if !showHidden {
            let hidden = node.children.filter(\.isHidden)
            let hiddenSize = hidden.reduce(UInt64(0)) { $0 &+ $1.allocatedBytes }
            if hiddenSize > 0 {
                let span = (end - start) * Double(hiddenSize) / Double(total)
                sectors.append(Sector(
                    id: "\(node.path)|hidden|\(depth)",
                    node: nil,
                    depth: depth,
                    startAngle: angle,
                    endAngle: angle + span,
                    innerRadius: inner,
                    outerRadius: outer,
                    color: .gray.opacity(0.30),
                    label: "Hidden",
                    size: hiddenSize
                ))
                angle += span
            }
        }
    }

    private func shouldDescend(into node: KBDiskNode) -> Bool {
        node.isDirectory
            && !node.isAggregate
            && !node.isMountPoint
            && (showPackageContents || !node.isPackage)
    }

    private func color(index: Int, depth: Int) -> Color {
        let base = Self.palette[index % Self.palette.count]
        let opacity = depth == 0 ? 1.0 : max(0.55, 0.88 - Double(depth) * 0.12)
        return base.opacity(opacity)
    }

    // MARK: - Drawing

    private func draw(layout: Layout, context: inout GraphicsContext) {
        let selected = selectedSector(in: layout)

        // Draw the selected sector last: its outward growth overlaps the child
        // rings, so it must sit on top of them (and of their labels).
        for sector in layout.sectors {
            if let selected, sector.id == selected.id { continue }
            drawSector(sector, layout: layout, context: &context,
                       highlighted: false, outerGrowth: 0)
        }
        if let selected {
            drawSector(selected, layout: layout, context: &context,
                       highlighted: true,
                       outerGrowth: growth(for: selected, layout: layout))
        }

        let centerRect = CGRect(
            x: layout.center.x - layout.centerRadius,
            y: layout.center.y - layout.centerRadius,
            width: layout.centerRadius * 2,
            height: layout.centerRadius * 2
        )
        let centerPath = Path(ellipseIn: centerRect)
        context.fill(centerPath, with: .color(Color(nsColor: .controlBackgroundColor)))
        context.stroke(centerPath, with: .color(Color.secondary.opacity(0.35)),
                       lineWidth: 1)
    }

    private func drawSector(_ sector: Sector, layout: Layout,
                            context: inout GraphicsContext,
                            highlighted: Bool, outerGrowth: CGFloat) {
        let outerRadius = sector.outerRadius + outerGrowth
        var path = Path()
        path.addArc(center: layout.center,
                    radius: outerRadius,
                    startAngle: .radians(sector.startAngle),
                    endAngle: .radians(sector.endAngle),
                    clockwise: false)
        path.addArc(center: layout.center,
                    radius: sector.innerRadius,
                    startAngle: .radians(sector.endAngle),
                    endAngle: .radians(sector.startAngle),
                    clockwise: true)
        path.closeSubpath()

        let hovered = hoveredID == sector.id
        context.fill(path,
                     with: .color(sector.color.opacity((hovered || highlighted) ? 1 : 0.92)))
        context.stroke(path, with: .color(.black.opacity(0.10)), lineWidth: 0.5)
        if highlighted {
            // Dark halo + bright inner ring, so the persistent selection reads
            // over every palette colour in light and dark appearance.
            context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 4)
            context.stroke(path, with: .color(.white.opacity(0.95)), lineWidth: 2)
        } else if hovered {
            context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        }

        let span = sector.endAngle - sector.startAngle
        if span >= minimumLabelAngle,
           outerRadius - sector.innerRadius >= 20 {
            let middle = (sector.startAngle + sector.endAngle) / 2
            let radius = (sector.innerRadius + outerRadius) / 2
            let point = CGPoint(
                x: layout.center.x + cos(middle) * radius,
                y: layout.center.y + sin(middle) * radius
            )
            let nameText = context.resolve(
                Text(sector.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
            )
            let sizeText = context.resolve(
                Text(KBFormat.bytes(sector.size, units: byteUnitSystem))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.white.opacity(0.82))
            )
            context.draw(nameText,
                         at: CGPoint(x: point.x, y: point.y - 5.5),
                         anchor: .center)
            context.draw(sizeText,
                         at: CGPoint(x: point.x, y: point.y + 5.5),
                         anchor: .center)
        }
    }

    /// Outward growth of the selected sector: ~10 pt, never closer than 3 pt
    /// to the Canvas edge (the halo already adds 2 pt).
    private func growth(for sector: Sector, layout: Layout) -> CGFloat {
        min(10, max(0, layout.canvasRadius - sector.outerRadius - 3))
    }

    private func selectedSector(in layout: Layout) -> Sector? {
        guard let selectedPath else { return nil }
        return layout.sectors.first { $0.node?.path == selectedPath }
    }

    private func centerLabel(centerRadius: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(focus.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
            Text(KBFormat.bytes(focus.allocatedBytes, units: byteUnitSystem))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .monospacedDigit()
            if let capacity = volumeCapacity,
               capacity > 0,
               focus.id == root.id {
                Text(KBFormat.percent(Double(focus.allocatedBytes) / Double(capacity)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .monospacedDigit()
            }
        }
        .frame(width: centerRadius * 1.7, height: centerRadius * 1.7)
    }

    private func tooltip(_ sector: Sector) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sector.label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text(KBFormat.bytes(sector.size, units: byteUnitSystem))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.6), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Hit testing

    private func handleSingleTap(at location: CGPoint, layout: Layout) {
        // Center, empty space and synthetic sectors (Hidden/Other/Not scanned)
        // carry no node, so they clear the shared selection.
        guard !isInsideCenter(location, layout: layout),
              let sector = sector(at: location, layout: layout),
              let node = sector.node else {
            onPick(nil)
            return
        }
        onPick(node)
    }

    private func handleDoubleTap(at location: CGPoint, layout: Layout) {
        if isInsideCenter(location, layout: layout) {
            onCenterTap()
            return
        }
        guard let sector = sector(at: location, layout: layout),
              let node = sector.node,
              node.isDirectory,
              !node.isAggregate,
              !(node.isPackage && !showPackageContents) else { return }
        onSelect(node)
    }

    private func isInsideCenter(_ point: CGPoint, layout: Layout) -> Bool {
        let dx = point.x - layout.center.x
        let dy = point.y - layout.center.y
        return dx * dx + dy * dy < layout.centerRadius * layout.centerRadius
    }

    private func sector(at location: CGPoint, layout: Layout) -> Sector? {
        let dx = location.x - layout.center.x
        let dy = location.y - layout.center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= layout.centerRadius else { return nil }

        var angle = atan2(dy, dx)
        if angle < -Double.pi / 2 {
            angle += 2 * Double.pi
        }

        // The selected sector grows outward; test it first with the expanded
        // radius so its grown band stays clickable and hoverable.
        if let selected = selectedSector(in: layout),
           distance >= selected.innerRadius,
           distance <= selected.outerRadius + growth(for: selected, layout: layout),
           angle >= selected.startAngle,
           angle < selected.endAngle {
            return selected
        }

        guard distance <= layout.maxRadius else { return nil }
        return layout.sectors.first { sector in
            distance >= sector.innerRadius
                && distance <= sector.outerRadius
                && angle >= sector.startAngle
                && angle < sector.endAngle
        }
    }
}
