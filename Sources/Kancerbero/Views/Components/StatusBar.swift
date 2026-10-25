import SwiftUI
import KancerberoCore

struct StatusBar: View {
    let section: AppSection
    @Environment(AppModel.self) private var model
    @Environment(DiskModel.self) private var disk

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

    @ViewBuilder
    private var metrics: some View {
        switch section {
        case .networking:
            LiveDot(isLive: model.isLive)
            Text("\(model.processes.count) processes")
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
        }
    }

    private var globalStatus: some View {
        HStack(spacing: 14) {
            Text(model.usingDaemon ? "Daemon" : "Local")
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background {
                    Capsule().fill(model.usingDaemon
                                   ? Color.green.opacity(0.14)
                                   : Color.orange.opacity(0.14))
                }
                .foregroundStyle(model.usingDaemon ? Color.green : Color.orange)
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
        }
    }

    private var isDaemonsLive: Bool {
        guard let date = model.daemonLastUpdate else { return false }
        return Date().timeIntervalSince(date) < 15 && model.daemonServicesError == nil
    }
}
