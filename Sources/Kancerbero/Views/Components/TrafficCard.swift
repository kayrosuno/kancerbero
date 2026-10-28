import SwiftUI

struct TrafficCard: View {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    var sampleDates: [Date] = []
    let focus: NetworkingFocus?
    var sampleInterval: TimeInterval = 1
    let onToggle: (NetworkingFocus) -> Void

    static let cardHeight: CGFloat = 208
    private static let headerHeight: CGFloat = 38
    private static let metricWidth: CGFloat = 140

    private var downloadValue: String {
        KBFormat.bitRate(downloadBytesPerSecond)
    }

    private var uploadValue: String {
        KBFormat.bitRate(uploadBytesPerSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(
                                colors: [KBTheme.downloadTint, KBTheme.uploadTint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text("Traffic")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("bit rate")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                MetricTile(
                    layout: .inline,
                    title: "Download",
                    value: downloadValue,
                    icon: "arrow.down.circle.fill",
                    tint: KBTheme.downloadTint,
                    caption: "system-wide receive",
                    hint: "Show rows with receive traffic",
                    isSelected: focus == .download,
                    valueSize: 16,
                    valueMinWidth: 104,
                    valueScales: false,
                    verticalPadding: 3
                ) {
                    onToggle(.download)
                }
                .frame(width: Self.metricWidth)

                MetricTile(
                    layout: .inline,
                    title: "Upload",
                    value: uploadValue,
                    icon: "arrow.up.circle.fill",
                    tint: KBTheme.uploadTint,
                    caption: "system-wide send",
                    hint: "Show rows with send traffic",
                    isSelected: focus == .upload,
                    valueSize: 16,
                    valueMinWidth: 104,
                    valueScales: false,
                    verticalPadding: 3
                ) {
                    onToggle(.upload)
                }
                .frame(width: Self.metricWidth)
            }
            .frame(height: Self.headerHeight)

            TrafficChart(download: downloadHistory,
                         upload: uploadHistory,
                         focus: focus,
                         sampleInterval: sampleInterval,
                         sampleDates: sampleDates)
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
