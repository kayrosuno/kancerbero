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
        .help("Per-core usage and temperature")
        .popover(isPresented: $showCoresDetails, arrowEdge: .bottom) {
            coresDetails
                .padding(16)
                .frame(width: 560)
        }
    }

    private func coresCompactCard(_ cpu: KBCPUStats?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(KBTheme.gradient(cpuTint))
                    }
                Text("Cores")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if let cpu {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) {
                            Text("avg \(KBFormat.usagePercent(cpu.totalUsagePercent))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            packageTemperatureBadge(cpu)
                        }
                        packageTemperatureBadge(cpu)
                        EmptyView()
                    }
                }
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if let cpu {
                coreClusters(cpu)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private func packageTemperatureBadge(_ cpu: KBCPUStats) -> some View {
        let tint = KBTheme.temperatureTint(cpu.packageTemperatureCelsius)
        let value = cpu.packageTemperatureCelsius.map {
            "\(Int($0.rounded()))°C"
        } ?? "—"
        return HStack(spacing: 3) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 8, weight: .semibold))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
        .lineLimit(1)
        .help(cpu.packageTemperatureCelsius == nil
              ? "Temperature unavailable on this Mac"
              : "CPU package \(KBFormat.temperature(cpu.packageTemperatureCelsius)) · \(cpu.temperatureSource ?? "IOHID")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU package temperature")
        .accessibilityValue(cpu.packageTemperatureCelsius
                            .map { KBFormat.temperature($0) } ?? "unavailable")
    }

    /// Core grid grouped by performance level. Rows get a fixed height derived
    /// from the card strip so the performance and efficiency clusters line up
    /// even though they contain a different number of cores.
    private func coreClusters(_ cpu: KBCPUStats) -> some View {
        let visible = Array(cpu.cores.prefix(24))
        let split = CPUTopology.performanceCoreCount
            .map { min(max($0, 0), visible.count) } ?? 0
        var groups: [(title: String?, cores: [KBCoreCPU])]
        if split > 0, split < visible.count {
            groups = [("PERFORMANCE", Array(visible[0..<split])),
                      ("EFFICIENCY", Array(visible[split...]))]
        } else {
            groups = [(nil, visible)]
        }

        let columns = visible.count > 16 ? 3 : 2
        let sectionCount = groups.count
        let labelled = groups.contains { $0.title != nil }
        let totalRows = groups.reduce(0) {
            $0 + Int((Double($1.cores.count) / Double(columns)).rounded(.up))
        }
        let labelHeight: CGFloat = labelled ? 14 : 0
        let withinSpacing: CGFloat = 3
        let betweenSpacing: CGFloat = 5
        // Padding (20) + header (18) + header gap (4), from the fixed strip.
        let contentHeight = KBTheme.cardStripHeight - 42
        let reserved = CGFloat(sectionCount) * labelHeight
            + CGFloat(max(0, sectionCount - 1)) * betweenSpacing
            + CGFloat(max(0, totalRows - sectionCount)) * withinSpacing
        let rowHeight = min(30, max(10,
            (contentHeight - reserved) / CGFloat(max(totalRows, 1))))
        let meterHeight = min(14, max(5, rowHeight - 9))
        let showsTemperature = visible.contains { $0.temperatureCelsius != nil }

        return VStack(spacing: betweenSpacing) {
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                VStack(spacing: withinSpacing) {
                    if let title = group.title {
                        clusterHeader(title, count: group.cores.count)
                    }
                    coreRows(group.cores,
                             columns: columns,
                             rowHeight: rowHeight,
                             meterHeight: meterHeight,
                             showsTemperature: showsTemperature)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func clusterHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text("· \(count)")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(.quaternary.opacity(0.45))
                .frame(height: 0.5)
        }
        .frame(height: 11)
        .accessibilityHidden(true)
    }

    private func coreRows(_ cores: [KBCoreCPU], columns: Int,
                          rowHeight: CGFloat, meterHeight: CGFloat,
                          showsTemperature: Bool) -> some View {
        let rows = stride(from: 0, to: cores.count, by: columns).map {
            Array(cores[$0..<min($0 + columns, cores.count)])
        }
        return VStack(spacing: 3) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 12) {
                    ForEach(rows[rowIndex]) { core in
                        compactCoreRow(core,
                                       meterHeight: meterHeight,
                                       showsTemperature: showsTemperature)
                            .frame(maxWidth: .infinity)
                    }
                    if rows[rowIndex].count < columns {
                        ForEach(0..<(columns - rows[rowIndex].count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }

    private func compactCoreRow(_ core: KBCoreCPU, meterHeight: CGFloat,
                                showsTemperature: Bool) -> some View {
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
                if showsTemperature {
                    TemperatureLabel(celsius: core.temperatureCelsius, width: 26)
                }
            }
            HStack(spacing: 4) {
                coreIndexLabel(core)
                meter
                if showsTemperature {
                    TemperatureLabel(celsius: core.temperatureCelsius, width: 26)
                }
            }
            HStack(spacing: 4) {
                coreIndexLabel(core)
                meter
            }
            meter
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU core \(core.index + 1)")
        .accessibilityValue(coreAccessibilityValue(core))
    }

    private func coreAccessibilityValue(_ core: KBCoreCPU) -> String {
        var parts = ["\(Int(core.usagePercent.rounded())) percent usage"]
        if let temperature = core.temperatureCelsius {
            parts.append("\(Int(temperature.rounded())) degrees Celsius")
        }
        return parts.joined(separator: ", ")
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
            .frame(width: 30, alignment: .trailing)
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
                    packageTemperatureBadge(cpu)
                    Text("\(cpu.coreCount) cores")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let cpu {
                let split = CPUTopology.performanceCoreCount
                    .map { min(max($0, 0), cpu.cores.count) } ?? 0
                let groups: [(title: String?, cores: [KBCoreCPU])] =
                    (split > 0 && split < cpu.cores.count)
                    ? [("PERFORMANCE", Array(cpu.cores[0..<split])),
                       ("EFFICIENCY", Array(cpu.cores[split...]))]
                    : [(nil, cpu.cores)]

                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    VStack(alignment: .leading, spacing: 6) {
                        if let title = group.title {
                            HStack(spacing: 5) {
                                Text(title)
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(.secondary)
                                Text("· \(group.cores.count)")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                Rectangle()
                                    .fill(.quaternary.opacity(0.45))
                                    .frame(height: 0.5)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)],
                                  alignment: .leading,
                                  spacing: 6) {
                            ForEach(group.cores) { core in
                                coreRow(core)
                            }
                        }
                    }
                }

                if cpu.packageTemperatureCelsius != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 9))
                        Text("\(KBFormat.temperature(cpu.packageTemperatureCelsius)) package")
                        if let source = cpu.temperatureSource {
                            Text("· \(source)")
                        }
                        Spacer()
                        Text("per-core values are mapped from the available sensors, like btop")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                } else {
                    Text("Temperature unavailable on this Mac. Intel Macs and some virtual machines do not expose IOHID temperature sensors.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
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

            TemperatureLabel(celsius: core.temperatureCelsius,
                             fontSize: 9,
                             compact: true,
                             width: 30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU core \(core.index + 1)")
        .accessibilityValue(coreAccessibilityValue(core))
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
