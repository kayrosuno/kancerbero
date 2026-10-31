import SwiftUI
import KancerberoCore

/// Live interface rates and cumulative totals grouped by direction, modelled
/// on Activity Monitor's Network tab.
struct NetworkTotalsCard: View {
    let counters: KBCounters
    let rates: KBRates

    private enum Direction {
        case input
        case output

        var title: String {
            self == .input ? "Input" : "Output"
        }

        var icon: String {
            self == .input ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
        }

        var tint: Color {
            self == .input ? KBTheme.downloadTint : KBTheme.uploadTint
        }

        func totals(in counters: KBCounters) -> (bytes: UInt64, packets: UInt64) {
            self == .input
                ? (counters.rxBytes, counters.rxPackets)
                : (counters.txBytes, counters.txPackets)
        }

        func liveRates(in rates: KBRates) -> (bytes: Double, packets: Double) {
            self == .input
                ? (rates.rxBytesPerSecond, rates.rxPacketsPerSecond)
                : (rates.txBytesPerSecond, rates.txPacketsPerSecond)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(spacing: 6) {
                directionPanel(.input)
                directionPanel(.output)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [KBTheme.downloadTint.opacity(0.32),
                                 KBTheme.uploadTint.opacity(0.32)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .help("Live interface rates and cumulative totals since boot. Counters reset "
              + "if an interface restarts.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Network totals")
        .accessibilityValue(accessibilityValue)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "network")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(KBTheme.brandGradient)
                }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text("Network totals")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("since boot")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text("Network")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("since boot")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text("Network")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .frame(height: 18)
    }

    /// Both live rates share size and colour; both totals do too.
    private func liveValue(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
    }

    private func totalValue(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .layoutPriority(1)
            .contentTransition(.numericText())
    }

    private func metricLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .medium))
            .tracking(0.2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Static, unselected twin of `MetricTile`: same radius, fill and border,
    /// but no button, checkmark or focus treatment.
    private func directionPanel(_ direction: Direction) -> some View {
        let totals = direction.totals(in: counters)
        let live = direction.liveRates(in: rates)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: direction.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(direction.tint)
                Text(direction.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text("now")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 4) {
                liveValue(KBFormat.bitRate(live.bytes))
                Text("·")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                liveValue(KBFormat.packetsRate(live.packets))
                Spacer(minLength: 0)
            }

            Divider().opacity(0.6)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                totalValue(KBFormat.totalBytes(totals.bytes))
                metricLabel("data")
                Text("·")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                totalValue(KBFormat.compactTotal(totals.packets))
                metricLabel("pkts")
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(direction.tint.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(direction.tint.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(direction == .input ? "Network input" : "Network output")
        .accessibilityValue(
            "Now \(KBFormat.bitRate(live.bytes)), \(KBFormat.packetsRate(live.packets)). " +
            "\(KBFormat.totalBytes(totals.bytes)) data, " +
            "\(KBFormat.compactTotal(totals.packets)) packets since boot."
        )
    }

    private var accessibilityValue: String {
        let input = Direction.input.totals(in: counters)
        let output = Direction.output.totals(in: counters)
        let inputLive = Direction.input.liveRates(in: rates)
        let outputLive = Direction.output.liveRates(in: rates)

        return "Input now \(KBFormat.bitRate(inputLive.bytes)), " +
            "\(KBFormat.packetsRate(inputLive.packets)); since boot " +
            "\(KBFormat.totalBytes(input.bytes)) data, " +
            "\(KBFormat.compactTotal(input.packets)) packets. " +
            "Output now \(KBFormat.bitRate(outputLive.bytes)), " +
            "\(KBFormat.packetsRate(outputLive.packets)); since boot " +
            "\(KBFormat.totalBytes(output.bytes)) data, " +
            "\(KBFormat.compactTotal(output.packets)) packets."
    }
}
