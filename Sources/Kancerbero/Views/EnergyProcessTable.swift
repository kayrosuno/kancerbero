import SwiftUI
import KancerberoCore

/// Process list for the Energy tab: per-process energy rate, its share of the
/// busiest process, idle wake-ups and sleep assertions.
struct EnergyProcessTable: View {
    let rows: [CPUProcessRow]

    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var inspected: KBProcessInfo?

    private var selection: Binding<KBProcessKey?> {
        Binding(
            get: { ui.energy.selectedProcess },
            set: { ui.energy.selectedProcess = $0 }
        )
    }

    private var sortOrder: Binding<[KeyPathComparator<CPUProcessRow>]> {
        Binding(
            get: { ui.energy.processSortOrder },
            set: { ui.energy.processSortOrder = $0 }
        )
    }

    private var search: Binding<String> {
        Binding(
            get: { ui.energy.search },
            set: { ui.energy.search = $0 }
        )
    }

    private var displayRows: [CPUProcessRow] {
        let filtered = rows.filter { $0.matches(ui.energy.search, userNames: model.userNames) }
        if ui.energy.processSortOrder.isEmpty {
            return filtered.sorted { $0.energySortValue > $1.energySortValue }
        }
        return filtered.sorted(using: ui.energy.processSortOrder)
    }

    private var maximumEnergy: Double {
        max(displayRows.map { $0.energyWatts ?? 0 }.max() ?? 0, 0.000_001)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Processes by energy")
                    .font(.system(size: 12, weight: .semibold))

                TextField("Filter processes", text: search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Button("Inspect Selected") {
                    inspected = selectedRow?.process
                }
                .disabled(selectedRow == nil)

                Spacer()

                if !model.usingDaemon && !model.isRoot {
                    Text("your processes only")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .help("macOS exposes other users' processes only through the root daemon.")
                }

                Text("\(displayRows.count) of \(rows.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Table(displayRows, selection: selection, sortOrder: sortOrder) {
                commandColumn
                energyColumn
                impactColumn
                wakeupsColumn
                cpuColumn
                pidColumn
                userColumn
                sleepColumn
            }
            .contextMenu(forSelectionType: KBProcessKey.self) { keys in
                if let key = keys.first, let row = rows.first(where: { $0.id == key }) {
                    Button("Inspect \(row.commandText)") {
                        inspected = row.process
                    }
                }
            } primaryAction: { keys in
                if let key = keys.first, let row = rows.first(where: { $0.id == key }) {
                    inspected = row.process
                }
            }
        }
        .sheet(item: $inspected) { process in
            ProcessInspectorView(process: process)
                .environment(model)
        }
        .onChange(of: rows.map(\.id), initial: true) { _, ids in
            if let pid = ui.energy.pendingSelectionPID {
                if let row = rows.first(where: { $0.process.pid == pid }) {
                    ui.energy.selectedProcess = row.id
                }
                ui.energy.pendingSelectionPID = nil
            }
            guard let selected = ui.energy.selectedProcess,
                  !ids.contains(selected) else { return }
            ui.energy.selectedProcess = nil
        }
    }

    // MARK: - Columns

    private var commandColumn: some TableColumnContent<CPUProcessRow,
                                                      KeyPathComparator<CPUProcessRow>> {
        TableColumn("Command", value: \.commandSortValue) { row in
            Text(row.commandText)
                .lineLimit(1)
                .help(row.process.path.isEmpty ? row.commandText : row.process.path)
        }
        .width(min: 150, ideal: 280)
    }

    private var energyColumn: some TableColumnContent<CPUProcessRow,
                                                      KeyPathComparator<CPUProcessRow>> {
        TableColumn("Energy", value: \.energySortValue) { row in
            Text(row.energyText)
                .monospacedDigit()
                .foregroundStyle(row.energyWatts != nil ? .primary : .secondary)
        }
        .width(min: 70, ideal: 85)
    }

    private var impactColumn: some TableColumnContent<CPUProcessRow,
                                                      KeyPathComparator<CPUProcessRow>> {
        TableColumn("Impact", value: \.energySortValue) { row in
            Text(impactText(row))
                .monospacedDigit()
                .foregroundStyle(impactColor(row))
                .help("Energy relative to the busiest process in this list")
        }
        .width(min: 60, ideal: 72)
    }

    private var wakeupsColumn: some TableColumnContent<CPUProcessRow,
                                                       KeyPathComparator<CPUProcessRow>> {
        TableColumn("Wake-ups", value: \.wakeupSortValue) { row in
            Text(row.wakeupsText)
                .monospacedDigit()
        }
        .width(min: 70, ideal: 85)
    }

    private var cpuColumn: some TableColumnContent<CPUProcessRow,
                                                   KeyPathComparator<CPUProcessRow>> {
        TableColumn("CPU%", value: \.cpuSortValue) { row in
            Text(row.cpuText)
                .monospacedDigit()
        }
        .width(min: 55, ideal: 62)
    }

    private var pidColumn: some TableColumnContent<CPUProcessRow,
                                                   KeyPathComparator<CPUProcessRow>> {
        TableColumn("PID", value: \.process.pid) { row in
            Text(String(row.process.pid))
                .monospacedDigit()
        }
        .width(min: 50, ideal: 60)
    }

    private var userColumn: some TableColumnContent<CPUProcessRow,
                                                    KeyPathComparator<CPUProcessRow>> {
        TableColumn("USER", value: \.userSortValue) { row in
            Text(model.userName(for: row.process.uid))
                .lineLimit(1)
        }
        .width(min: 70, ideal: 100)
    }

    private var sleepColumn: some TableColumnContent<CPUProcessRow,
                                                     KeyPathComparator<CPUProcessRow>> {
        TableColumn("Preventing Sleep", value: \.sleepSortValue) { row in
            if row.preventingSleep {
                Label("Yes", systemImage: "moon.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .width(min: 100, ideal: 130)
    }

    private var selectedRow: CPUProcessRow? {
        guard let selection = ui.energy.selectedProcess else { return nil }
        return rows.first { $0.id == selection }
    }

    private func impactText(_ row: CPUProcessRow) -> String {
        guard let energy = row.energyWatts, energy > 0 else { return "—" }
        let percentage = min(100, energy / maximumEnergy * 100)
        return String(format: "%.0f%%", percentage)
    }

    private func impactColor(_ row: CPUProcessRow) -> Color {
        guard let energy = row.energyWatts, energy > 0 else { return .secondary }
        let ratio = energy / maximumEnergy
        if ratio >= 0.66 { return .orange }
        if ratio >= 0.33 { return .primary }
        return .secondary
    }
}
