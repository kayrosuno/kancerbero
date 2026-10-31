import SwiftUI

struct TrafficCard: View {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let downloadPacketsPerSecond: Double
    let uploadPacketsPerSecond: Double
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

    private var downloadValue: String {
        KBFormat.bitRate(downloadBytesPerSecond)
    }

    private var uploadValue: String {
        KBFormat.bitRate(uploadBytesPerSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                headerRow
                    .frame(height: 22)
                downloadUploadRow
                    .frame(height: 22)
                packetRow
                    .frame(height: 18)
            }

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

    private var headerRow: some View {
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

            Spacer(minLength: 4)

            Picker("Traffic graph units", selection: $graphMode) {
                ForEach(TrafficGraphMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 124)
            .accessibilityLabel("Traffic graph units")
            .help("Show the graph in bits per second or packets per second")
        }
    }

    private var downloadUploadRow: some View {
        HStack(spacing: 6) {
            MetricTile(
                layout: .compact,
                title: "Download",
                value: downloadValue,
                icon: "arrow.down.circle.fill",
                tint: KBTheme.downloadTint,
                hint: "Show rows with receive traffic",
                isSelected: focus == .download,
                valueSize: 13,
                valueMinWidth: 0,
                valueScales: true,
                iconSize: 10,
                verticalPadding: 2
            ) {
                onToggle(.download)
            }
            .frame(maxWidth: .infinity)

            MetricTile(
                layout: .compact,
                title: "Upload",
                value: uploadValue,
                icon: "arrow.up.circle.fill",
                tint: KBTheme.uploadTint,
                hint: "Show rows with send traffic",
                isSelected: focus == .upload,
                valueSize: 13,
                valueMinWidth: 0,
                valueScales: true,
                iconSize: 10,
                verticalPadding: 2
            ) {
                onToggle(.upload)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var packetRow: some View {
        HStack(spacing: 6) {
            packetCell(icon: "arrow.down.circle",
                       label: "Pkts in",
                       value: KBFormat.packetsRate(downloadPacketsPerSecond),
                       tint: KBTheme.downloadTint)
                .frame(maxWidth: .infinity)
            packetCell(icon: "arrow.up.circle",
                       label: "Pkts out",
                       value: KBFormat.packetsRate(uploadPacketsPerSecond),
                       tint: KBTheme.uploadTint)
                .frame(maxWidth: .infinity)
        }
    }

    private func packetCell(icon: String, label: String, value: String,
                            tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
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
