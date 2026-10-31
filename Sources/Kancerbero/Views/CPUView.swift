import SwiftUI
import KancerberoCore

struct CPUView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

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
            CollapsibleSectionHeader(
                section: .cpu,
                title: "CPU",
                subtitle: "Cores, load, memory and processes"
            )

            VStack(spacing: 14) {
                if !ui.cardsCollapsed(for: .cpu) {
                    topGroups
                        .frame(height: KBTheme.cardStripHeight)
                        .transition(.opacity)
                }
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
                    .frame(minWidth: 92, idealWidth: 100, maxWidth: 112)
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
                                         titleSize: CGFloat = 12,
                                         captionSize: CGFloat = 11,
                                         showsInfo: Bool = true,
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
                    .font(.system(size: titleSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if showsInfo {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
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
                    .font(.system(size: captionSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                        tint: loadTint,
                        titleSize: 11,
                        captionSize: 10,
                        showsInfo: false) {
            if let cpu {
                let restrictedHelp = "\(cpu.threadsRestricted) processes belong to other users or come from a daemon that predates the full process enumeration. Their CPU, memory and thread counters are unavailable; installing the current build and repairing the background service restores them."
                let threadsLabel = Text("\(cpu.threadCount.formatted()) threads")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(cpu.taskCount.formatted()) tasks")
                        .font(.system(size: 16, weight: .semibold))
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            threadsLabel
                            if cpu.threadsRestricted > 0 {
                                Text("partial")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange)
                                    .help(restrictedHelp)
                            }
                        }
                        HStack(spacing: 3) {
                            threadsLabel
                            if cpu.threadsRestricted > 0 {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .help(restrictedHelp)
                                    .accessibilityLabel("partial thread data")
                            }
                        }
                        threadsLabel
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
        .help("Per-core load history and temperature")
        .popover(isPresented: $showCoresDetails, arrowEdge: .bottom) {
            coresDetails
                .padding(16)
                .frame(width: 1120, height: 600, alignment: .topLeading)
        }
    }

    private var coresIcon: some View {
        Image(systemName: "cpu")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(KBTheme.gradient(cpuTint))
            }
    }

    private func coresCompactCard(_ cpu: KBCPUStats?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        coresIcon
                        Text("Cores")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    coresIcon
                }
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
                GeometryReader { proxy in
                    let size = proxy.size
                    if cpu.cores.isEmpty {
                        Text("Waiting for per-core metrics…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if size.width >= 300, cpu.cores.count <= 8 {
                        coreEqualizer(cpu, available: size)
                    } else {
                        coreClusters(cpu,
                                     contentHeight: size.height,
                                     narrow: size.width < 160)
                    }
                }
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

    private func packageTemperatureBadge(_ cpu: KBCPUStats,
                                         large: Bool = false) -> some View {
        let tint = KBTheme.temperatureTint(cpu.packageTemperatureCelsius)
        let value = cpu.packageTemperatureCelsius.map {
            "\(Int($0.rounded()))°C"
        } ?? "—"
        return HStack(spacing: large ? 4 : 3) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: large ? 10 : 8, weight: .semibold))
            Text(value)
                .font(.system(size: large ? 12 : 10,
                              weight: .semibold,
                              design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, large ? 7 : 5)
        .padding(.vertical, large ? 3 : 2)
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

    /// One-row equalizer used for up to eight cores: each core is a column of
    /// recent load bars, grouped by performance level.
    private func coreEqualizer(_ cpu: KBCPUStats, available: CGSize) -> some View {
        let visible = Array(cpu.cores.prefix(8))
        let split = CPUTopology.performanceCoreCount
            .map { min(max($0, 0), visible.count) } ?? 0
        var groups: [(title: String?, cores: [KBCoreCPU])]
        if split > 0, split < visible.count {
            groups = [("PERFORMANCE", Array(visible[0..<split])),
                      ("EFFICIENCY", Array(visible[split...]))]
        } else {
            groups = [(nil, visible)]
        }

        let metrics = CoreWallMetrics(
            width: available.width,
            groupCounts: groups.map { $0.cores.count },
            cellGap: 3,
            groupGap: 8,
            divider: 0.5
        )
        let headerBlock: CGFloat = groups.count > 1 ? 14 : 0
        let cellHeight = max(40, available.height - headerBlock)
        let showsTemperature = visible.contains { $0.temperatureCelsius != nil }

        return HStack(alignment: .top, spacing: 0) {
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                VStack(alignment: .leading, spacing: 3) {
                    if let title = group.title {
                        clusterHeader(String(title.prefix(1)),
                                      count: group.cores.count)
                    }
                    HStack(spacing: 3) {
                        ForEach(group.cores) { core in
                            equalizerCell(core,
                                          showsTemperature: showsTemperature)
                                .frame(width: metrics.columnWidth)
                        }
                    }
                    .frame(height: cellHeight, alignment: .top)
                }
                .frame(width: metrics.groupWidths[index], alignment: .leading)

                if index < groups.count - 1 {
                    Rectangle()
                        .fill(.quaternary.opacity(0.5))
                        .frame(width: 0.5, height: available.height)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func equalizerCell(_ core: KBCoreCPU,
                               showsTemperature: Bool) -> some View {
        let history = coreHistory(core)
        return VStack(spacing: 2) {
            Text("C\(core.index + 1)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(height: 10)
                .frame(maxWidth: .infinity)

            CoreLoadBars(values: history.isEmpty ? [core.usagePercent] : history,
                         maxBars: 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            equalizerFooter(core, showsTemperature: showsTemperature)
                .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Core C\(core.index + 1)")
        .accessibilityValue(coreAccessibilityValue(core))
    }

    private func equalizerFooter(_ core: KBCoreCPU,
                                 showsTemperature: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                usageLabel(core, compact: false)
                if showsTemperature {
                    TemperatureLabel(celsius: core.temperatureCelsius,
                                     fontSize: 8,
                                     compact: true)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 2) {
                usageLabel(core, compact: true)
                if showsTemperature {
                    TemperatureLabel(celsius: core.temperatureCelsius,
                                     fontSize: 8,
                                     compact: true)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            usageLabel(core, compact: false)
                .fixedSize(horizontal: true, vertical: false)

            usageLabel(core, compact: true)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
    }

    private func usageLabel(_ core: KBCoreCPU, compact: Bool) -> some View {
        Text(compact
             ? "\(Int(core.usagePercent.rounded()))%"
             : KBFormat.usagePercent(core.usagePercent))
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(core.usagePercent > 85 ? .orange : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(.numericText())
    }

    private func coreHistory(_ core: KBCoreCPU) -> [Double] {
        guard model.coreUsageHistory.indices.contains(core.index) else { return [] }
        return model.coreUsageHistory[core.index]
    }

    /// Fallback grid for narrow cards or Macs with more than eight cores.
    private func coreClusters(_ cpu: KBCPUStats,
                              contentHeight: CGFloat,
                              narrow: Bool) -> some View {
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

        let columns = narrow ? 1 : (visible.count > 16 ? 3 : 2)
        let sectionCount = groups.count
        let labelled = groups.contains { $0.title != nil }
        let totalRows = groups.reduce(0) {
            $0 + Int((Double($1.cores.count) / Double(columns)).rounded(.up))
        }
        let labelHeight: CGFloat = labelled ? 14 : 0
        let withinSpacing: CGFloat = 3
        let betweenSpacing: CGFloat = 5
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
                        clusterHeader(narrow ? String(title.prefix(1)) : title,
                                      count: group.cores.count)
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
            accessibilityLabel: "Core C\(core.index + 1)"
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
        .accessibilityLabel("Core C\(core.index + 1)")
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
        Text("C\(core.index + 1)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 16, alignment: .trailing)
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
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("CPU cores")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if let cpu {
                    packageTemperatureBadge(cpu, large: true)
                    Text("\(cpu.coreCount) cores")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let cpu {
                coreLoadLegend

                let split = CPUTopology.performanceCoreCount
                    .map { min(max($0, 0), cpu.cores.count) } ?? 0
                let groups: [(title: String?, cores: [KBCoreCPU])] =
                    (split > 0 && split < cpu.cores.count)
                    ? [("PERFORMANCE", Array(cpu.cores[0..<split])),
                       ("EFFICIENCY", Array(cpu.cores[split...]))]
                    : [(nil, cpu.cores)]

                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    VStack(alignment: .leading, spacing: 8) {
                        if let title = group.title {
                            HStack(spacing: 6) {
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(.secondary)
                                Text("· \(group.cores.count)")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                Rectangle()
                                    .fill(.quaternary.opacity(0.45))
                                    .frame(height: 0.5)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 500), spacing: 16)],
                                  alignment: .leading,
                                  spacing: 10) {
                            ForEach(group.cores) { core in
                                coreRow(core)
                            }
                        }
                    }
                }

                if cpu.packageTemperatureCelsius != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 10))
                        Text("\(KBFormat.temperature(cpu.packageTemperatureCelsius)) package")
                        if let source = cpu.temperatureSource {
                            Text("· \(source)")
                        }
                        Spacer()
                        Text("per-core values are mapped from the available sensors, like btop")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                } else {
                    Text("Temperature unavailable on this Mac. Intel Macs and some virtual machines do not expose IOHID temperature sensors.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if cpu.threadsRestricted > 0 {
                    Label("\(cpu.threadsRestricted) restricted",
                          systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .medium))
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
                ], minItemWidth: 150)

                HStack {
                    Label("Uptime \(KBFormat.uptime(cpu.uptimeSeconds))",
                          systemImage: "clock")
                    Spacer()
                    Text("\(cpu.taskCount) tasks · \(cpu.threadCount) threads")
                }
                .font(.system(size: 11))
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

    private var coreLoadLegend: some View {
        let samples = model.coreUsageHistory.map { $0.count }.max() ?? 0
        return HStack(spacing: 8) {
            Text("Core load")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            LinearGradient(
                colors: [
                    KBTheme.loadHeat(10), KBTheme.loadHeat(30),
                    KBTheme.loadHeat(55), KBTheme.loadHeat(75),
                    KBTheme.loadHeat(95)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 80, height: 7)
            .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
            Text("low → high")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(samples > 0 ? "last \(samples) samples" : "collecting…")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .accessibilityHidden(true)
    }

    private func coreRow(_ core: KBCoreCPU) -> some View {
        let history = coreHistory(core)
        return HStack(spacing: 10) {
            Text("C\(core.index + 1)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            CoreLoadBars(values: history.isEmpty ? [core.usagePercent] : history,
                         maxBars: 30)
                .frame(maxWidth: .infinity)
                .frame(height: 68)

            Text(KBFormat.usagePercent(core.usagePercent))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(core.usagePercent > 85 ? .orange : .secondary)
                .frame(width: 54, alignment: .trailing)

            TemperatureLabel(celsius: core.temperatureCelsius,
                             fontSize: 10,
                             compact: true,
                             width: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Core C\(core.index + 1)")
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

/// Pure width math for the per-core equalizer: all columns share one width and
/// each group is sized from its core count plus its internal gaps.
private struct CoreWallMetrics {
    let columnWidth: CGFloat
    let groupWidths: [CGFloat]

    init(width: CGFloat, groupCounts: [Int],
         cellGap: CGFloat, groupGap: CGFloat, divider: CGFloat) {
        let cells = groupCounts.reduce(0, +)
        let groups = groupCounts.count
        let innerGaps = groupCounts.reduce(0) { $0 + max(0, $1 - 1) }
        let chrome = CGFloat(max(0, groups - 1)) * (divider + 2 * groupGap)
        let gaps = CGFloat(innerGaps) * cellGap
        let column = max(1, (width - chrome - gaps) / CGFloat(max(cells, 1)))
        columnWidth = column
        groupWidths = groupCounts.map {
            CGFloat($0) * column + CGFloat(max(0, $0 - 1)) * cellGap
        }
    }
}
