import SwiftUI

/// One segment of the vertical volume bar. Its fraction mirrors the weight of
/// the corresponding deepest block of the disk being viewed.
struct VolumeBarSlice: Identifiable {
    let id: String
    let fraction: Double
    let isFree: Bool
    let isHighlighted: Bool
    /// Text drawn inside the segment: the volume's device identifier, or
    /// "Free" for a container's free-space block.
    var label: String? = nil
    /// Disk item represented by the segment. Tapping the segment selects it.
    var ownerID: String? = nil
}

/// Shared geometry between the bar and the hero stats, so the Used label and
/// its leader line can target the selected segment.
enum VolumeBarLayout {
    static let contentInset: CGFloat = 2
    static let gap: CGFloat = 2

    static func minimumSliceHeight(isMaximized: Bool) -> CGFloat {
        isMaximized ? 13 : 12
    }

    static func heights(for slices: [VolumeBarSlice], height: CGFloat,
                        isMaximized: Bool) -> [CGFloat] {
        guard !slices.isEmpty else { return [] }
        let contentHeight = max(0, height - 2 * contentInset)
        let available = max(
            0, contentHeight - gap * CGFloat(max(0, slices.count - 1)))
        let count = CGFloat(slices.count)
        let requestedMinimum = minimumSliceHeight(isMaximized: isMaximized)
            * count
        let scale = requestedMinimum > available
            ? available / requestedMinimum : 1
        let minimum = minimumSliceHeight(isMaximized: isMaximized) * scale
        let remainder = max(0, available - minimum * count)
        let total = slices.reduce(0.0) {
            $0 + max(0, $1.fraction)
        }
        return slices.map { slice in
            let extra = total > 0
                ? remainder * CGFloat(max(0, slice.fraction) / total)
                : remainder / count
            return minimum + extra
        }
    }

    static func sliceIndex(at y: CGFloat, for slices: [VolumeBarSlice],
                           height: CGFloat,
                           isMaximized: Bool) -> Int? {
        let heights = heights(for: slices, height: height,
                              isMaximized: isMaximized)
        guard !heights.isEmpty else { return nil }
        var top = contentInset
        for (index, sliceHeight) in heights.enumerated() {
            let bottom = top + sliceHeight
            if y >= top, y <= bottom { return index }
            top = bottom + gap
        }
        return nil
    }

    static func selectedCenterY(for slices: [VolumeBarSlice],
                                height: CGFloat,
                                isMaximized: Bool) -> CGFloat? {
        let heights = heights(for: slices, height: height,
                              isMaximized: isMaximized)
        guard !heights.isEmpty else { return nil }
        var top = contentInset
        var firstTop: CGFloat?
        var lastBottom: CGFloat?
        for (index, slice) in slices.enumerated() {
            let bottom = top + heights[index]
            if slice.isHighlighted {
                if firstTop == nil { firstTop = top }
                lastBottom = bottom
            }
            top = bottom + gap
        }
        guard let first = firstTop, let last = lastBottom else {
            return nil
        }
        return (first + last) / 2
    }
}

/// The vertical, 4/5-height volume bar of the Volumes hero. A dark glass rail
/// holds the volume segments; the selected run gets a vivid gradient and a
/// neon outline.
struct VolumeBarView: View {
    let slices: [VolumeBarSlice]
    let width: CGFloat
    let height: CGFloat
    let tint: Color
    let isMaximized: Bool
    var onTapSlice: ((VolumeBarSlice) -> Void)? = nil

    private var trackCorner: CGFloat { isMaximized ? 14 : 12 }

    private var selectedCount: Int {
        slices.filter { $0.isHighlighted }.count
    }

