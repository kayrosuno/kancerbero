import SwiftUI
import KancerberoCore

/// Live upload/download rates plus cumulative interface totals, styled to
/// match `Disk statistics` in Disk → I/O.
struct NetworkStatisticsCard: View {
    let rates: KBRates
    let counters: KBCounters
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var statsHovering = false

    private let downloadTint = KBTheme.downloadTint
    private let uploadTint = KBTheme.uploadTint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            heroRows
            Spacer(minLength: 4)
            Rectangle()
                .fill(.quaternary.opacity(0.5))
                .frame(height: 1)
            totalsFooter
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [downloadTint.opacity(0.09), uploadTint.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [downloadTint.opacity(statsHovering ? 0.55 : 0.30),
                                 uploadTint.opacity(statsHovering ? 0.55 : 0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: statsHovering ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(statsHovering ? 0.16 : 0.06),
                radius: statsHovering ? 12 : 10,
                y: statsHovering ? 5 : 4)
        .contentShape(RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous))
        .onHover { hovering in
            guard !reduceMotion else { return }
            withAnimation(.snappy(duration: 0.2)) { statsHovering = hovering }
        }
        .accessibilityElement(children: .contain)
        .help("Current upload and download rates, plus cumulative byte and packet "
              + "totals since boot. Totals cover non-loopback, non-tunnel interfaces "
              + "and reset if an interface restarts.")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            cardIcon("network",
                     fill: LinearGradient(colors: [downloadTint, uploadTint],
                                          startPoint: .topLeading,
                                          endPoint: .bottomTrailing))
            Text("Network statistics")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            LiveDot(isLive: isLive)
                .accessibilityHidden(true)
            Text(isLive ? "live" : "paused")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network statistics")
        .accessibilityValue(isLive ? "Live" : "Paused")
    }

    // MARK: - Rates

    private var heroRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            rateRow(title: "Upload rate",
                    systemImage: "arrow.up",
                    bytesPerSecond: rates.txBytesPerSecond,
                    packetsPerSecond: rates.txPacketsPerSecond,
                    tint: uploadTint)
            rateRow(title: "Download rate",
                    systemImage: "arrow.down",
                    bytesPerSecond: rates.rxBytesPerSecond,
                    packetsPerSecond: rates.rxPacketsPerSecond,
                    tint: downloadTint)
        }
    }

    private func rateRow(title: String,
                         systemImage: String,
                         bytesPerSecond: Double,
                         packetsPerSecond: Double,
                         tint: Color) -> some View {
        let rate = KBFormat.bitRate(bytesPerSecond)
        let packets = KBFormat.packetsRate(packetsPerSecond)
        return HStack(spacing: 8) {
            cardIcon(systemImage,
                     fill: KBTheme.gradient(tint),
                     size: 24, cornerRadius: 7, glyphSize: 11)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(packets)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                Text(rate)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(KBTheme.rateHeat(bytesPerSecond, scheme: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(numericTransition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(rate), \(packets)")
        .help("\(title): \(rate) · \(packets)")
    }

    // MARK: - Totals

    private var totalsFooter: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                totalMetric("Bytes out",
                            value: KBFormat.totalBytes(counters.txBytes),
                            exact: "\(counters.txBytes.formatted()) bytes",
                            icon: "arrow.up.to.line",
                            tint: uploadTint)
                totalMetric("Bytes in",
                            value: KBFormat.totalBytes(counters.rxBytes),
                            exact: "\(counters.rxBytes.formatted()) bytes",
                            icon: "arrow.down.to.line",
                            tint: downloadTint)
            }
            HStack(spacing: 10) {
                totalMetric("Packets out",
                            value: KBFormat.compactTotal(counters.txPackets),
                            exact: "\(KBFormat.count(counters.txPackets)) packets",
                            icon: "number",
                            tint: uploadTint)
                totalMetric("Packets in",
                            value: KBFormat.compactTotal(counters.rxPackets),
                            exact: "\(KBFormat.count(counters.rxPackets)) packets",
                            icon: "number",
                            tint: downloadTint)
            }
        }
    }

    private func totalMetric(_ label: String, value: String, exact: String,
                             icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(numericTransition)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(exact) since boot")
        .help("\(label): \(exact)")
    }

    // MARK: - Helpers

    private var numericTransition: ContentTransition {
        reduceMotion ? .identity : .numericText()
    }

    private func cardIcon(_ systemImage: String,
                          fill: LinearGradient,
                          size: CGFloat = 18,
                          cornerRadius: CGFloat = 5,
                          glyphSize: CGFloat = 9) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            }
            .accessibilityHidden(true)
    }
}
