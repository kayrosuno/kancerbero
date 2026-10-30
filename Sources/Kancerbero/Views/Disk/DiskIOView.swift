import SwiftUI
import KancerberoCore

/// Disk activity (read/write graph and counters) plus per-process disk usage.
struct DiskIOView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    private let readTint = Color(red: 0.94, green: 0.56, blue: 0.18)
    private let writeTint = KBTheme.uploadTint

    var body: some View {
        GeometryReader { proxy in
            let topHeight = max(210, (proxy.size.height - 14) / 3)
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    activityCard
                        .frame(maxWidth: .infinity)
                    statsCard
                        .frame(width: 300)
                }
                .frame(height: topHeight)

                processCard
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
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
            HStack(alignment: .center, spacing: 10) {
                Text("Disk activity")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
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

            DiskIOChart(mode: ui.disk.ioGraphMode,
                        read: isData ? model.diskReadHistory : model.diskReadOpsHistory,
                        write: isData ? model.diskWriteHistory : model.diskWriteOpsHistory,
                        readColor: readTint,
                        writeColor: writeTint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 14) {
                legend("Read", value: isData
                       ? KBFormat.byteRate(model.diskReadRate)
                       : KBFormat.opsRate(model.diskReadOpsRate),
                       color: readTint)
                legend("Write", value: isData
                       ? KBFormat.byteRate(model.diskWriteRate)
                       : KBFormat.opsRate(model.diskWriteOpsRate),
                       color: writeTint)
                Spacer()
                Text("Last \(max(model.diskHistoryCount, 0)) samples")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
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
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Disk statistics")
                .font(.system(size: 12, weight: .semibold))

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading,
                      spacing: 10) {
                metric("Reads in/sec", KBFormat.opsRate(model.diskReadOpsRate))
                metric("Writes out/sec", KBFormat.opsRate(model.diskWriteOpsRate))
                metric("Data read/sec", KBFormat.byteRate(model.diskReadRate))
                metric("Data written/sec", KBFormat.byteRate(model.diskWriteRate))
                metric("Reads in", model.diskReadOperationsTotal.formatted())
                metric("Writes out", model.diskWriteOperationsTotal.formatted())
                metric("Data read", KBFormat.bytes(model.diskReadTotalBytes))
                metric("Data written", KBFormat.bytes(model.diskWriteTotalBytes))
            }

            Spacer(minLength: 0)
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

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
