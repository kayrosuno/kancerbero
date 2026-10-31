import AppKit
import SwiftUI
import KancerberoCore

/// Twelve-hour battery charge history, modelled on Activity Monitor's Energy
/// tab: a cyan charge line over a dashed quarter grid, with green bands for
/// the periods the Mac was on AC power.
struct BatteryChargeChart: View {
    let graph: KBBatteryChargeGraph

    private static let window: TimeInterval = 12 * 3600

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery charge history")
        .accessibilityValue(accessibilityValue)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }

        var grid = Path()
        for fraction in [0.25, 0.5, 0.75] {
            let x = size.width * fraction
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            let y = size.height * fraction
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid,
                       with: .color(.secondary.opacity(0.25)),
                       style: StrokeStyle(lineWidth: 1, dash: [6, 3]))

        let green = Color(nsColor: .systemGreen).opacity(0.3)
        for rect in acRegions(size: size) {
            context.fill(Path(rect), with: .color(green))
        }

        let points = chargePoints(size: size)
        guard points.count >= 2 else { return }
        // Activity Monitor strokes a closed polygon: baseline, right edge and
        // the charge curve drawn on top of it.
        var path = Path()
        path.move(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        context.stroke(path,
                       with: .color(Color(nsColor: .systemCyan)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
    }

    /// Charge samples across the fixed 12 h window, oldest first. Activity
    /// Monitor keeps the oldest sample before the window as a right anchor;
    /// the first point is pinned to the right edge and the last level extends
    /// to the left edge. A single sample therefore draws a flat line.
    private func chargePoints(size: CGSize) -> [CGPoint] {
        let samples = chargeSamples()
        guard !samples.isEmpty else { return [] }

        var points: [CGPoint] = []
        points.reserveCapacity(samples.count + 1)
        for (index, sample) in samples.enumerated() {
            let x = index == 0 ? size.width : xPosition(sample.time, width: size.width)
            points.append(CGPoint(x: x, y: yPosition(sample.level, height: size.height)))
        }
        if let last = samples.last {
            points.append(CGPoint(x: 0,
                                  y: yPosition(last.level, height: size.height)))
        }
        return points
    }

    private typealias ChargeSample = (time: Double, level: Double)

    private func chargeSamples() -> [ChargeSample] {
        let all = zip(graph.chargeTimes, graph.chargeLevels)
            .filter { $0.0.isFinite && $0.1.isFinite && $0.0 >= 0 }
            .sorted { $0.0 > $1.0 }
            .map { (time: $0.0, level: $0.1) }
        guard !all.isEmpty else { return [] }
        guard let firstInside = all.firstIndex(where: { $0.0 < Self.window }) else {
            // No sample inside the window: Activity Monitor still draws the
            // newest one, extended flat to the right edge.
            return [all[all.count - 1]]
        }
        var samples = Array(all[firstInside...])
        if firstInside > 0 {
            samples.insert(all[firstInside - 1], at: 0)
        }
        return samples
    }

    /// Full-height bands for the AC intervals. The state just before the
    /// window anchors the right edge; the current state owns everything up to
    /// the left edge.
    private func acRegions(size: CGSize) -> [CGRect] {
        let entries = stateEntries()
        guard let first = entries.first else { return [] }

        var regions: [CGRect] = []
        var previous = first.onAC
        var start = size.width
        for (index, entry) in entries.enumerated() {
            let x = index == 0 ? size.width : xPosition(entry.time, width: size.width)
            if entry.onAC != previous {
                if entry.onAC {
                    start = x
                } else {
                    let left = min(start, x)
                    let right = max(start, x)
                    regions.append(CGRect(x: left, y: 0,
                                          width: max(0, right - left),
                                          height: size.height))
                }
                previous = entry.onAC
            }
        }
        if previous {
            regions.append(CGRect(x: 0, y: 0,
                                  width: max(0, start),
                                  height: size.height))
        }
        return regions
    }

    private typealias StateEntry = (time: Double, onAC: Bool)

    private func stateEntries() -> [StateEntry] {
        guard !graph.onAC.isEmpty, graph.onAC.count == graph.stateTimes.count else {
            return []
        }
        let all = zip(graph.stateTimes, graph.onAC)
            .filter { $0.0.isFinite && $0.0 >= 0 }
            .sorted { $0.0 > $1.0 }
            .map { (time: $0.0, onAC: $0.1) }
        guard !all.isEmpty else { return [] }
        guard let firstInside = all.firstIndex(where: { $0.0 < Self.window }) else {
            return [all[all.count - 1]]
        }
        var entries = Array(all[firstInside...])
        if firstInside > 0 {
            entries.insert(all[firstInside - 1], at: 0)
        }
        return entries
    }

    private func xPosition(_ secondsAgo: Double, width: CGFloat) -> CGFloat {
        let fraction = min(max(secondsAgo / Self.window, 0), 1)
        return width * fraction
    }

    /// Activity Monitor maps 0...100 % into a 2 pt inset at both edges.
    private func yPosition(_ level: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(level, 0), 100)
        return height - (2 + (height - 4) * clamped / 100)
    }

    private var accessibilityValue: String {
        let samples = zip(graph.chargeTimes, graph.chargeLevels)
            .sorted { $0.0 > $1.0 }
        guard let latest = samples.last else { return "No data" }
        let level = Int(latest.1.rounded())
        let states = zip(graph.stateTimes, graph.onAC).sorted { $0.0 > $1.0 }
        if let state = states.last {
            return "Latest \(level) percent, \(state.1 ? "on AC power" : "on battery")"
        }
        return "Latest \(level) percent"
    }
}
