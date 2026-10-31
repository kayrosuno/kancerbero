import SwiftUI

/// Per-core load history drawn as a dense wall of rectangular bars. Bars are
/// left-aligned (newest at the left), colored by load, and the latest sample
/// gets a bright cap. The faint tracks keep the grid visible while the history
/// warms up.
struct CoreLoadBars: View {
    var values: [Double]
    var maxBars: Int = 20
    var barGap: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 1, maxBars > 0 else { return }

            let samples = Array(values.suffix(maxBars)).map { value in
                value.isFinite ? min(max(value, 0), 100) : 0
            }
            let slot = size.width / CGFloat(maxBars)
            let barWidth = max(0.75, min(slot - barGap, slot))
            let chartHeight = size.height - 1

            for index in 0..<maxBars {
                let rect = CGRect(x: CGFloat(index) * slot + (slot - barWidth) / 2,
                                  y: 0,
                                  width: barWidth,
                                  height: chartHeight)
                context.fill(Path(rect), with: .color(.secondary.opacity(0.08)))
            }

            if chartHeight >= 40 {
                let y = chartHeight * 0.5
                let guide = CGRect(x: 0, y: y, width: size.width, height: 0.5)
                context.fill(Path(guide), with: .color(.secondary.opacity(0.10)))
            }

            if let latest = samples.last {
                let heat = KBTheme.loadHeat(latest)
                let x = (slot - barWidth) / 2
                let glow = CGRect(x: x - 1,
                                  y: 0,
                                  width: barWidth + 2,
                                  height: chartHeight)
                context.fill(Path(glow), with: .color(heat.opacity(0.07)))
            }

            if !samples.isEmpty {
                let start = 0
                for (offset, value) in samples.enumerated() {
                    let height = max(value > 0 ? 1 : 0, chartHeight * value / 100)
                    let slotIndex = samples.count - 1 - offset
                    let x = CGFloat(start + slotIndex) * slot + (slot - barWidth) / 2
                    let rect = CGRect(x: x,
                                      y: chartHeight - height,
                                      width: barWidth,
                                      height: height)
                    let recency = samples.count > 1
                        ? 0.6 + 0.4 * Double(offset) / Double(samples.count - 1)
                        : 1
                    context.fill(Path(rect),
                                 with: .color(KBTheme.loadHeat(value).opacity(recency)))
                }

                if let latest = samples.last, chartHeight * latest / 100 >= 2 {
                    let height = chartHeight * latest / 100
                    let x = (slot - barWidth) / 2
                    let cap = CGRect(x: x,
                                     y: chartHeight - height - 1,
                                     width: barWidth,
                                     height: 1)
                    context.fill(Path(cap), with: .color(.primary.opacity(0.85)))
                }
            }

            let baseline = CGRect(x: 0,
                                  y: size.height - 0.5,
                                  width: size.width,
                                  height: 0.5)
            context.fill(Path(baseline), with: .color(.secondary.opacity(0.25)))
        }
        .accessibilityHidden(true)
    }
}
