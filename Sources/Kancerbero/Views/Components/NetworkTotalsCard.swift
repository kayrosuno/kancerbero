import SwiftUI
import KancerberoCore

/// Cumulative interface totals, grouped by metric: bytes on top and packets
/// below, with Input/Output rows in each group.
struct NetworkTotalsCard: View {
    let counters: KBCounters

    private enum Direction {
        case input
        case output

        var shortTitle: String {
            self == .input ? "In" : "Out"
        }

        var icon: String {
            self == .input ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
        }

        var tint: Color {
            self == .input ? KBTheme.downloadTint : KBTheme.uploadTint
        }

        var accessibilityTitle: String {
            self == .input ? "Input" : "Output"
        }

        func totals(in counters: KBCounters) -> (bytes: UInt64, packets: UInt64) {
            self == .input
                ? (counters.rxBytes, counters.rxPackets)
                : (counters.txBytes, counters.txPackets)
        }
    }

    private enum Metric {
        case bytes
        case packets

        var title: String {
            self == .bytes ? "Bytes" : "Packets"
        }

        func total(for direction: Direction, in counters: KBCounters) -> String {
            let totals = direction.totals(in: counters)
            switch self {
            case .bytes: return KBFormat.totalBytes(totals.bytes)
            case .packets: return KBFormat.compactTotal(totals.packets)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(spacing: 6) {
                metricGroup(.bytes)
                metricGroup(.packets)
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
        .help("Cumulative interface totals since boot. Counters reset if an "
              + "interface restarts.")
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

            Text("Network")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 2)

            Text("since boot")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(height: 18)
    }

    private func totalRow(_ direction: Direction, metric: Metric) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: direction.icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(direction.tint)
                Text(direction.shortTitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 29, alignment: .leading)

            Text(metric.total(for: direction, in: counters))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    /// Static group chrome with the same subtle fill and border as an
    /// unselected `MetricTile`.
    private func metricGroup(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(metric.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("total")
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            totalRow(.input, metric: metric)
            totalRow(.output, metric: metric)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var accessibilityValue: String {
        "Bytes. \(metricDescription(.bytes, .input)) " +
            "\(metricDescription(.bytes, .output)) " +
            "Packets. \(metricDescription(.packets, .input)) " +
            "\(metricDescription(.packets, .output))"
    }

    private func metricDescription(_ metric: Metric,
                                   _ direction: Direction) -> String {
        "\(direction.accessibilityTitle) total " +
            "\(metric.total(for: direction, in: counters)) since boot."
    }
}
