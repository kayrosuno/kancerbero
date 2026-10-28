import Foundation
import SwiftUI
import KancerberoCore

struct StatusBar: View {
    let section: AppSection
    @Environment(AppModel.self) private var model
    @Environment(DiskModel.self) private var disk
    @Environment(FilterModel.self) private var filter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 14) {
            metrics
            Spacer()
            globalStatus
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .animation(.snappy(duration: 0.25), value: model.systemRates.rxBytesPerSecond)
    }

    /// Fixed-width slot so a changing value never shifts the neighbouring
    /// components. Digits are monospaced so the value itself does not jitter.
    private func slot(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private var metrics: some View {
        switch section {
        case .networking:
            LiveDot(isLive: model.isLive)
            slot("\(model.processInventory.count) networked processes", width: 165)
            slot("\(model.sources.count) connections", width: 120)
            slot("RX \(KBFormat.bitRate(model.systemRates.rxBytesPerSecond))", width: 100)
            slot("TX \(KBFormat.bitRate(model.systemRates.txBytesPerSecond))", width: 100)

        case .disk:
            LiveDot(isLive: disk.inventory != nil && !disk.isLoadingInventory)
            slot("\(DiskMetrics.physicalDiskCount(disk.inventory)) disks", width: 80)
            slot("\(DiskMetrics.mountedVolumeCount(disk.inventory)) volumes", width: 90)
            slot("\(KBFormat.bytes(DiskMetrics.capacityBytes(disk.inventory))) total", width: 100)
            slot("\(KBFormat.bytes(DiskMetrics.freeBytes(disk.inventory))) free", width: 95)
            if disk.isScanning {
                ProgressView().controlSize(.mini)
                slot("Scanning \(KBFormat.compactCount(disk.scanProgress?.files ?? 0)) files",
                     width: 150)
            } else if let snapshot = disk.scanSnapshot {
                slot("Scanned \(KBFormat.bytes(snapshot.root.allocatedBytes))", width: 115)
            }

        case .daemons:
            let entries = model.daemonEntries
            LiveDot(isLive: isDaemonsLive)
            slot("\(entries.count) services", width: 90)
            slot("\(entries.filter { $0.service.state == .running }.count) running", width: 90)
            slot("\(entries.filter { $0.service.state == .stopped }.count) stopped", width: 90)
            slot("\(entries.filter { $0.service.state == .disabled }.count) disabled", width: 95)
            if model.daemonActionInFlight {
                ProgressView().controlSize(.mini)
            }
            if let error = model.daemonServicesError {
                Text(error)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(error)
            }

        case .cpu:
            if let cpu = model.hostMetrics?.cpu {
                LiveDot(isLive: model.isLive)
                slot("\(cpu.coreCount) cores", width: 70)
                slot("CPU \(KBFormat.usagePercent(cpu.totalUsagePercent))", width: 90)
                slot("Load \(KBFormat.load(cpu.load1))", width: 85)
                if cpu.threadsRestricted > 0 {
                    Text("partial")
                        .foregroundStyle(.orange)
                        .help("\(cpu.threadsRestricted) processes belong to another user; install the root daemon for their CPU and memory counters.")
                }
            } else {
                Text("Waiting for CPU metrics…")
                    .foregroundStyle(.secondary)
            }
            if let memory = model.hostMetrics?.memory {
                slot("\(KBFormat.bytes(memory.usedBytes)) / \(KBFormat.bytes(memory.totalBytes))",
                     width: 135)
            }
        }
    }

    private var globalStatus: some View {
        HStack(spacing: 14) {
            chip(label: filterLabel,
                 textWidth: 64,
                 icon: "shield.lefthalf.filled",
                 tint: filterTint,
                 help: filterHelp,
                 accessibilityLabel: "Network filter: \(filter.controller.state.title)")

            chip(label: model.usingDaemon ? "Daemon" : "Local",
                 textWidth: 52,
                 icon: "info.circle",
                 tint: statusTint,
                 help: "System status and background service setup",
                 accessibilityLabel: model.usingDaemon
                     ? "System status: daemon connected"
                     : "System status: local mode")

            if model.privcheck >= 0 {
                slot("privcheck \(model.privcheck)", width: 85)
            }
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            slot(updatedLabel, width: 130)
                .foregroundStyle(.secondary)
        }
    }

    /// Capsule chip with a fixed text width so state changes do not shift the
    /// rest of the bar. Opens the System status window.
    private func chip(label: String,
                      textWidth: CGFloat,
                      icon: String,
                      tint: Color,
                      help: String,
                      accessibilityLabel: String) -> some View {
        Button {
            openWindow(id: SystemStatusWindow.id)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .lineLimit(1)
                    .frame(width: textWidth, alignment: .leading)
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(tint.opacity(0.14))
            }
            .foregroundStyle(tint)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the System status window")
    }

    private var filterLabel: String {
        switch filter.controller.state {
        case .enabled: return "Filter"
        case .disabled: return "Filter off"
        case .requiresApproval: return "Approval"
        case .activating: return "Filter…"
        case .notInstalled, .unsupported: return "No filter"
        case .failed: return "Error"
        }
    }

    private var filterTint: Color {
        switch filter.controller.state {
        case .enabled:
            return filter.isConnected ? .green : .orange
        case .failed:
            return .red
        case .unsupported:
            return .gray
        case .disabled, .notInstalled, .requiresApproval, .activating:
            return .orange
        }
    }

    private var filterHelp: String {
        var text = "Network filter: \(filter.controller.state.title)"
        if case .failed(let message) = filter.controller.state {
            text += " — \(message)"
        }
        return text
    }

    private var statusTint: Color {
        if model.legacyServiceDetected { return .orange }
        if model.usingDaemon {
            return model.daemonIsRoot ? .green : .orange
        }
        return .orange
    }

    private var updatedLabel: String {
        switch section {
        case .networking:
            return model.lastUpdate.map { "Updated \(KBFormat.time($0))" } ?? "Waiting…"
        case .disk:
            let date = [disk.inventory?.generatedAt, disk.scanSnapshot?.generatedAt]
                .compactMap { $0 }
                .max()
            return date.map { "Updated \(KBFormat.time($0))" } ?? "Waiting…"
        case .daemons:
            return model.daemonLastUpdate.map { "Updated \(KBFormat.time($0))" } ?? "Waiting…"
        case .cpu:
            return model.lastUpdate.map { "Updated \(KBFormat.time($0))" } ?? "Waiting…"
        }
    }

    private var isDaemonsLive: Bool {
        guard let date = model.daemonLastUpdate else { return false }
        return Date().timeIntervalSince(date) < 15 && model.daemonServicesError == nil
    }
}
