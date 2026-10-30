import SwiftUI
import KancerberoCore

/// Energy dashboard mirroring Activity Monitor's Energy tab: battery state,
/// per-process energy and idle wake-ups, sleep assertions, and the process
/// list ordered by energy.
struct EnergyView: View {
    @Environment(AppModel.self) private var model

    private let energyTint = Color(red: 0.95, green: 0.72, blue: 0.20)
    private let wakeupTint = KBTheme.uploadTint
    private let batteryTint = Color(red: 0.20, green: 0.72, blue: 0.52)

    @State private var showBatteryDetails = false
    @State private var showEnergyDetails = false
    @State private var showWakeupsDetails = false

    var body: some View {
        VStack(spacing: 14) {
            SectionHeader(title: "Energy",
                          subtitle: "Battery, energy and wake-ups")

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

    // MARK: - Top strip

    private var topGroups: some View {
        HStack(alignment: .top, spacing: 14) {
            batteryCard
                .frame(width: 260)

            energyCard
                .frame(maxWidth: .infinity)

            wakeupsCard
                .frame(width: 240)
        }
    }

    private var batteryCard: some View {
        Button {
            showBatteryDetails = true
            model.refreshBatteryChargeGraph(force: true)
        } label: {
            batteryCardContent
        }
        .buttonStyle(.plain)
        .help("Battery charge and power source")
        .popover(isPresented: $showBatteryDetails, arrowEdge: .bottom) {
            batteryDetails
                .padding(16)
                .frame(width: 460)
        }
    }

    private var batteryCardContent: some View {
        let power = model.hostMetrics?.power
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Battery")
                    .font(.system(size: 12, weight: .semibold))
                if power?.isPluggedIn == true {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let power {
                    Text(powerLabel(power))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(batteryTintFor(power))
                }
            }

            if let power, power.hasBattery {
                HStack(alignment: .center, spacing: 8) {
                    Text(power.chargePercent.map { "\($0)%" } ?? "—")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)

                    timeOnPowerLine(power)
                    Spacer(minLength: 0)
                }

                if let graph = model.batteryChargeGraph,
                   graph.chargeLevels.count > 1 {
                    BatteryChargeChart(graph: graph)
                        .frame(maxHeight: .infinity)
                        .layoutPriority(1)
                } else {
                    CapacityBar(fraction: power.chargeFraction,
                                tint: batteryTintFor(power),
                                height: 10)
                }

                HStack(alignment: .top, spacing: 12) {
                    metric("Power source", power.source ?? "—")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    metric("Time remaining", timeRemainingText(power))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No battery")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("This Mac runs on AC power.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
                .strokeBorder(energyTint.opacity(0.22), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var energyCard: some View {
        Button {
            showEnergyDetails = true
        } label: {
            energyCardContent
        }
        .buttonStyle(.plain)
        .help("Energy history and top processes")
        .popover(isPresented: $showEnergyDetails, arrowEdge: .bottom) {
            energyDetails
                .padding(16)
                .frame(width: 560)
        }
    }

    private var energyCardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Energy")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(String(format: "%.2f W", totalEnergy))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(String(format: "%.2f W", totalEnergy))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)

            Text(topEnergyProcess.map {
                "Top: \($0.commandText) · \($0.energyText)"
            } ?? "No process energy yet")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(topEnergyProcess?.process.path ?? "Energy history")

            if model.energyUsageHistory.count > 1 {
                Sparkline(values: model.energyUsageHistory, tint: energyTint)
                    .frame(maxHeight: .infinity)
            } else {
                Color.clear.frame(maxHeight: .infinity)
            }

            Text("Session total of visible processes")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(energyTint.opacity(0.22), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var wakeupsCard: some View {
        Button {
            showWakeupsDetails = true
        } label: {
            wakeupsCardContent
        }
        .buttonStyle(.plain)
        .help("Idle wake-ups and top processes")
        .popover(isPresented: $showWakeupsDetails, arrowEdge: .bottom) {
            wakeupsDetails
                .padding(16)
                .frame(width: 460)
        }
    }

    private var wakeupsCardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Idle wake-ups")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f/s", totalWakeups))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(String(format: "%.0f/s", totalWakeups))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)

            Text(topWakeupProcess.map {
                "Top: \($0.commandText) · \($0.wakeupsText)"
            } ?? "No wake-up data yet")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(topWakeupProcess?.process.path ?? "Idle wake-ups")

            if model.wakeupHistory.count > 1 {
                Sparkline(values: model.wakeupHistory, tint: wakeupTint)
                    .frame(maxHeight: .infinity)
            } else {
                Color.clear.frame(maxHeight: .infinity)
            }

            Text("Interrupt + package idle wake-ups")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(energyTint.opacity(0.22), lineWidth: 1)
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

    // MARK: - Derived values

    private var totalEnergy: Double {
        model.cpuProcessRows.reduce(0) { $0 + ($1.energyWatts ?? 0) }
    }

    private var totalWakeups: Double {
        model.cpuProcessRows.reduce(0) { $0 + ($1.wakeupsPerSecond ?? 0) }
    }

    private var topEnergyProcess: CPUProcessRow? {
        topEnergyProcesses(limit: 1).first
    }

    private var topWakeupProcess: CPUProcessRow? {
        topWakeupProcesses(limit: 1).first
    }

    private func topEnergyProcesses(limit: Int) -> [CPUProcessRow] {
        Array(model.cpuProcessRows
            .filter { ($0.energyWatts ?? 0) > 0 }
            .sorted {
                let lhs = $0.energyWatts ?? 0
                let rhs = $1.energyWatts ?? 0
                if lhs == rhs {
                    return $0.commandText.localizedStandardCompare($1.commandText) == .orderedAscending
                }
                return lhs > rhs
            }
            .prefix(limit))
    }

    private func topWakeupProcesses(limit: Int) -> [CPUProcessRow] {
        Array(model.cpuProcessRows
            .filter { ($0.wakeupsPerSecond ?? 0) > 0 }
            .sorted {
                let lhs = $0.wakeupsPerSecond ?? 0
                let rhs = $1.wakeupsPerSecond ?? 0
                if lhs == rhs {
                    return $0.commandText.localizedStandardCompare($1.commandText) == .orderedAscending
                }
                return lhs > rhs
            }
            .prefix(limit))
    }

    private func energyShareText(_ row: CPUProcessRow) -> String {
        guard totalEnergy > 0, let watts = row.energyWatts else { return "—" }
        return String(format: "%.0f%%", min(100, watts / totalEnergy * 100))
    }

    private func wakeupShareText(_ row: CPUProcessRow) -> String {
        guard totalWakeups > 0, let rate = row.wakeupsPerSecond else { return "—" }
        return String(format: "%.0f%%", min(100, rate / totalWakeups * 100))
    }

    private func processShareRow(_ row: CPUProcessRow,
                                 detail: String,
                                 share: String) -> some View {
        HStack(spacing: 8) {
            Text(row.commandText)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(row.process.path.isEmpty ? row.commandText : row.process.path)
            Spacer(minLength: 4)
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
            Text(share)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func powerLabel(_ power: KBPowerStats) -> String {
        if power.isCharging { return "Charging" }
        if power.isCharged { return "Charged" }
        return power.isPluggedIn ? "AC power" : "On battery"
    }

    private func timeRemainingText(_ power: KBPowerStats) -> String {
        if power.isCharged { return "Fully charged" }
        if power.isCharging {
            guard let minutes = power.timeRemainingMinutes else { return "Calculating…" }
            return "Full in \(minutes / 60)h \(minutes % 60)m"
        }
        guard let minutes = power.timeRemainingMinutes else { return "—" }
        return "\(minutes / 60)h \(minutes % 60)m left"
    }

    /// How long the Mac has been on its current power source, as Activity
    /// Monitor reports it from the same charge graph.
    private var timeOnPower: (label: String, value: String)? {
        guard let graph = model.batteryChargeGraph,
              !graph.onAC.isEmpty,
              graph.onAC.count == graph.stateTimes.count else { return nil }
        let entries = zip(graph.stateTimes, graph.onAC).sorted { $0.0 > $1.0 }
        guard let current = entries.last else { return nil }
        var start = current.0
        for entry in entries.reversed() {
            guard entry.1 == current.1 else { break }
            start = entry.0
        }
        let total = Int(max(0, start))
        return (current.1 ? "Time on AC" : "Time on Battery",
                "\(total / 3600)h \((total % 3600) / 60)m")
    }

    private func timeOnPowerLine(_ power: KBPowerStats) -> some View {
        let info = timeOnPower
        let label = info?.label ?? (power.isPluggedIn ? "Time on AC" : "Time on Battery")
        let value = info?.value ?? "—"
        return HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.system(size: 9))
        .lineLimit(1)
    }

    private func batteryTintFor(_ power: KBPowerStats) -> Color {
        if power.isCharging || power.isCharged { return batteryTint }
        guard let charge = power.chargePercent else { return .secondary }
        if charge <= 10 { return .red }
        if charge <= 20 { return .yellow }
        return batteryTint
    }

    // MARK: - Popover details

    private var batteryDetails: some View {
        let power = model.hostMetrics?.power
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Battery")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let power {
                    Text(powerLabel(power))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(batteryTintFor(power))
                }
            }

            if let power, power.hasBattery {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(power.chargePercent.map { "\($0)%" } ?? "—")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(power.isPluggedIn ? "Plugged in" : "On battery")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                timeOnPowerLine(power)

                if let graph = model.batteryChargeGraph,
                   graph.chargeLevels.count > 1 {
                    BatteryChargeChart(graph: graph)
                        .frame(height: 180)
                } else {
                    CapacityBar(fraction: power.chargeFraction,
                                tint: batteryTintFor(power),
                                height: 14)
                }

                HStack(alignment: .top, spacing: 28) {
                    metric("Power source", power.source ?? "—")
                    metric("Time remaining", timeRemainingText(power))
                    Spacer(minLength: 0)
                }

                Divider().opacity(0.4)

                Text("Charge and time estimates come from IOKit power sources. The estimate reads “Calculating…” until macOS has enough samples.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if power != nil {
                Text("No battery")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("This Mac runs on AC power.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting for power metrics…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var energyDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Energy")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(model.energyUsageHistory.count) samples")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Text(String(format: "%.2f W", totalEnergy))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()

            if model.energyUsageHistory.count > 1 {
                Sparkline(values: model.energyUsageHistory, tint: energyTint)
                    .frame(height: 200)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 200)
                    .overlay {
                        Text("Collecting samples…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
            }

            Divider().opacity(0.4)

            Text("Top processes by energy")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            let rows = topEnergyProcesses(limit: 5)
            if rows.isEmpty {
                Text("No per-process energy reported yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 5) {
                    ForEach(rows) { row in
                        processShareRow(row,
                                        detail: row.energyText,
                                        share: energyShareText(row))
                    }
                }
            }

            Text("Session total of visible processes.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var wakeupsDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Idle wake-ups")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(model.wakeupHistory.count) samples")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Text(String(format: "%.0f/s", totalWakeups))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()

            if model.wakeupHistory.count > 1 {
                Sparkline(values: model.wakeupHistory, tint: wakeupTint)
                    .frame(height: 180)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 180)
                    .overlay {
                        Text("Collecting samples…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
            }

            Divider().opacity(0.4)

            Text("Top processes by wake-ups")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            let rows = topWakeupProcesses(limit: 5)
            if rows.isEmpty {
                Text("No per-process wake-up data yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 5) {
                    ForEach(rows) { row in
                        processShareRow(row,
                                        detail: row.wakeupsText,
                                        share: wakeupShareText(row))
                    }
                }
            }

            Text("Interrupt + package idle wake-ups.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Processes

    private var processCard: some View {
        EnergyProcessTable(rows: model.cpuProcessRows)
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
