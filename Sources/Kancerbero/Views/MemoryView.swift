import AppKit
import SwiftUI
import KancerberoCore

/// Memory dashboard mirroring Activity Monitor's Memory tab: pressure,
/// breakdown (App / Wired / Compressed / Cached / Free), the seven detail
/// values and a process list ordered by resident memory.
struct MemoryView: View {
    @Environment(AppModel.self) private var model

    private let memoryTint = Color(red: 0.20, green: 0.70, blue: 0.62)
    private let appColor = KBTheme.downloadTint
    private let wiredColor = Color(red: 0.95, green: 0.42, blue: 0.30)
    private let compressedColor = Color(red: 0.72, green: 0.40, blue: 0.92)
    private let cachedColor = KBTheme.connectionsTint
    private let idleColor = Color.gray.opacity(0.28)
    private let swapColor = Color(red: 0.62, green: 0.42, blue: 0.95)

    @State private var showPhysicalMemoryDetails = false
    @State private var showPressureDetails = false
    @State private var showCompositionDetails = false
    @State private var showSwapDetails = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 14) {
            header(model: model)

            GeometryReader { proxy in
                let topHeight = max(210, (proxy.size.height - 14) / 3)
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

    // MARK: - Header

    private func header(model: AppModel) -> some View {
        @Bindable var model = model

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Memory")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Pressure, breakdown and processes")
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

    // MARK: - Top strip

    private var topGroups: some View {
        HStack(alignment: .top, spacing: 14) {
            groupPanel("Pressure") {
                pressureCard
            }
            .frame(width: 280)

            groupPanel("Breakdown") {
                HStack(spacing: 10) {
                    activityMonitorCard
                        .frame(minWidth: 210, idealWidth: 250, maxWidth: 250)
                    compositionCard
                        .frame(maxWidth: .infinity)
                }
            }

            groupPanel("Swap") {
                swapCard
            }
            .frame(width: 220)
        }
    }

    private func groupPanel<Content: View>(_ title: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private var pressureCard: some View {
        Button {
            showPressureDetails = true
        } label: {
            pressureCardContent
        }
        .buttonStyle(.plain)
        .help("Memory pressure history")
        .popover(isPresented: $showPressureDetails, arrowEdge: .bottom) {
            pressureDetails
                .padding(16)
                .frame(width: 460)
        }
    }

    private var pressureCardContent: some View {
        let memory = model.hostMetrics?.memory
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                cardIcon("gauge.medium", tint: memoryTint)
                Text("Memory pressure")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if let memory, memory.pressurePercent != nil {
                    Text(memory.pressureLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(pressureColor(memory.pressureBand))
                        .lineLimit(1)
                }
            }

            if let memory, let percent = memory.pressurePercent {
                Text("\(percent)% pressure")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Not reported")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if model.memoryPressureHistory.count > 1 {
                MemoryPressureChart(values: model.memoryPressureHistory,
                                    levels: model.memoryPressureLevelHistory)
                    .frame(maxHeight: .infinity)
            } else {
                Text("Collecting…")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }

            Text("Memory pressure is an indicator of the system’s ability to meet the memory requirements of the user’s activities. Higher memory pressure indicates that the system is reaching its limits, and performance may degrade.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(memoryTint.opacity(0.22), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var activityMonitorCard: some View {
        Button {
            showPhysicalMemoryDetails = true
        } label: {
            activityMonitorCardContent
        }
        .buttonStyle(.plain)
        .help("Memory used history and breakdown")
        .popover(isPresented: $showPhysicalMemoryDetails, arrowEdge: .bottom) {
            physicalMemoryDetails
                .padding(16)
                .frame(width: 460)
        }
    }

    private var activityMonitorCardContent: some View {
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
                              tint: memoryTint,
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
                .strokeBorder(memoryTint.opacity(0.22), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var compositionCard: some View {
        Button {
            showCompositionDetails = true
        } label: {
            compositionCardContent
        }
        .buttonStyle(.plain)
        .help("Memory composition and detail")
        .popover(isPresented: $showCompositionDetails, arrowEdge: .bottom) {
            compositionDetails
                .padding(16)
                .frame(width: 460)
        }
    }

    private var compositionCardContent: some View {
        let memory = model.hostMetrics?.memory
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                cardIcon("chart.bar.fill", tint: compressedColor)
                Text("Composition")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }

            if let memory {
                if model.memoryAppHistory.count > 1 {
                    MemoryCompositionChart(
                        app: model.memoryAppHistory,
                        wired: model.memoryWiredHistory,
                        compressed: model.memoryCompressedHistory,
                        cached: model.memoryCachedHistory,
                        free: model.memoryFreeHistory,
                        appColor: appColor,
                        wiredColor: wiredColor,
                        compressedColor: compressedColor,
                        cachedColor: cachedColor,
                        freeColor: idleColor
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    Text("Collecting…")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                MeterLegend(items: [
                    MeterLegendItem("App", value: KBFormat.bytes(memory.appMemoryBytes),
                                    color: appColor),
                    MeterLegendItem("Wired", value: KBFormat.bytes(memory.wiredBytes),
                                    color: wiredColor),
                    MeterLegendItem("Compressed", value: KBFormat.bytes(memory.compressedBytes),
                                    color: compressedColor),
                    MeterLegendItem("Cached", value: KBFormat.bytes(memory.cachedFileBytes),
                                    color: cachedColor),
                    MeterLegendItem("Free", value: KBFormat.bytes(memory.activityMonitorFreeBytes),
                                    color: idleColor)
                ], minItemWidth: 120)
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
                .strokeBorder(memoryTint.opacity(0.22), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var swapCard: some View {
        Button {
            showSwapDetails = true
        } label: {
            swapCardContent
        }
        .buttonStyle(.plain)
        .help("Swap usage and status")
        .popover(isPresented: $showSwapDetails, arrowEdge: .bottom) {
            swapDetails
                .padding(16)
                .frame(width: 460)
        }
    }

    private var swapCardContent: some View {
        let memory = model.hostMetrics?.memory
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                cardIcon("arrow.left.arrow.right", tint: swapColor)
                Text("Swap")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let memory {
                    Text(KBFormat.bytes(memory.swapTotalBytes))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if let memory {
                Text("\(KBFormat.bytes(memory.swapUsedBytes)) used")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                CapacityBar(
                    fraction: memory.swapUsedFraction,
                    tint: memory.swapUsedFraction > 0.8 ? .red : swapColor
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

                Divider().opacity(0.4)

                metric("Free", KBFormat.bytes(memory.activityMonitorFreeBytes))
                metric("Cached files", KBFormat.bytes(memory.cachedFileBytes))

                Spacer(minLength: 0)
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
                .strokeBorder(memoryTint.opacity(0.22), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    /// Decorative badge matching the top-strip cards in the CPU tab.
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
                        .foregroundStyle(memoryTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
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

    // MARK: - Popover details

    private var physicalMemoryDetails: some View {
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
                        .foregroundStyle(memoryTint)
                }

                if model.memoryUsageHistory.count > 1 {
                    Sparkline(values: model.memoryUsageHistory,
                              tint: memoryTint,
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

    private var compositionDetails: some View {
        let memory = model.hostMetrics?.memory
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory composition")
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
                    Text("\(KBFormat.bytes(memory.activityMonitorUsedBytes)) used · \(KBFormat.percent(memory.activityMonitorUsedFraction))")
                        .font(.system(size: 10))
                        .monospacedDigit()
                }

                if model.memoryAppHistory.count > 1 {
                    MemoryCompositionChart(
                        app: model.memoryAppHistory,
                        wired: model.memoryWiredHistory,
                        compressed: model.memoryCompressedHistory,
                        cached: model.memoryCachedHistory,
                        free: model.memoryFreeHistory,
                        appColor: appColor,
                        wiredColor: wiredColor,
                        compressedColor: compressedColor,
                        cachedColor: cachedColor,
                        freeColor: idleColor
                    )
                    .frame(height: 170)
                } else {
                    Text("Collecting…")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                }

                MeterLegend(items: [
                    MeterLegendItem("App", value: KBFormat.bytes(memory.appMemoryBytes),
                                    color: appColor),
                    MeterLegendItem("Wired", value: KBFormat.bytes(memory.wiredBytes),
                                    color: wiredColor),
                    MeterLegendItem("Compressed", value: KBFormat.bytes(memory.compressedBytes),
                                    color: compressedColor),
                    MeterLegendItem("Cached", value: KBFormat.bytes(memory.cachedFileBytes),
                                    color: cachedColor),
                    MeterLegendItem("Free", value: KBFormat.bytes(memory.activityMonitorFreeBytes),
                                    color: idleColor)
                ], minItemWidth: 140)

                Text("App, wired, compressed and cached memory as Activity Monitor reports it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting for metrics…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var swapDetails: some View {
        let memory = model.hostMetrics?.memory
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Swap")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let memory {
                    Text(KBFormat.bytes(memory.swapTotalBytes))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let memory {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(KBFormat.bytes(memory.swapUsedBytes)) used")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(KBFormat.percent(memory.swapUsedFraction))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(memory.swapUsedFraction > 0.8 ? .red : swapColor)
                }

                CapacityBar(
                    fraction: memory.swapUsedFraction,
                    tint: memory.swapUsedFraction > 0.8 ? .red : swapColor,
                    height: 14
                )

                if memory.swapEncrypted {
                    Label("Encrypted", systemImage: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.4)

                HStack(alignment: .top, spacing: 28) {
                    metric("Free", KBFormat.bytes(memory.activityMonitorFreeBytes))
                    metric("Cached files", KBFormat.bytes(memory.cachedFileBytes))
                    Spacer(minLength: 0)
                }

                Text("Swap is used when physical memory is full; heavy swap use can slow the Mac down.")
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

    // MARK: - Processes

    private var processCard: some View {
        MemoryProcessTable(rows: model.cpuProcessRows)
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
