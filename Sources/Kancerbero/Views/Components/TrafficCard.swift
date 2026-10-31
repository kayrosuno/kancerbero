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

    /// Title and unit selector with the two direction chips centered in the
    /// same top line. In narrow cards the chips move to a second row.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            ZStack {
                titleAndSelector
                directionChips(showsLabel: true)
            }
            .frame(height: 24)
            .frame(minWidth: 700)

            VStack(spacing: 4) {
                titleAndSelector
                    .frame(height: 22)
                directionChips(showsLabel: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
            }
        }
    }

    private var titleAndSelector: some View {
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

    private func directionChips(showsLabel: Bool) -> some View {
        HStack(spacing: 8) {
            directionChip(.download, showsLabel: showsLabel)
            directionChip(.upload, showsLabel: showsLabel)
        }
    }

    private func directionChip(_ direction: NetworkingFocus,
                               showsLabel: Bool) -> some View {
        let isDownload = direction == .download
        let tint = isDownload ? KBTheme.downloadTint : KBTheme.uploadTint
        let selected = focus == direction
        let bits = isDownload ? downloadValue : uploadValue
        let packets = KBFormat.packetsRate(isDownload
            ? downloadPacketsPerSecond
            : uploadPacketsPerSecond)
        let label = isDownload ? "Download" : "Upload"
        let packetLabel = isDownload ? "in" : "out"
        let bitsActive = graphMode == .bits

        return Button {
            onToggle(direction)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isDownload
                      ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint)
                if showsLabel {
                    Text(label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(bits)
                    .font(.system(size: 10,
                                  weight: bitsActive ? .semibold : .medium,
                                  design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(bitsActive
                                     ? Color.primary
                                     : Color.secondary.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                Text("·")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                Text(packets)
                    .font(.system(size: 10,
                                  weight: bitsActive ? .medium : .semibold,
                                  design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(bitsActive
                                     ? Color.secondary.opacity(0.55)
                                     : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(width: showsLabel ? 214 : 160, height: 20, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(selected ? 0.14 : 0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.9) : tint.opacity(0.16),
                                  lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isDownload ? "Show rows with receive traffic"
                         : "Show rows with send traffic")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(bits), packets \(packetLabel) \(packets)")
        .accessibilityHint(isDownload ? "Toggle receive traffic filter"
                                      : "Toggle send traffic filter")
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
