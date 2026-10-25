import Foundation
import SwiftUI
import KancerberoCore

struct StatusBar: View {
    let section: AppSection
    @Environment(AppModel.self) private var model
    @Environment(DiskModel.self) private var disk
    @State private var showStatus = false

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
        .onAppear(perform: autoOpenStatusPopoverIfRequested)
    }

    private func autoOpenStatusPopoverIfRequested() {
        guard CommandLine.arguments.contains("--show-status"),
              CommandLine.arguments.contains("--sidebar-collapsed"),
              !showStatus else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            showStatus = true
        }
    }

    @ViewBuilder
    private var metrics: some View {
        switch section {
        case .networking:
            LiveDot(isLive: model.isLive)
            Text("\(model.processInventory.count) networked processes")
            Text("\(model.sources.count) connections")
            Text("RX \(KBFormat.bitRate(model.systemRates.rxBytesPerSecond))")
            Text("TX \(KBFormat.bitRate(model.systemRates.txBytesPerSecond))")

        case .disk:
            LiveDot(isLive: disk.inventory != nil && !disk.isLoadingInventory)
            Text("\(DiskMetrics.physicalDiskCount(disk.inventory)) disks")
            Text("\(DiskMetrics.mountedVolumeCount(disk.inventory)) volumes")
            Text("\(KBFormat.bytes(DiskMetrics.capacityBytes(disk.inventory))) total")
            Text("\(KBFormat.bytes(DiskMetrics.freeBytes(disk.inventory))) free")
            if disk.isScanning {
                ProgressView().controlSize(.mini)
                Text("Scanning \(KBFormat.compactCount(disk.scanProgress?.files ?? 0)) files")
            } else if let snapshot = disk.scanSnapshot {
                Text("Scanned \(KBFormat.bytes(snapshot.root.allocatedBytes))")
            }

        case .daemons:
            let entries = model.daemonEntries
            LiveDot(isLive: isDaemonsLive)
            Text("\(entries.count) services")
            Text("\(entries.filter { $0.service.state == .running }.count) running")
            Text("\(entries.filter { $0.service.state == .stopped }.count) stopped")
            Text("\(entries.filter { $0.service.state == .disabled }.count) disabled")
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
                Text("\(cpu.coreCount) cores")
                Text("CPU \(KBFormat.usagePercent(cpu.totalUsagePercent))")
                Text("Load \(KBFormat.load(cpu.load1))")
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
                Text("\(KBFormat.bytes(memory.usedBytes)) / \(KBFormat.bytes(memory.totalBytes))")
            }
        }
    }

    private var globalStatus: some View {
        HStack(spacing: 14) {
            Button {
                showStatus.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(model.usingDaemon ? "Daemon" : "Local")
                    Image(systemName: "info.circle")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background {
                    Capsule().fill(statusTint.opacity(0.14))
                }
                .foregroundStyle(statusTint)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("System status and background service setup")
            .accessibilityLabel(model.usingDaemon
                ? "System status: daemon connected"
                : "System status: local mode")
            .popover(isPresented: $showStatus, arrowEdge: .bottom) {
                SystemStatusView()
                    .environment(model)
            }

            if model.privcheck >= 0 {
                Text("privcheck \(model.privcheck)")
            }
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Text(updatedLabel)
                .foregroundStyle(.secondary)
        }
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
