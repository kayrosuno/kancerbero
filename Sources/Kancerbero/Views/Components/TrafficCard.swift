import SwiftUI

struct TrafficCard: View {
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    let downloadPacketHistory: [Double]
    let uploadPacketHistory: [Double]
    var sampleDates: [Date] = []
    let focus: NetworkingFocus?
    var sampleInterval: TimeInterval = 1
    @Binding var graphMode: TrafficGraphMode
    let onToggle: (NetworkingFocus) -> Void

    static let cardHeight: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            TrafficChart(
                download: graphMode == .bits ? downloadHistory : downloadPacketHistory,
                upload: graphMode == .bits ? uploadHistory : uploadPacketHistory,
                focus: focus,
                sampleInterval: sampleInterval,
                sampleDates: sampleDates,
                mode: graphMode
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            legend
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
        HStack(spacing: 8) {
            titleBlock
            TrafficModeSelector(mode: $graphMode)
            Spacer(minLength: 0)
        }
        .frame(height: 28)
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
                            colors: [KBTheme.downloadTint, KBTheme.uploadTint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                }

            Text("Traffic")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendButton(.download)
            legendButton(.upload)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
    }

    private func legendLabel(_ direction: NetworkingFocus) -> String {
        let isDownload = direction == .download
        switch graphMode {
        case .bits:
            return isDownload ? "Download" : "Upload"
        case .packets:
            return isDownload ? "Packets in" : "Packets out"
        }
    }

    private var legendUnit: String {
        graphMode == .bits ? "bps" : "pkt/s"
    }

    private func legendButton(_ direction: NetworkingFocus) -> some View {
        let isDownload = direction == .download
        let tint = isDownload ? KBTheme.downloadTint : KBTheme.uploadTint
        let selected = focus == direction
        let dimmed = focus != nil && !selected

        return Button {
            onToggle(direction)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(legendLabel(direction))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? tint : Color.secondary)
                    .lineLimit(1)
                Text(legendUnit)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 26, alignment: .leading)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.12))
                }
            }
            .overlay {
                if selected {
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                }
            }
            .opacity(dimmed ? 0.5 : 1)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isDownload ? "Show rows with receive traffic"
                         : "Show rows with send traffic")
        .accessibilityLabel("\(legendLabel(direction)), "
                            + (graphMode == .bits ? "bits per second"
                                                  : "packets per second"))
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(isDownload ? "Toggle receive traffic focus filter"
                                      : "Toggle send traffic focus filter")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var borderStyle: AnyShapeStyle {
        if focus == .download {
            return AnyShapeStyle(KBTheme.downloadTint.opacity(0.8))
        }
        if focus == .upload {
            return AnyShapeStyle(KBTheme.uploadTint.opacity(0.8))
        }
        return AnyShapeStyle(LinearGradient(
            colors: [KBTheme.downloadTint.opacity(0.32),
                     KBTheme.uploadTint.opacity(0.32)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing))
    }
}
