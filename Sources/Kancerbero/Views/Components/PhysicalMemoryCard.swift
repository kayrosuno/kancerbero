import SwiftUI
import KancerberoCore

/// Physical memory card shared by the Memory and CPU tabs. It shows the
/// Activity Monitor "memory used" figure and opens a popover with the used
/// history and the app/wired/compressed/cached breakdown.
struct PhysicalMemoryCard: View {
    @Environment(AppModel.self) private var model
    @State private var showDetails = false

    private let tint = Color(red: 0.20, green: 0.70, blue: 0.62)

    var body: some View {
        Button {
            showDetails = true
        } label: {
            content
        }
        .buttonStyle(.plain)
        .help("Memory used history and breakdown")
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            details
                .padding(16)
                .frame(width: 460)
        }
    }

    private var content: some View {
        let memory = model.hostMetrics?.memory
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                cardIcon("memorychip", tint: KBTheme.downloadTint)
                Text("Physical Memory")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                if let memory {
                    Text(KBFormat.bytes(memory.totalBytes))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            if let memory {
                headlineMetric("Memory Used",
                               KBFormat.bytes(memory.activityMonitorUsedBytes),
                               detail: "· \(KBFormat.percent(memory.activityMonitorUsedFraction))")
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.memoryUsageHistory.count > 1 {
                    Sparkline(values: model.memoryUsageHistory,
                              tint: tint,
                              scale: 100)
                        .frame(maxHeight: .infinity)
                } else {
                    Text("Collecting…")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            } else {
                Text("Waiting for metrics…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var details: some View {
        let memory = model.hostMetrics?.memory
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Physical Memory")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let memory {
                    Text(KBFormat.bytes(memory.totalBytes))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let memory {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(KBFormat.bytes(memory.activityMonitorUsedBytes)) used")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(KBFormat.percent(memory.activityMonitorUsedFraction))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }

                if model.memoryUsageHistory.count > 1 {
                    Sparkline(values: model.memoryUsageHistory,
                              tint: tint,
                              scale: 100)
                        .frame(height: 200)
                } else {
                    Text("Collecting…")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                }

                Divider().opacity(0.4)

                HStack(alignment: .top, spacing: 24) {
                    metric("App Memory", KBFormat.bytes(memory.appMemoryBytes))
                    metric("Wired Memory", KBFormat.bytes(memory.wiredBytes))
                    metric("Compressed", KBFormat.bytes(memory.compressedBytes))
                    metric("Cached Files", KBFormat.bytes(memory.cachedFileBytes))
                    Spacer(minLength: 0)
                }

                Text("Activity Monitor’s memory used: app, wired and compressed pages.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Waiting for metrics…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cardIcon(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(KBTheme.gradient(tint))
            }
            .accessibilityHidden(true)
    }

    /// Prominent figure for the Activity Monitor detail card.
    private func headlineMetric(_ label: String,
                                _ value: String,
                                detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
