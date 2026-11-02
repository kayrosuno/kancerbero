import SwiftUI
import KancerberoCore

/// Disk activity (read/write graph and counters) plus per-process disk usage.
struct DiskIOView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var statsHovering = false

    private let readTint = Color(red: 0.94, green: 0.56, blue: 0.18)
    private let writeTint = KBTheme.uploadTint

    var body: some View {
        VStack(spacing: 14) {
            if !ui.cardsCollapsed(for: .disk) {
                HStack(alignment: .top, spacing: 14) {
                    statsCard
                        .frame(width: 200)
                    activityCard
                        .frame(maxWidth: .infinity)
                }
                .frame(height: KBTheme.cardStripHeight)
                .transition(.opacity)
            }

            processCard
                .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var graphMode: Binding<DiskIOGraphMode> {
        Binding(
            get: { ui.disk.ioGraphMode },
            set: { ui.disk.ioGraphMode = $0 }
        )
    }

    private var activityCard: some View {
        let isData = ui.disk.ioGraphMode == .data
        return VStack(alignment: .leading, spacing: 8) {
            header(isData: isData)

            DiskIOChart(mode: ui.disk.ioGraphMode,
                        read: isData ? model.diskReadHistory : model.diskReadOpsHistory,
                        write: isData ? model.diskWriteHistory : model.diskWriteOpsHistory,
                        readColor: readTint,
                        writeColor: writeTint,
                        sampleInterval: model.interval)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private func header(isData: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                activityTitle
                legendEntries(isData: isData)
                Spacer(minLength: 8)
                sampleCount
                modePicker
            }
            .frame(minWidth: 620)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    activityTitle
                    Spacer(minLength: 4)
                    sampleCount
                    modePicker
                }
                legendEntries(isData: isData)
            }
        }
    }

    private var activityTitle: some View {
        HStack(spacing: 6) {
            cardIcon("chart.line.uptrend.xyaxis",
                     fill: LinearGradient(colors: [readTint, writeTint],
                                          startPoint: .topLeading,
                                          endPoint: .bottomTrailing))
            Text("Disk activity")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private var modePicker: some View {
        Picker("Graph", selection: graphMode) {
            ForEach(DiskIOGraphMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 180)
        .accessibilityLabel("Disk graph type")
    }

    private var sampleCount: some View {
        Text("Last \(max(model.diskHistoryCount, 0)) samples")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func legendEntries(isData: Bool) -> some View {
        HStack(spacing: 14) {
            legend("Read", value: isData
                   ? KBFormat.byteRate(model.diskReadRate)
                   : KBFormat.opsRate(model.diskReadOpsRate),
                   color: readTint)
            legend("Write", value: isData
                   ? KBFormat.byteRate(model.diskWriteRate)
                   : KBFormat.opsRate(model.diskWriteOpsRate),
                   color: writeTint)
        }
    }

    private func legend(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 60, alignment: .leading)
        }
    }

    // MARK: - Statistics card

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            statsHeader
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
                    colors: [readTint.opacity(0.09), writeTint.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [readTint.opacity(statsHovering ? 0.55 : 0.30),
                                 writeTint.opacity(statsHovering ? 0.55 : 0.30)],
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
        .help("Read/write throughput over the last 60 samples; cumulative totals since boot.")
    }

    private var statsHeader: some View {
        HStack(spacing: 6) {
            cardIcon("chart.bar.fill",
                     fill: LinearGradient(colors: [readTint, writeTint],
                                          startPoint: .topLeading,
                                          endPoint: .bottomTrailing))
            Text("Disk statistics")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            LiveDot(isLive: model.isLive)
                .accessibilityHidden(true)
            Text(model.isLive ? "live" : "paused")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk statistics")
        .accessibilityValue(model.isLive ? "Live" : "Paused")
    }

    private var heroRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            throughputRow(title: "Read rate",
                          systemImage: "arrow.up",
                          bytesPerSecond: model.diskReadRate,
                          opsPerSecond: model.diskReadOpsRate,
                          tint: readTint)
            throughputRow(title: "Write rate",
                          systemImage: "arrow.down",
                          bytesPerSecond: model.diskWriteRate,
                          opsPerSecond: model.diskWriteOpsRate,
                          tint: writeTint)
        }
    }

    private func throughputRow(title: String,
                               systemImage: String,
                               bytesPerSecond: Double,
                               opsPerSecond: Double,
                               tint: Color) -> some View {
        let rate = KBFormat.byteRate(bytesPerSecond)
        let ops = KBFormat.opsRate(opsPerSecond)
        return HStack(spacing: 8) {
            cardIcon(systemImage,
                     fill: KBTheme.gradient(tint),
                     size: 24, cornerRadius: 7, glyphSize: 11)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("ops \(ops)")
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
        .accessibilityValue("\(rate), \(ops) operations per second")
        .help("\(title): \(rate) · \(ops) ops/s")
    }

    private var totalsFooter: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                totalMetric("Reads in",
                            value: KBFormat.compactTotal(model.diskReadOperationsTotal),
                            exact: "\(KBFormat.count(model.diskReadOperationsTotal)) operations",
                            icon: "arrow.up.to.line",
                            tint: readTint)
                totalMetric("Writes out",
                            value: KBFormat.compactTotal(model.diskWriteOperationsTotal),
                            exact: "\(KBFormat.count(model.diskWriteOperationsTotal)) operations",
                            icon: "arrow.down.to.line",
                            tint: writeTint)
            }
            HStack(spacing: 10) {
                totalMetric("Data read",
                            value: KBFormat.totalBytes(model.diskReadTotalBytes),
                            exact: KBFormat.bytes(model.diskReadTotalBytes),
                            icon: "internaldrive",
                            tint: readTint)
                totalMetric("Data written",
                            value: KBFormat.totalBytes(model.diskWriteTotalBytes),
                            exact: KBFormat.bytes(model.diskWriteTotalBytes),
                            icon: "internaldrive",
                            tint: writeTint)
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

    private var processCard: some View {
        DiskIOProcessTable(rows: model.cpuProcessRows)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                    .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

private extension AppModel {
    var diskHistoryCount: Int {
        max(diskReadHistory.count, diskReadOpsHistory.count)
    }
}