    private var accessibilityValueText: String {
        var parts = ["\(slices.count) blocks"]
        if selectedCount > 0 {
            parts.append("\(selectedCount) selected")
        }
        let labels = slices.compactMap(\.label)
        if !labels.isEmpty {
            parts.append(labels.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Canvas { context, size in
            var context = context
            draw(context: &context, size: size)
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume bar")
        .accessibilityValue(accessibilityValueText)
        .highPriorityGesture(
            SpatialTapGesture().onEnded { value in
                guard let index = VolumeBarLayout.sliceIndex(
                    at: value.location.y, for: slices,
                    height: height, isMaximized: isMaximized) else {
                    return
                }
                onTapSlice?(slices[index])
            })
    }

    private struct SliceFrame {
        let slice: VolumeBarSlice
        let top: CGFloat
        let bottom: CGFloat
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        guard !slices.isEmpty, size.width > 8, size.height > 40 else {
            return
        }
        let track = CGRect(origin: .zero, size: size)
        let trackPath = Path(roundedRect: track,
                             cornerRadius: trackCorner)
        let contentInset = VolumeBarLayout.contentInset
        let contentRect = track.insetBy(dx: contentInset,
                                        dy: contentInset)
        let contentPath = Path(
            roundedRect: contentRect,
            cornerRadius: max(0, trackCorner - contentInset))

        drawHalo(context: &context, trackPath: trackPath)
        drawTrack(context: &context, trackPath: trackPath)

        var content = context
        content.clip(to: contentPath)

        let heights = VolumeBarLayout.heights(
            for: slices, height: size.height,
            isMaximized: isMaximized)

        var frames: [SliceFrame] = []
        var top = contentRect.minY
        for (index, slice) in slices.enumerated() {
            let sliceHeight = heights[index]
            let bottom = top + sliceHeight
            let rect = CGRect(x: contentRect.minX, y: top,
                              width: contentRect.width,
                              height: sliceHeight)
            drawSlice(context: &content, rect: rect, slice: slice)
            if let label = slice.label {
                drawLabel(context: &content, rect: rect, label: label,
                          sliceHeight: sliceHeight)
            }
            frames.append(SliceFrame(slice: slice, top: top,
                                     bottom: bottom))
            if index < slices.count - 1 {
                drawSeparator(context: &content,
                              rect: CGRect(x: contentRect.minX,
                                           y: bottom,
                                           width: contentRect.width,
                                           height: VolumeBarLayout.gap))
            }
            top = bottom + VolumeBarLayout.gap
        }

        drawSelection(context: &context, frames: frames,
                      contentRect: contentRect)
        drawTrackRim(context: &context, track: track,
                     cornerRadius: trackCorner)
    }

    // MARK: - Slice layout

    // MARK: - Track and slices

    private func drawHalo(context: inout GraphicsContext,
                          trackPath: Path) {
        var halo = context
        halo.addFilter(.blur(radius: max(7, width * 0.22)))
        halo.fill(trackPath, with: .color(tint.opacity(0.28)))
    }

    private func drawTrack(context: inout GraphicsContext,
                           trackPath: Path) {
        context.fill(
            trackPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(.sRGB, red: 0.12, green: 0.16,
                                       blue: 0.23, opacity: 1),
                          location: 0),
                    .init(color: Color(.sRGB, red: 0.05, green: 0.07,
                                       blue: 0.11, opacity: 1),
                          location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: height)))
        context.stroke(
            trackPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(0.26),
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.12)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: height)),
            lineWidth: 1)
    }

    private func drawSlice(context: inout GraphicsContext, rect: CGRect,
                           slice: VolumeBarSlice) {
        let selected = slice.isHighlighted
        if slice.isFree {
            drawFreeSlice(context: &context, rect: rect,
                          selected: selected)
        } else {
            let topColor: Color
            let bottomColor: Color
            if selected {
                topColor = Color(.sRGB, red: 0.49, green: 0.89,
                                 blue: 1.0, opacity: 0.98)
                bottomColor = Color(.sRGB, red: 0.16, green: 0.45,
                                    blue: 0.98, opacity: 0.98)
            } else {
                topColor = Color(.sRGB, red: 0.40, green: 0.51,
                                 blue: 0.65, opacity: 0.90)
                bottomColor = Color(.sRGB, red: 0.20, green: 0.29,
                                    blue: 0.39, opacity: 0.90)
            }
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [topColor, bottomColor]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            drawSliceEdges(context: &context, rect: rect,
                           opacity: selected ? 0.45 : 0.25)
        }
    }

    /// A tiny monospaced device identifier (or "Free") centered in the
    /// segment. Segments too short for a legible line stay unlabeled.
    private func drawLabel(context: inout GraphicsContext, rect: CGRect,
                           label: String, sliceHeight: CGFloat) {
        let minimumHeight: CGFloat = isMaximized ? 11 : 10
        guard sliceHeight >= minimumHeight else { return }
        let font = Font.system(size: isMaximized ? 8.5 : 8,
                               weight: .semibold, design: .monospaced)
        var resolved = context.resolve(Text(label).font(font))
        resolved.shading = .color(.white.opacity(0.92))
        var labelContext = context
        labelContext.addFilter(.shadow(color: .black.opacity(0.55),
                                       radius: 1, x: 0, y: 0.5))
        labelContext.draw(resolved,
                          at: CGPoint(x: rect.midX, y: rect.midY),
                          anchor: .center)
    }

    private func drawFreeSlice(context: inout GraphicsContext,
                               rect: CGRect, selected: Bool) {
        let topColor = selected
            ? Color(.sRGB, red: 0.49, green: 0.89, blue: 1.0,
                    opacity: 0.92)
            : Color(.sRGB, red: 0.62, green: 0.74, blue: 0.86,
                    opacity: 0.24)
        let bottomColor = selected
            ? Color(.sRGB, red: 0.16, green: 0.45, blue: 0.98,
                    opacity: 0.82)
            : Color(.sRGB, red: 0.34, green: 0.45, blue: 0.58,
                    opacity: 0.14)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [topColor, bottomColor]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

        var hatch = context
        hatch.clip(to: Path(rect))
        let step: CGFloat = 7
        var x = rect.minX - rect.height
        while x < rect.maxX {
            var line = Path()
            line.move(to: CGPoint(x: x, y: rect.maxY))
            line.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            hatch.stroke(line,
                         with: .color(.white.opacity(selected
                             ? 0.22 : 0.13)),
                         lineWidth: 1)
            x += step
        }
        drawSliceEdges(context: &context, rect: rect,
                       opacity: selected ? 0.40 : 0.18)
    }

    private func drawSliceEdges(context: inout GraphicsContext,
                                rect: CGRect, opacity: CGFloat) {
        context.fill(
            Path(CGRect(x: rect.minX, y: rect.minY,
                        width: rect.width, height: 0.7)),
            with: .color(.white.opacity(opacity)))
        context.fill(
            Path(CGRect(x: rect.minX, y: rect.maxY - 0.7,
                        width: rect.width, height: 0.7)),
            with: .color(.black.opacity(opacity * 0.9)))
    }

    private func drawSeparator(context: inout GraphicsContext,
                               rect: CGRect) {
        context.fill(Path(rect),
                     with: .color(.black.opacity(0.45)))
        context.fill(
            Path(CGRect(x: rect.minX, y: rect.minY,
                        width: rect.width, height: 0.6)),
            with: .color(.white.opacity(0.10)))
    }

    // MARK: - Light effects

    // MARK: - Selection

    private func drawSelection(context: inout GraphicsContext,
                               frames: [SliceFrame],
                               contentRect: CGRect) {
        let runs = selectedRuns(frames: frames)
        guard !runs.isEmpty else { return }
        let cyan = Color(.sRGB, red: 0.46, green: 0.87,
                         blue: 1.0, opacity: 1)
        let inset: CGFloat = 1.2
        let smallRadius: CGFloat = 4
        let capRadius = max(0, trackCorner
            - VolumeBarLayout.contentInset - inset)

        for run in runs {
            let top = run.top - inset
            let bottom = run.bottom + inset
            guard bottom - top > 2 else { continue }
            let touchesTop = run.top <= contentRect.minY + 0.5
            let touchesBottom = run.bottom >= contentRect.maxY - 0.5
            let runRect = CGRect(
                x: contentRect.minX - inset,
                y: top,
                width: contentRect.width + inset * 2,
                height: bottom - top)
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: touchesTop ? capRadius : smallRadius,
                bottomLeadingRadius: touchesBottom ? capRadius : smallRadius,
                bottomTrailingRadius: touchesBottom ? capRadius : smallRadius,
                topTrailingRadius: touchesTop ? capRadius : smallRadius,
                style: .continuous)
            let path = shape.path(in: runRect)

            var glow = context
            glow.addFilter(.blur(radius: 7))
            glow.stroke(path, with: .color(cyan.opacity(0.55)),
                        lineWidth: 5)
            context.stroke(path, with: .color(cyan.opacity(0.95)),
                           lineWidth: 1.6)
            context.stroke(path, with: .color(.white.opacity(0.55)),
                           lineWidth: 0.7)
        }
    }

    private func drawTrackRim(context: inout GraphicsContext,
                              track: CGRect,
                              cornerRadius: CGFloat) {
        let inner = Path(
            roundedRect: track.insetBy(dx: 1, dy: 1),
            cornerRadius: max(0, cornerRadius - 1))
        context.stroke(inner, with: .color(.white.opacity(0.10)),
                       lineWidth: 0.6)
    }

    private func selectedRuns(frames: [SliceFrame])
        -> [(top: CGFloat, bottom: CGFloat)] {
        var runs: [(top: CGFloat, bottom: CGFloat)] = []
        var runTop: CGFloat?
        var runBottom: CGFloat?
        for frame in frames {
            if frame.slice.isHighlighted {
                if runTop == nil { runTop = frame.top }
                runBottom = frame.bottom
            } else if let top = runTop, let bottom = runBottom {
                runs.append((top, bottom))
                runTop = nil
                runBottom = nil
            }
        }
        if let top = runTop, let bottom = runBottom {
            runs.append((top, bottom))
        }
        return runs
    }
}
