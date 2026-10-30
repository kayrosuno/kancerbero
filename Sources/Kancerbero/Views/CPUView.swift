import SwiftUI
import KancerberoCore

struct CPUView: View {
    @Environment(AppModel.self) private var model

    private let cpuTint = Color(red: 0.20, green: 0.72, blue: 0.52)
    private let loadTint = Color(red: 0.94, green: 0.56, blue: 0.18)
    private let memoryTint = Color(red: 0.20, green: 0.70, blue: 0.62)

    private let userColor = KBTheme.downloadTint
    private let systemColor = Color(red: 0.94, green: 0.56, blue: 0.18)
    private let niceColor = KBTheme.uploadTint
    private let idleColor = Color.gray.opacity(0.28)
    private let wiredColor = Color(red: 0.95, green: 0.42, blue: 0.30)
    private let compressedColor = Color(red: 0.72, green: 0.40, blue: 0.92)
    private let cachedColor = KBTheme.connectionsTint
    private let gpuTint = Color(red: 0.36, green: 0.50, blue: 0.95)

    @State private var showCPUDetails = false
    @State private var showCoresDetails = false
    @State private var showMemoryDetails = false
    @State private var showPressureDetails = false
    @State private var showGPUDetails = false

    var body: some View {
        VStack(spacing: 14) {
            SectionHeader(title: "CPU",
                          subtitle: "Cores, load, memory and processes")

            GeometryReader { proxy in
                // The card strip takes a bit under a third of the space below
                // the header; the process table keeps the rest. The 200 pt floor
                // is the smallest height at which every card still lays out
                // without clipping.
                let topHeight = max(200, (proxy.size.height - 14) / 3.2)
                VStack(spacing: 14) {
                    topGroups
                        .frame(height: topHeight)
                    processCard
                        .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
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

            HStack(spacing: 10) {
                memoryCard
                pressureCard
            }
            .frame(width: 420)
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
                Spacer(minLength: 2)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                Spacer(minLength: 2)
                Text("Cores")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
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

                VStack {
                    Spacer(minLength: 0)
                    compactCoreGrid(cpu)
                    Spacer(minLength: 0)
                }
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

    private func compactCoreGrid(_ cpu: KBCPUStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  alignment: .center,
                  spacing: 5) {
            ForEach(cpu.cores.prefix(12)) { core in
                HStack(spacing: 5) {
                    Text("\(core.index + 1)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 15, alignment: .trailing)
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
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var memoryCard: some View {
        let memory = model.hostMetrics?.memory
        return Button {
            showMemoryDetails = true
        } label: {
            statCard(title: "Memory",
                     value: memory.map { KBFormat.percent($0.usedFraction) } ?? "—",
                     caption: memory.map {
                         "\(KBFormat.bytes($0.usedBytes)) of \(KBFormat.bytes($0.totalBytes))"
                     } ?? "Waiting for metrics",
                     systemImage: "memorychip",
                     tint: memoryTint) {
                if let memory {
                    VStack(alignment: .leading, spacing: 6) {
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
                        Text("Cached \(KBFormat.bytes(memory.cachedBytes)) · Free \(KBFormat.bytes(memory.barFreeBytes))")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Color.clear
                }
            }
        }
        .buttonStyle(.plain)
        .help("Memory breakdown and swap")
        .popover(isPresented: $showMemoryDetails, arrowEdge: .bottom) {
            memoryDetails
                .padding(16)
                .frame(width: 460)
        }
    }

    private var pressureCard: some View {
        let memory = model.hostMetrics?.memory
        let hasPressure = memory?.pressurePercent != nil
        return Button {
            showPressureDetails = true
        } label: {
            statCard(title: "Pressure",
                     value: hasPressure ? (memory?.pressureLabel ?? "—") : "—",
                     caption: memory?.pressurePercent.map { "\($0)% pressure" } ?? "Not reported",
                     systemImage: "gauge.medium",
                     tint: pressureTint(memory?.pressureBand)) {
                if model.memoryPressureHistory.count > 1 {
                    MemoryPressureChart(values: model.memoryPressureHistory,
                                        levels: model.memoryPressureLevelHistory)
                } else {
                    Color.clear
                }
            }
        }
        .buttonStyle(.plain)
        .help("Memory pressure details")
        .popover(isPresented: $showPressureDetails, arrowEdge: .bottom) {
            pressureDetails
                .padding(16)
                .frame(width: 460)
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
                    MeterLegendItem("User", value: KBFormat.usagePercent(cpu.userPercent),
                                    color: userColor),
                    MeterLegendItem("System", value: KBFormat.usagePercent(cpu.systemPercent),
                                    color: systemColor),
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

    private var memoryDetails: some View {
        let memory = model.hostMetrics?.memory
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory & Swap")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let memory {
                    Text(KBFormat.bytes(memory.totalBytes))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let memory {
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
                ], minItemWidth: 120)

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
            } else {
                Text("Waiting for metrics…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pressureDetails: some View {
        let memory = model.hostMetrics?.memory
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Memory pressure")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let memory, memory.pressurePercent != nil {
                    Text(memory.pressureLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(pressureColor(memory.pressureBand))
                }
            }

            if let memory, let percent = memory.pressurePercent {
                Text("\(percent)% pressure · level \(memory.pressureLevel ?? 0)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                MemoryPressureChart(values: model.memoryPressureHistory,
                                    levels: model.memoryPressureLevelHistory)
                    .frame(height: 180)

                Text("Memory pressure is an indicator of the system’s ability to meet the memory requirements of the user’s activities. Higher memory pressure indicates that the system is reaching its limits, and performance may degrade.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Update the background daemon to report memory pressure.")
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

    private func pressureColor(_ band: KBMemoryStats.PressureBand) -> Color {
        switch band {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        case .unknown: return .secondary
        }
    }

    private func pressureTint(_ band: KBMemoryStats.PressureBand?) -> Color {
        guard let band else { return memoryTint }
        switch band {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        case .unknown: return memoryTint
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
