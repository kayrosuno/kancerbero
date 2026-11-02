import SwiftUI
import KancerberoCore

struct TrafficCard: View {
    let rates: KBRates
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    let downloadPacketHistory: [Double]
    let uploadPacketHistory: [Double]
    let focus: NetworkingFocus?
    var sampleInterval: TimeInterval = 1
    @Binding var graphMode: TrafficGraphMode
    let onToggle: (NetworkingFocus) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let cardHeight: CGFloat = 190

    private enum LegendLayout {
        static let legendSpacing: CGFloat = 10
        static let entryPaddingH: CGFloat = 5
        static let entryPaddingV: CGFloat = 2
        /// Fixed value width so changing rates never move the legend.
        static let valueWidth: CGFloat = 64
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            TrafficChart(
                download: graphMode == .bits ? downloadHistory : downloadPacketHistory,
                upload: graphMode == .bits ? uploadHistory : uploadPacketHistory,
                focus: focus,
                sampleInterval: sampleInterval,
                mode: graphMode,
                downloadTint: KBTheme.netDownloadTint,
                uploadTint: KBTheme.netUploadTint
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.cardHeight)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(borderStyle, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                titleBlock
                    .fixedSize(horizontal: true, vertical: false)
                legendEntries
                Spacer(minLength: 8)
                TrafficModeSelector(mode: $graphMode)
            }
            .frame(minWidth: 430)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    titleBlock
                    Spacer(minLength: 4)
                    TrafficModeSelector(mode: $graphMode)
                }
                legendEntries
            }
        }
    }

    private var legendEntries: some View {
        HStack(spacing: LegendLayout.legendSpacing) {
            legend(.upload)
            legend(.download)
        }
    }

    private func legend(_ direction: NetworkingFocus) -> some View {
        let isDownload = direction == .download
        let name = isDownload ? "Download" : "Upload"
        let tint = isDownload ? KBTheme.netDownloadTint : KBTheme.netUploadTint
        let selected = focus == direction
        let bitRate = KBFormat.bitRate(isDownload ? rates.rxBytesPerSecond
                                                 : rates.txBytesPerSecond)
        let packetRate = KBFormat.packetsRate(isDownload ? rates.rxPacketsPerSecond
                                                         : rates.txPacketsPerSecond)
        let value = graphMode == .bits ? bitRate : packetRate

        return Button {
            onToggle(direction)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: LegendLayout.valueWidth, alignment: .leading)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            .padding(.horizontal, LegendLayout.entryPaddingH)
            .padding(.vertical, LegendLayout.entryPaddingV)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.12))
                }
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(name) rates: \(bitRate) · \(packetRate)")
        .accessibilityLabel("\(name) rates, \(bitRate), \(packetRate)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(isDownload ? "Toggle receive traffic focus filter"
                                      : "Toggle send traffic focus filter")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var titleBlock: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(
                            colors: [KBTheme.netDownloadTint, KBTheme.netUploadTint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                }

            Text("Traffic")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var borderStyle: AnyShapeStyle {
        if focus == .download {
            return AnyShapeStyle(KBTheme.netDownloadTint.opacity(0.8))
        }
        if focus == .upload {
            return AnyShapeStyle(KBTheme.netUploadTint.opacity(0.8))
        }
        return AnyShapeStyle(LinearGradient(
            colors: [KBTheme.netDownloadTint.opacity(0.32),
                     KBTheme.netUploadTint.opacity(0.32)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing))
    }
}
