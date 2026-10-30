import SwiftUI
import KancerberoCore

struct CPUView: View {
    @Environment(AppModel.self) private var model

    private let cpuTint = Color(red: 0.20, green: 0.72, blue: 0.52)
    private let loadTint = Color(red: 0.94, green: 0.56, blue: 0.18)

    private let userColor = KBTheme.downloadTint
    private let systemColor = Color(red: 0.94, green: 0.56, blue: 0.18)
    private let niceColor = KBTheme.uploadTint
    private let idleColor = Color.gray.opacity(0.28)
    private let gpuTint = Color(red: 0.36, green: 0.50, blue: 0.95)

    @State private var showCPUDetails = false
    @State private var showCoresDetails = false
    @State private var showGPUDetails = false

    var body: some View {
        VStack(spacing: 14) {
            SectionHeader(title: "CPU",
                          subtitle: "Cores, load, memory and processes")

            VStack(spacing: 14) {
                topGroups
                    .frame(height: KBTheme.cardStripHeight)
                processCard
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, KBTheme.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Top card groups

    private var topGroups: some View {
        HStack(alignment: .top, spacing: 14) {
            HStack(spacing: 10) {
                cpuCard
                    .frame(minWidth: 165, idealWidth: 180, maxWidth: 195)
                loadTasksCard
                    .frame(minWidth: 110, idealWidth: 120, maxWidth: 140)
                coresCard
            }
            .frame(maxWidth: .infinity)

            gpuCard
                .frame(width: 185)

            PhysicalMemoryCard()
                .frame(width: 185)
        }
    }

    /// Compact card used in the top strip. The content area flexes so a chart
    /// can fill the remaining height.
    private func statCard<Content: View>(title: String,
                                         value: String,
                                         caption: String? = nil,
                                         systemImage: String,
                                         tint: Color,
                                         accessory: String? = nil,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(KBTheme.gradient(tint))
                    }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .layoutPriority(1)

                if let accessory {
                    Text(accessory)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
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

    // MARK: - Cards

    private var cpuCard: some View {
        let cpu = model.hostMetrics?.cpu
        return Button {
            showCPUDetails = true
        } label: {
            statCard(title: "CPU",
                     value: cpu.map { KBFormat.usagePercent($0.totalUsagePercent) } ?? "—",
                     caption: cpu == nil ? "Waiting for metrics" : nil,
                     systemImage: "cpu",
                     tint: cpuTint,
                     accessory: cpu.map {
                         "idle \(KBFormat.usagePercent($0.idlePercent))"
                     }) {
                if let cpu {
                    VStack(alignment: .leading, spacing: 6) {
                        breakdownInlineRow(cpu)
                        CPUHistoryChart(user: model.cpuUserHistory,
                                        system: model.cpuSystemHistory,
                                        nice: model.cpuNiceHistory,
                                        userColor: userColor,
                                        systemColor: systemColor,
                                        niceColor: niceColor,
                                        freeColor: idleColor)
                            .frame(minHeight: 56, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Color.clear
                }
            }
        }
        .buttonStyle(.plain)
        .help("CPU history and core details")
        .popover(isPresented: $showCPUDetails, arrowEdge: .bottom) {
            cpuDetails
                .padding(16)
                .frame(width: 560)
        }
    }

    private var loadTasksCard: some View {
        let cpu = model.hostMetrics?.cpu
        return statCard(title: "Load & tasks",
                        value: cpu.map { KBFormat.load($0.load1) } ?? "—",
                        caption: cpu.map {
                            "5m \(KBFormat.load($0.load5)) · 15m \(KBFormat.load($0.load15))"
                        } ?? "—",
                        systemImage: "waveform.path",
                        tint: loadTint) {
            if let cpu {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(cpu.taskCount.formatted()) tasks")
                        .font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 4) {
                        Text("\(cpu.threadCount.formatted()) threads")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        if cpu.threadsRestricted > 0 {
                            Text("partial")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                                .help("\(cpu.threadsRestricted) processes belong to other users or come from a daemon that predates the full process enumeration. Their CPU, memory and thread counters are unavailable; installing the current build and repairing the background service restores them.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Color.clear
            }
        }
    }

    private var coresCard: some View {
        let cpu = model.hostMetrics?.cpu
        return Button {
            showCoresDetails = true
        } label: {
            coresCompactCard(cpu)
        }
        .buttonStyle(.plain)
        .help("Per-core usage")
        .popover(isPresented: $showCoresDetails, arrowEdge: .bottom) {
            coresDetails
                .padding(16)
                .frame(width: 560)
        }
    }

    private func coresCompactCard(_ cpu: KBCPUStats?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(KBTheme.gradient(cpuTint))
                    }
                Text("Cores")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                ViewThatFits(in: .horizontal) {
                    coreSegmentLegend
                    EmptyView()
                }
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if let cpu {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(cpu.coreCount) cores")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("avg \(KBFormat.usagePercent(cpu.totalUsagePercent))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                compactCoreGrid(cpu)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cpuTint.opacity(0.22), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Two-column core grid that stretches its rows to fill the card. The bar
    /// height grows when there are fewer rows, so an 8-core Mac gets visibly
    /// bigger meters than a 12-core one.
    private func compactCoreGrid(_ cpu: KBCPUStats) -> some View {
        let cores = Array(cpu.cores.prefix(12))
        let rows = stride(from: 0, to: cores.count, by: 2).map {
            Array(cores[$0..<min($0 + 2, cores.count)])
        }
        let rowCount = max(rows.count, 1)
        let meterHeight: CGFloat = rowCount >= 6 ? 15 : (rowCount == 5 ? 16 : 20)

        return VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(rows[rowIndex]) { core in
                        compactCoreRow(core, meterHeight: meterHeight)
                            .frame(maxWidth: .infinity)
                    }
                    if rows[rowIndex].count < 2 {
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactCoreRow(_ core: KBCoreCPU, meterHeight: CGFloat) -> some View {
        let meter = SegmentedMeter(
            segments: [
                MeterSegment(id: "System", value: core.systemPercent, color: systemColor),
                MeterSegment(id: "User", value: core.userPercent, color: userColor),
                MeterSegment(id: "Nice", value: core.nicePercent, color: niceColor),
                MeterSegment(id: "Idle", value: core.idlePercent, color: idleColor)
            ],
            height: meterHeight,
            accessibilityLabel: "CPU \(core.index + 1)"
        )
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                coreIndexLabel(core)
                meter
                corePercentLabel(core)
            }
            HStack(spacing: 4) {
                coreIndexLabel(core)
                meter
            }
            meter
        }
    }

    private func coreIndexLabel(_ core: KBCoreCPU) -> some View {
        Text("\(core.index + 1)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 12, alignment: .trailing)
    }

    private func corePercentLabel(_ core: KBCoreCPU) -> some View {
        Text(KBFormat.usagePercent(core.usagePercent))
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(core.usagePercent > 85 ? .orange : .secondary)
            .frame(width: 32, alignment: .trailing)
    }

    private var coreSegmentLegend: some View {
        HStack(spacing: 6) {
            legendDot("System", color: systemColor)
            legendDot("User", color: userColor)
            legendDot("Nice", color: niceColor)
            legendDot("Idle", color: idleColor)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }

    private var gpuCard: some View {
        let gpu = model.hostMetrics?.gpu
        let available = gpu?.utilizationPercent != nil
        return Button {
            showGPUDetails = true
        } label: {
            statCard(title: "GPU",
                     value: available
                        ? KBFormat.usagePercent(gpu?.utilizationPercent ?? 0)
                        : "—",
                     caption: gpuCaption(gpu),
                     systemImage: "display",
                     tint: gpuTint) {
                if available {
                    Sparkline(values: model.gpuUsageHistory, tint: gpuTint)
                } else {
                    Color.clear
                }
            }
        }
        .buttonStyle(.plain)
        .help("GPU utilisation and memory")
        .popover(isPresented: $showGPUDetails, arrowEdge: .bottom) {
            gpuDetails
                .padding(16)
                .frame(width: 460)
        }
    }

    private func gpuCaption(_ gpu: KBGPUStats?) -> String {
        guard let gpu, gpu.utilizationPercent != nil else { return "Unavailable" }
        let name = gpu.name ?? "GPU"
        if let bytes = gpu.inUseMemoryBytes {
            return "\(name) · \(KBFormat.bytes(bytes))"
        }
        return name
    }

    // MARK: - Popover details

    private var cpuDetails: some View {
        let cpu = model.hostMetrics?.cpu
        return VStack(alignment: .leading, spacing: 10) {
            Text("CPU history")
                .font(.system(size: 14, weight: .semibold))

            if let cpu {
                CPUHistoryChart(user: model.cpuUserHistory,
                                system: model.cpuSystemHistory,
                                nice: model.cpuNiceHistory,
                                userColor: userColor,
                                systemColor: systemColor,
                                niceColor: niceColor,
                                freeColor: idleColor)
                    .frame(height: 200)

                MeterLegend(items: [
                    MeterLegendItem("System", value: KBFormat.usagePercent(cpu.systemPercent),
                                    color: systemColor),
                    MeterLegendItem("User", value: KBFormat.usagePercent(cpu.userPercent),
                                    color: userColor),
                    MeterLegendItem("Nice", value: KBFormat.usagePercent(cpu.nicePercent),
                                    color: niceColor),
                    MeterLegendItem("Free", value: KBFormat.usagePercent(cpu.idlePercent),
                                    color: idleColor)
                ], minItemWidth: 110)

                HStack {
                    Text("\(model.cpuUserHistory.count) samples · fixed 0–100% scale")
                    Spacer()
                    Text("Uptime \(KBFormat.uptime(cpu.uptimeSeconds))")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            } else {
                Text("Waiting for metrics…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var coresDetails: some View {
        let cpu = model.hostMetrics?.cpu
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("CPU cores")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let cpu {
                    Text("\(cpu.coreCount) cores")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let cpu {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)],
                          alignment: .leading,
                          spacing: 6) {
                    ForEach(cpu.cores) { core in
                        coreRow(core)
                    }
                }

                if cpu.threadsRestricted > 0 {
                    Label("\(cpu.threadsRestricted) restricted",
                          systemImage: "lock.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .help("Threads of other users require the root daemon.")
                }

                Divider().opacity(0.4)

                MeterLegend(items: [
                    MeterLegendItem("System", value: KBFormat.usagePercent(cpu.systemPercent),
                                    color: systemColor),
                    MeterLegendItem("User", value: KBFormat.usagePercent(cpu.userPercent),
                                    color: userColor),
                    MeterLegendItem("Nice", value: KBFormat.usagePercent(cpu.nicePercent),
                                    color: niceColor),
                    MeterLegendItem("Idle", value: KBFormat.usagePercent(cpu.idlePercent),
                                    color: idleColor)
                ], minItemWidth: 110)

                HStack {
                    Label("Uptime \(KBFormat.uptime(cpu.uptimeSeconds))",
                          systemImage: "clock")
                    Spacer()
                    Text("\(cpu.taskCount) tasks · \(cpu.threadCount) threads")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            } else {
                Text("Waiting for metrics…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gpuDetails: some View {
        let gpu = model.hostMetrics?.gpu
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("GPU")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(gpu?.name ?? "GPU")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let gpu, let utilization = gpu.utilizationPercent {
                HStack(spacing: 18) {
                    gpuMetric("Utilization", KBFormat.usagePercent(utilization))
                    gpuMetric("Renderer",
                              gpu.rendererPercent.map { KBFormat.usagePercent($0) } ?? "—")
                    gpuMetric("Tiler",
                              gpu.tilerPercent.map { KBFormat.usagePercent($0) } ?? "—")
                }

                Sparkline(values: model.gpuUsageHistory, tint: gpuTint)
                    .frame(height: 150)

                Divider().opacity(0.4)

                HStack {
                    Text("Memory in use")
                    Spacer()
                    Text(gpu.inUseMemoryBytes.map { KBFormat.bytes($0) } ?? "—")
                        .monospacedDigit()
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                HStack {
                    Text("Allocated")
                    Spacer()
                    Text(gpu.allocatedMemoryBytes.map { KBFormat.bytes($0) } ?? "—")
                        .monospacedDigit()
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                Text("Source: IOAccelerator PerformanceStatistics.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            } else {
                Text("This Mac does not expose GPU statistics through IOAccelerator.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func gpuMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    // MARK: - Small building blocks

    private func breakdownInlineRow(_ cpu: KBCPUStats) -> some View {
        HStack(spacing: 6) {
            breakdownInlineItem("User", value: cpu.userPercent, color: userColor)
            breakdownInlineItem("System", value: cpu.systemPercent, color: systemColor)
            if cpu.nicePercent > 0.05 {
                breakdownInlineItem("Nice", value: cpu.nicePercent, color: niceColor)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private func breakdownInlineItem(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(KBFormat.usagePercent(value))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
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
                    MeterSegment(id: "System", value: core.systemPercent, color: systemColor),
                    MeterSegment(id: "User", value: core.userPercent, color: userColor),
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

    // MARK: - Processes

    private var processCard: some View {
        CPUProcessTable(rows: model.cpuProcessRows)
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
