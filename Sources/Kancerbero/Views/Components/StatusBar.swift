import Foundation
import SwiftUI
import KancerberoCore

struct StatusBar: View {
    let section: AppSection
    @Environment(AppModel.self) private var model
    @Environment(DiskModel.self) private var disk
    @Environment(FilterModel.self) private var filter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(KBPreferences.statusBarTextAnimationsKey)
    private var statusBarTextAnimations = KBPreferences.statusBarTextAnimationsDefault

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
        .animation(barAnimation, value: model.systemRates.rxBytesPerSecond)
    }

    private var barAnimation: Animation? {
        KBPreferences.enabled(stored: statusBarTextAnimations, reduceMotion: reduceMotion)
            ? .snappy(duration: 0.25)
            : nil
    }

    /// Fixed-width slot so a changing value never shifts the neighbouring
    /// components. Digits are monospaced so the value itself does not jitter.
    private func slot(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .contentTransition(textTransition)
    }

    private var textTransition: ContentTransition {
        KBPreferences.enabled(stored: statusBarTextAnimations, reduceMotion: reduceMotion)
            ? .numericText()
            : .identity
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

        case .memory:
            if let memory = model.hostMetrics?.memory {
                LiveDot(isLive: model.isLive)
                slot("\(KBFormat.bytes(memory.activityMonitorUsedBytes)) / \(KBFormat.bytes(memory.totalBytes))",
                     width: 150)
                slot("Pressure \(memory.pressureLabel)", width: 95)
                slot("Cached \(KBFormat.bytes(memory.cachedFileBytes))", width: 120)
                slot("Swap \(KBFormat.bytes(memory.swapUsedBytes))", width: 110)
            } else {
                Text("Waiting for memory metrics…")
                    .foregroundStyle(.secondary)
            }

        case .energy:
            LiveDot(isLive: model.isLive)
            if let power = model.hostMetrics?.power {
                slot(power.hasBattery
                     ? "Battery \(power.chargePercent.map { "\($0)%" } ?? "—")"
                     : "No battery", width: 100)
                slot(power.isCharging ? "Charging"
                     : power.isPluggedIn ? "AC power" : "On battery",
                     width: 80)
                if let minutes = power.timeRemainingMinutes {
                    slot("\(minutes / 60):\(String(format: "%02d", minutes % 60)) left",
                         width: 90)
                }
            } else {
                slot("Power —", width: 100)
            }
            slot(String(format: "Energy %.1f W", energyWatts), width: 100)
            slot(String(format: "Wakeups %.0f/s", wakeupsPerSecond), width: 105)
        }
    }

    private var energyWatts: Double {
        model.processes.reduce(0) { $0 + ($1.usage?.energyWatts ?? 0) }
    }

    private var wakeupsPerSecond: Double {
        model.processes.reduce(0) { $0 + ($1.usage?.wakeupsPerSecond ?? 0) }
    }

    private var globalStatus: some View {
        HStack(spacing: 14) {
            chip(label: filter.filterStatusLabel,
                 textWidth: 64,
                 icon: "shield.lefthalf.filled",
                 tint: filter.filterStatusTint,
                 help: filter.filterStatusHelp,
                 accessibilityLabel: "Network filter: \(filter.filterHealth.systemValue)")

            chip(label: daemonLabel,
                 textWidth: 74,
                 icon: "info.circle",
                 tint: statusTint,
                 help: daemonHelp,
                 accessibilityLabel: daemonHelp)

            if model.privcheck >= 0 {
                chip(label: model.trafficAccessShortLabel,
                     textWidth: nil,
                     icon: "network",
                     tint: model.trafficAccessTint,
                     help: model.trafficAccessHelp,
                     accessibilityLabel: model.trafficAccessLabel)
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
                      textWidth: CGFloat?,
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
                    .fixedSize(horizontal: textWidth == nil, vertical: false)
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

    private var daemonLabel: String {
        guard model.usingDaemon else { return "Local" }
        return model.daemonIsRoot ? "Daemon root" : "Daemon user"
    }

    private var daemonHelp: String {
        guard model.usingDaemon else {
            return "System status: local mode"
        }
        return model.daemonIsRoot
            ? "System status: daemon connected as root"
            : "System status: daemon connected without root"
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
        case .memory:
            return model.lastUpdate.map { "Updated \(KBFormat.time($0))" } ?? "Waiting…"
        case .energy:
            return model.lastUpdate.map { "Updated \(KBFormat.time($0))" } ?? "Waiting…"
        }
    }

    private var isDaemonsLive: Bool {
        guard let date = model.daemonLastUpdate else { return false }
        return Date().timeIntervalSince(date) < 15 && model.daemonServicesError == nil
    }
}
