import SwiftUI

struct TrafficCard: View {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    let focus: NetworkingFocus?
    let onToggle: (NetworkingFocus) -> Void

    private var downloadValue: String {
        KBFormat.bitRate(downloadBytesPerSecond)
    }

    private var uploadValue: String {
        KBFormat.bitRate(uploadBytesPerSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            HStack(spacing: 6) {
                metricButton(.download,
                             title: "Download",
                             icon: "arrow.down.circle.fill",
                             value: downloadValue,
                             tint: KBTheme.downloadTint,
                             caption: "system-wide receive",
                             hint: "Show rows with receive traffic")
                metricButton(.upload,
                             title: "Upload",
                             icon: "arrow.up.circle.fill",
                             value: uploadValue,
                             tint: KBTheme.uploadTint,
                             caption: "system-wide send",
                             hint: "Show rows with send traffic")
            }
            TrafficChart(download: downloadHistory,
                         upload: uploadHistory,
                         focus: focus)
                .frame(height: 56)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("Traffic")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text("bit rate")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func metricButton(_ value: NetworkingFocus, title: String,
                              icon: String, value text: String, tint: Color,
                              caption: String, hint: String) -> some View {
        let isSelected = focus == value
        return Button {
            onToggle(value)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(isSelected ? 0.14 : 0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.9) : tint.opacity(0.18),
                                  lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(text), \(caption)")
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(hint)
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
