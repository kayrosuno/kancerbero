import SwiftUI
import KancerberoCore

struct TrafficCard: View {
    let rates: KBRates
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

    private enum RateMetric {
        case bytes
        case packets

        var title: String {
            self == .bytes ? "Bytes" : "Packets"
        }

        var groupWidth: CGFloat {
            self == .bytes ? 196 : 208
        }

        var titleWidth: CGFloat {
            self == .bytes ? 34 : 46
        }

        var valueWidth: CGFloat {
            56
        }

        func value(for direction: NetworkingFocus, in rates: KBRates) -> String {
            let isDownload = direction == .download
            switch self {
            case .bytes:
                return KBFormat.bitRate(isDownload
                    ? rates.rxBytesPerSecond
                    : rates.txBytesPerSecond)
            case .packets:
                return KBFormat.packetsRate(isDownload
                    ? rates.rxPacketsPerSecond
                    : rates.txPacketsPerSecond)
            }
        }
    }

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
            HStack(spacing: 6) {
                titleBlock
                rateGroup(.bytes)
                rateGroup(.packets)
                Spacer(minLength: 8)
                TrafficModeSelector(mode: $graphMode)
            }
            .frame(minWidth: 630)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    titleBlock
                    Spacer(minLength: 4)
                    TrafficModeSelector(mode: $graphMode)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        rateGroup(.bytes)
                        rateGroup(.packets)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        rateGroup(.bytes)
                        rateGroup(.packets)
                    }
                }
            }
        }
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

    private func rateGroup(_ metric: RateMetric) -> some View {
        let active = (metric == .bytes) == (graphMode == .bits)

        return HStack(spacing: 4) {
            Text(metric.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(width: metric.titleWidth, alignment: .leading)

            rateItem(metric, .download, active: active)
            rateItem(metric, .upload, active: active)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: metric.groupWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(active ? Color.accentColor.opacity(0.12)
                             : Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(active ? Color.accentColor.opacity(0.35)
                                     : Color.primary.opacity(0.12),
                              lineWidth: 1)
        }
        .opacity(active ? 1 : 0.7)
        .animation(.snappy(duration: 0.2), value: active)
    }

    private func rateItem(_ metric: RateMetric,
                          _ direction: NetworkingFocus,
                          active: Bool) -> some View {
        let isDownload = direction == .download
        let tint = isDownload ? KBTheme.downloadTint : KBTheme.uploadTint
        let selected = focus == direction
        let value = metric.value(for: direction, in: rates)

        return Button {
            onToggle(direction)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isDownload ? "arrow.down" : "arrow.up")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 8)
                    .accessibilityHidden(true)
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: metric.valueWidth, alignment: .leading)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
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
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isDownload ? "Show rows with receive traffic"
                         : "Show rows with send traffic")
        .accessibilityLabel("\(metric.title) "
                            + (isDownload ? "download" : "upload") + ", \(value)")
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
