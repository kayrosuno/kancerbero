import SwiftUI
import KancerberoCore

struct CPUView: View {
    @Environment(AppModel.self) private var model

    private let cpuTint = Color(red: 0.20, green: 0.72, blue: 0.52)
    private let loadTint = Color(red: 0.94, green: 0.56, blue: 0.18)
    private let taskTint = Color(red: 0.62, green: 0.42, blue: 0.95)
    private let memoryTint = Color(red: 0.20, green: 0.70, blue: 0.62)

    private let userColor = KBTheme.downloadTint
    private let systemColor = Color(red: 0.94, green: 0.56, blue: 0.18)
    private let niceColor = KBTheme.uploadTint
    private let idleColor = Color.gray.opacity(0.28)
    private let wiredColor = Color(red: 0.95, green: 0.42, blue: 0.30)
    private let compressedColor = Color(red: 0.72, green: 0.40, blue: 0.92)
    private let cachedColor = KBTheme.connectionsTint
    private let meterCardHeight: CGFloat = 190

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 14) {
            header(model: model)

            summaryGrid

            if let host = model.hostMetrics {
                HStack(alignment: .top, spacing: 12) {
                    coresCard(host.cpu)
                        .frame(minWidth: 360, maxWidth: .infinity)

                    memoryCard(host.memory)
                        .frame(minWidth: 250, idealWidth: 280, maxWidth: 300)
                }
            } else {
                unavailableCard
            }

            processCard
        }
        .padding(.horizontal, KBTheme.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func header(model: AppModel) -> some View {
        @Bindable var model = model

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CPU")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Cores, load, memory and processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("Interval")
                    .font(.body)
                    .lineLimit(1)
                    .fixedSize()

                Picker("Interval", selection: $model.interval) {
                    Text("0.5 s").tag(0.5)
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)
                .accessibilityLabel("Interval")
            }
            .fixedSize(horizontal: true, vertical: false)

            Toggle(isOn: $model.isPaused) {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .help(model.isPaused ? "Resume" : "Pause")

            Button {
                model.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh now")
        }
    }

    private var summaryGrid: some View {
        let host = model.hostMetrics
        let cpu = host?.cpu
        let memory = host?.memory

        return LazyVGrid(columns: KBTheme.summaryColumns, spacing: KBTheme.summaryGridSpacing) {
            SummaryCard(
                title: "CPU",
                value: cpu.map { KBFormat.usagePercent($0.totalUsagePercent) } ?? "—",
                caption: cpu.map {
                    "user \(KBFormat.usagePercent($0.userPercent)) · system \(KBFormat.usagePercent($0.systemPercent))"
                } ?? "Waiting for metrics",
                systemImage: "cpu",
                tint: cpuTint,
                sparkline: model.cpuUsageHistory
            )

            SummaryCard(
                title: "Load average",
                value: cpu.map { KBFormat.load($0.load1) } ?? "—",
                caption: cpu.map {
                    "5m \(KBFormat.load($0.load5)) · 15m \(KBFormat.load($0.load15))"
                } ?? "—",
                systemImage: "waveform.path",
                tint: loadTint,
                sparkline: model.loadHistory
            )

            SummaryCard(
                title: "Tasks",
                value: cpu.map { $0.taskCount.formatted() } ?? "—",
                caption: cpu.map { "\($0.threadCount.formatted()) threads" } ?? "—",
                systemImage: "square.stack.3d.up",
                tint: taskTint,
                sparkline: model.threadHistory
            )

            SummaryCard(
                title: "Memory",
                value: memory.map { KBFormat.percent($0.usedFraction) } ?? "—",
                caption: memory.map {
                    "\(KBFormat.bytes($0.usedBytes)) of \(KBFormat.bytes($0.totalBytes))"
                } ?? "—",
                systemImage: "memorychip",
                tint: memoryTint,
                sparkline: model.memoryUsageHistory
            )
        }
    }

    private func coresCard(_ cpu: KBCPUStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("CPU Cores")
                    .font(.system(size: 12, weight: .semibold))
                if cpu.threadsRestricted > 0 {
                    Label("\(cpu.threadsRestricted) restricted", systemImage: "lock.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                        .help("Threads of other users require the root daemon.")
                }
                Spacer()
                Text("\(cpu.coreCount) cores")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)],
                      alignment: .leading, spacing: 6) {
                ForEach(cpu.cores) { core in
                    coreRow(core)
                }
            }

            Divider().opacity(0.4)

            MeterLegend(items: [
                MeterLegendItem("User", value: KBFormat.usagePercent(cpu.userPercent),
                                color: userColor),
                MeterLegendItem("System", value: KBFormat.usagePercent(cpu.systemPercent),
                                color: systemColor),
                MeterLegendItem("Nice", value: KBFormat.usagePercent(cpu.nicePercent),
                                color: niceColor),
                MeterLegendItem("Idle", value: KBFormat.usagePercent(cpu.idlePercent),
                                color: idleColor)
            ])

            HStack(spacing: 10) {
                Label("Uptime \(KBFormat.uptime(cpu.uptimeSeconds))",
                      systemImage: "clock")
                Spacer()
                Text("\(cpu.taskCount) tasks · \(cpu.threadCount) threads")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: meterCardHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private func coreRow(_ core: KBCoreCPU) -> some View {
        HStack(spacing: 7) {
            Text("\(core.index + 1)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            SegmentedMeter(
                segments: [
                    MeterSegment(id: "User", value: core.userPercent, color: userColor),
                    MeterSegment(id: "System", value: core.systemPercent, color: systemColor),
                    MeterSegment(id: "Nice", value: core.nicePercent, color: niceColor),
                    MeterSegment(id: "Idle", value: core.idlePercent, color: idleColor)
                ],
                height: 8,
                accessibilityLabel: "CPU \(core.index + 1)"
            )

            Text(KBFormat.usagePercent(core.usagePercent))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(core.usagePercent > 85 ? .orange : .secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func memoryCard(_ memory: KBMemoryStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory & Swap")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(KBFormat.bytes(memory.totalBytes))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Memory")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(KBFormat.bytes(memory.usedBytes)) used · \(KBFormat.percent(memory.usedFraction))")
                    .font(.system(size: 10))
                    .monospacedDigit()
            }

            SegmentedMeter(
                segments: [
                    MeterSegment(id: "Active", value: Double(memory.activeBytes),
                                 color: userColor),
                    MeterSegment(id: "Wired", value: Double(memory.wiredBytes),
                                 color: wiredColor),
                    MeterSegment(id: "Compressed", value: Double(memory.compressedBytes),
                                 color: compressedColor),
                    MeterSegment(id: "Cached", value: Double(memory.cachedBytes),
                                 color: cachedColor),
                    MeterSegment(id: "Free", value: Double(memory.barFreeBytes),
                                 color: idleColor)
                ],
                height: 10,
                accessibilityLabel: "Memory"
            )

            MeterLegend(items: [
                MeterLegendItem("Active", value: KBFormat.bytes(memory.activeBytes),
                                color: userColor),
                MeterLegendItem("Wired", value: KBFormat.bytes(memory.wiredBytes),
                                color: wiredColor),
                MeterLegendItem("Compressed", value: KBFormat.bytes(memory.compressedBytes),
                                color: compressedColor),
                MeterLegendItem("Cached", value: KBFormat.bytes(memory.cachedBytes),
                                color: cachedColor),
                MeterLegendItem("Free", value: KBFormat.bytes(memory.barFreeBytes),
                                color: idleColor)
            ])

            Divider().opacity(0.4)

            HStack(alignment: .firstTextBaseline) {
                Text("Swap")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(KBFormat.bytes(memory.swapUsedBytes)) / \(KBFormat.bytes(memory.swapTotalBytes))")
                    .font(.system(size: 10))
                    .monospacedDigit()
            }

            CapacityBar(
                fraction: memory.swapUsedFraction,
                tint: memory.swapUsedFraction > 0.8 ? .red : compressedColor
            )

            HStack(spacing: 4) {
                Text(KBFormat.percent(memory.swapUsedFraction))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                if memory.swapEncrypted {
                    Label("Encrypted", systemImage: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: meterCardHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private var unavailableCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(model.usingDaemon
                 ? "The connected daemon does not report CPU and memory metrics. Update the daemon to see this tab."
                 : "Waiting for host metrics…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        }
    }

    private var processCard: some View {
        CPUProcessTable(rows: model.cpuProcessRows)
            .padding(8)
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
