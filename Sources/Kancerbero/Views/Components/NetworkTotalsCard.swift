import SwiftUI
import KancerberoCore

enum NetworkTotalsLayout: Equatable {
    case vertical
    case horizontal
}

/// System-wide packet/byte rates and cumulative interface totals, modelled on
/// Activity Monitor's Network tab.
struct NetworkTotalsCard: View {
    let rates: KBRates
    let counters: KBCounters
    var layout: NetworkTotalsLayout = .vertical

    var body: some View {
        content
            .padding(9)
            .frame(maxWidth: .infinity,
                   maxHeight: layout == .vertical ? .infinity : nil,
                   alignment: .topLeading)
            .frame(height: layout == .horizontal ? 88 : nil)
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
            .accessibilityLabel("Network rates and totals")
            .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .vertical:
            VStack(alignment: .leading, spacing: 4) {
                header
                sectionLabel("RATES")
                valuesGrid(valueSize: 11, cells: rateCells)
                Divider().opacity(0.35)
                sectionLabel("TOTALS")
                valuesGrid(valueSize: 11, cells: totalCells)
                Spacer(minLength: 0)
            }
        case .horizontal:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    header
                    Text("since boot")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 110, alignment: .leading)

                Divider().frame(height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    sectionLabel("RATES")
                    valuesGrid(valueSize: 12, cells: rateCells)
                }

                Divider().frame(height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    sectionLabel("TOTALS")
                    valuesGrid(valueSize: 12, cells: totalCells)
                }
            }
        }
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
            if layout == .vertical {
                Text("since boot")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(height: 18)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private func valuesGrid(valueSize: CGFloat,
                            cells: [(icon: String, title: String, value: String, tint: Color)])
        -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                metricCell(cells[0], valueSize: valueSize)
                metricCell(cells[1], valueSize: valueSize)
            }
            HStack(spacing: 8) {
                metricCell(cells[2], valueSize: valueSize)
                metricCell(cells[3], valueSize: valueSize)
            }
        }
    }

    private func metricCell(_ cell: (icon: String, title: String, value: String, tint: Color),
                            valueSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: cell.icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(cell.tint)
                Text(cell.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(cell.value)
                .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rateCells: [(icon: String, title: String, value: String, tint: Color)] {
        [
            ("arrow.down.circle.fill", "Download",
             KBFormat.bitRate(rates.rxBytesPerSecond), KBTheme.downloadTint),
            ("arrow.up.circle.fill", "Upload",
             KBFormat.bitRate(rates.txBytesPerSecond), KBTheme.uploadTint),
            ("arrow.down.circle", "Pkts in",
             KBFormat.packetsRate(rates.rxPacketsPerSecond), KBTheme.downloadTint),
            ("arrow.up.circle", "Pkts out",
             KBFormat.packetsRate(rates.txPacketsPerSecond), KBTheme.uploadTint)
        ]
    }

    private var totalCells: [(icon: String, title: String, value: String, tint: Color)] {
        [
            ("arrow.down.circle", "Data in",
             KBFormat.totalBytes(counters.rxBytes), KBTheme.downloadTint),
            ("arrow.up.circle", "Data out",
             KBFormat.totalBytes(counters.txBytes), KBTheme.uploadTint),
            ("arrow.down.circle", "Pkts in",
             KBFormat.compactTotal(counters.rxPackets), KBTheme.downloadTint),
            ("arrow.up.circle", "Pkts out",
             KBFormat.compactTotal(counters.txPackets), KBTheme.uploadTint)
        ]
    }

    private var accessibilityValue: String {
        "Download \(KBFormat.bitRate(rates.rxBytesPerSecond)), " +
            "upload \(KBFormat.bitRate(rates.txBytesPerSecond)), " +
            "packets in \(KBFormat.packetsRate(rates.rxPacketsPerSecond)) per second, " +
            "packets out \(KBFormat.packetsRate(rates.txPacketsPerSecond)) per second. " +
            "Total data received \(KBFormat.totalBytes(counters.rxBytes)), " +
            "sent \(KBFormat.totalBytes(counters.txBytes)), " +
            "packets in \(KBFormat.compactTotal(counters.rxPackets)), " +
            "out \(KBFormat.compactTotal(counters.txPackets)) since boot."
    }
}
