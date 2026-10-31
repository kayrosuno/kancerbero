import SwiftUI
import KancerberoCore

enum NetworkTotalsLayout: Equatable {
    case vertical
    case horizontal
}

/// Cumulative interface totals grouped by direction, modelled on Activity
/// Monitor's Network tab. The live rates live in the Traffic card chips.
struct NetworkTotalsCard: View {
    let counters: KBCounters
    var layout: NetworkTotalsLayout = .vertical

    private enum Direction {
        case input
        case output

        var title: String {
            self == .input ? "Input" : "Output"
        }

        func values(in counters: KBCounters) -> (bytes: UInt64, packets: UInt64) {
            self == .input
                ? (counters.rxBytes, counters.rxPackets)
                : (counters.txBytes, counters.txPackets)
        }

        var icon: String {
            self == .input ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
        }

        var tint: Color {
            self == .input ? KBTheme.downloadTint : KBTheme.uploadTint
        }
    }

    var body: some View {
        content
            .padding(9)
            .frame(maxWidth: .infinity,
                   maxHeight: layout == .vertical ? .infinity : nil,
                   alignment: .topLeading)
            .frame(height: layout == .horizontal ? 72 : nil)
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
            .help("Interface counters are cumulative since boot and reset if an interface restarts.")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Network totals")
            .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .vertical:
            VStack(alignment: .leading, spacing: 8) {
                header(showsBootInline: true)
                VStack(spacing: 6) {
                    directionPanel(.input)
                    directionPanel(.output)
                }
                .frame(maxHeight: .infinity)
            }
        case .horizontal:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    header(showsBootInline: false)
                    Text("since boot")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 130, alignment: .leading)

                Divider().frame(height: 44)

                VStack(spacing: 4) {
                    directionRow(.input)
                    directionRow(.output)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func header(showsBootInline: Bool) -> some View {
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
                    if showsBootInline {
                        Spacer(minLength: 2)
                        Text("since boot")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 4) {
                    Text("Network")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if showsBootInline {
                        Spacer(minLength: 2)
                        Text("since boot")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Text("Network")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .frame(height: 18)
    }

    /// Both totals share size, colour and a fixed value slot, so the labels do
    /// not jump when a longer byte or packet total arrives.
    private func metricRow(_ value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 80, alignment: .leading)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    /// Static, unselected twin of `MetricTile`: same radius, fill and border,
    /// but no button, checkmark or focus treatment.
    private func directionPanel(_ direction: Direction) -> some View {
        let values = direction.values(in: counters)

        return VStack(alignment: .leading, spacing: 2) {
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
            }

            metricRow(KBFormat.totalBytes(values.bytes), label: "data")
            metricRow(KBFormat.compactTotal(values.packets), label: "packets")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
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
            "\(KBFormat.totalBytes(values.bytes)) data, " +
            "\(KBFormat.compactTotal(values.packets)) packets since boot"
        )
    }

    /// Compact single-line variant for the full-width fallback below the strip.
    private func directionRow(_ direction: Direction) -> some View {
        let values = direction.values(in: counters)

        return HStack(spacing: 4) {
            Image(systemName: direction.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(direction.tint)
            Text(direction.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(KBFormat.totalBytes(values.bytes))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
                .contentTransition(.numericText())
            Text("data")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("·")
                .font(.system(size: 7))
                .foregroundStyle(.tertiary)
            Text(KBFormat.compactTotal(values.packets))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
                .contentTransition(.numericText())
            Text("pkts")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            "\(KBFormat.totalBytes(values.bytes)) data, " +
            "\(KBFormat.compactTotal(values.packets)) packets since boot"
        )
    }

    private var accessibilityValue: String {
        "Input \(KBFormat.totalBytes(counters.rxBytes)) data, " +
            "\(KBFormat.compactTotal(counters.rxPackets)) packets. " +
            "Output \(KBFormat.totalBytes(counters.txBytes)) data, " +
            "\(KBFormat.compactTotal(counters.txPackets)) packets since boot."
    }
}
