import AppKit
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
                Text("Energy")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Battery, energy and wake-ups")
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
            groupPanel("Battery") {
                batteryCard
            }
            .frame(width: 260)

            groupPanel("Energy") {
                energyCard
            }

            groupPanel("Wake-ups") {
                wakeupsCard
            }
            .frame(width: 240)
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

    private var batteryCard: some View {
        let power = model.hostMetrics?.power
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let power {
                    Text(powerLabel(power))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(batteryTintFor(power))
                }
            }

            if let power, power.hasBattery {
                Text(power.chargePercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)

                CapacityBar(fraction: power.chargeFraction,
                            tint: batteryTintFor(power),
                            height: 12)

                HStack(spacing: 4) {
                    Text(timeRemainingText(power))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if power.isPluggedIn {
                        Label("Plugged in", systemImage: "powerplug.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().opacity(0.4)

                metric("Power source", power.source ?? "—")
                metric("Time remaining", timeRemainingText(power))

                Spacer(minLength: 0)
            } else {
                Text("No battery")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("This Mac runs on AC power.")
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
                .strokeBorder(energyTint.opacity(0.22), lineWidth: 1)
        }
    }

    private var energyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(energyTint.opacity(0.22), lineWidth: 1)
        }
    }

    private var wakeupsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(energyTint.opacity(0.22), lineWidth: 1)
        }
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
        guard let row = model.cpuProcessRows.max(by: {
            ($0.energyWatts ?? 0) < ($1.energyWatts ?? 0)
        }), (row.energyWatts ?? 0) > 0 else { return nil }
        return row
    }

    private var topWakeupProcess: CPUProcessRow? {
        guard let row = model.cpuProcessRows.max(by: {
            ($0.wakeupsPerSecond ?? 0) < ($1.wakeupsPerSecond ?? 0)
        }), (row.wakeupsPerSecond ?? 0) > 0 else { return nil }
        return row
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

    private func batteryTintFor(_ power: KBPowerStats) -> Color {
        if power.isCharging || power.isCharged { return batteryTint }
        guard let charge = power.chargePercent else { return .secondary }
        if charge <= 10 { return .red }
        if charge <= 20 { return .yellow }
        return batteryTint
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
