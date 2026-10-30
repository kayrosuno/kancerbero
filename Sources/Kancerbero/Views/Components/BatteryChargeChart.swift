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
        // Activity Monitor strokes a closed polygon: baseline, left edge and
        // the charge curve drawn on top of it.
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.stroke(path,
                       with: .color(Color(nsColor: .systemCyan)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
    }

    /// Charge samples across the fixed 12 h window. The first in-window point
    /// is pinned to the left edge and the last level extends to the right
    /// edge, like Activity Monitor.
    private func chargePoints(size: CGSize) -> [CGPoint] {
        let samples = zip(graph.chargeTimes, graph.chargeLevels)
            .filter { $0.0 >= 0 && $0.0 < Self.window }
            .sorted { $0.0 > $1.0 }
        guard samples.count >= 2 else { return [] }

        var points: [CGPoint] = []
        points.reserveCapacity(samples.count + 1)
        for (index, sample) in samples.enumerated() {
            let x = index == 0 ? 0 : xPosition(sample.0, width: size.width)
            points.append(CGPoint(x: x, y: yPosition(sample.1, height: size.height)))
        }
        if let last = samples.last {
            points.append(CGPoint(x: size.width,
                                  y: yPosition(last.1, height: size.height)))
        }
        return points
    }

    /// Full-height bands for the AC intervals. The first in-window state owns
    /// the left edge; the latest state owns everything up to the right edge.
    private func acRegions(size: CGSize) -> [CGRect] {
        guard !graph.onAC.isEmpty, graph.onAC.count == graph.stateTimes.count else {
            return []
        }
        let entries = zip(graph.stateTimes, graph.onAC)
            .filter { $0.0 >= 0 && $0.0 < Self.window }
            .sorted { $0.0 > $1.0 }
        guard let first = entries.first else { return [] }

        var regions: [CGRect] = []
        var previous = first.1
        var start: CGFloat = 0
        for entry in entries {
            let x = xPosition(entry.0, width: size.width)
            if entry.1 != previous {
                if entry.1 {
                    start = x
                } else {
                    regions.append(CGRect(x: start, y: 0,
                                          width: max(0, x - start),
                                          height: size.height))
                }
                previous = entry.1
            }
        }
        if previous {
            regions.append(CGRect(x: start, y: 0,
                                  width: max(0, size.width - start),
                                  height: size.height))
        }
        return regions
    }

    private func xPosition(_ secondsAgo: Double, width: CGFloat) -> CGFloat {
        let fraction = min(max(1 - secondsAgo / Self.window, 0), 1)
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
