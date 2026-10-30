import SwiftUI
import KancerberoCore

struct CPUProcessTable: View {
    let rows: [CPUProcessRow]

    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var inspected: KBProcessInfo?

    private var selection: Binding<KBProcessKey?> {
        Binding(
            get: { ui.cpu.selectedProcess },
            set: { ui.cpu.selectedProcess = $0 }
        )
    }

    private var sortOrder: Binding<[KeyPathComparator<CPUProcessRow>]> {
        Binding(
            get: { ui.cpu.processSortOrder },
            set: { ui.cpu.processSortOrder = $0 }
        )
    }

    private var search: Binding<String> {
        Binding(
            get: { ui.cpu.search },
            set: { ui.cpu.search = $0 }
        )
    }

    private var displayRows: [CPUProcessRow] {
        let filtered = rows.filter { $0.matches(ui.cpu.search, userNames: model.userNames) }
        if ui.cpu.processSortOrder.isEmpty {
            return filtered.sorted { $0.cpuSortValue > $1.cpuSortValue }
        }
        return filtered.sorted(using: ui.cpu.processSortOrder)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Processes")
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

                if let cpu = model.hostMetrics?.cpu, cpu.threadsRestricted > 0 {
                    Label("\(cpu.threadsRestricted) restricted", systemImage: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help("CPU, memory and thread counts of other users require the root daemon.")
                }

                Text("\(displayRows.count) of \(rows.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Table(displayRows, selection: selection, sortOrder: sortOrder) {
                pidColumn
                userColumn
                priorityColumn
                virtualColumn
                residentColumn
                stateColumn
                cpuColumnView
                memoryColumn
                timeColumn
                commandColumn
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
            if let pid = ui.cpu.pendingSelectionPID {
                if let row = rows.first(where: { $0.process.pid == pid }) {
                    ui.cpu.selectedProcess = row.id
                }
                ui.cpu.pendingSelectionPID = nil
            }
            guard let selected = ui.cpu.selectedProcess,
                  !ids.contains(selected) else { return }
            ui.cpu.selectedProcess = nil
        }
    }

    private var selectedRow: CPUProcessRow? {
        guard let selection = ui.cpu.selectedProcess else { return nil }
        return rows.first { $0.id == selection }
    }

    private var pidColumn: some TableColumnContent<CPUProcessRow,
                                                   KeyPathComparator<CPUProcessRow>> {
        TableColumn("PID", value: \.process.pid) { row in
            pidCell(row)
        }
        .width(min: 44, ideal: 52)
    }

    private var userColumn: some TableColumnContent<CPUProcessRow,
                                                    KeyPathComparator<CPUProcessRow>> {
        TableColumn("USER", value: \.userSortValue) { row in
            userCell(row)
        }
        .width(min: 60, ideal: 74)
    }

    private var priorityColumn: some TableColumnContent<CPUProcessRow,
                                                        KeyPathComparator<CPUProcessRow>> {
        TableColumn("PRI/NI", value: \.prioritySortValue) { row in
            priorityCell(row)
        }
        .width(min: 50, ideal: 56)
    }

    private var virtualColumn: some TableColumnContent<CPUProcessRow,
                                                       KeyPathComparator<CPUProcessRow>> {
        TableColumn("VIRT", value: \.virtualSortValue) { row in
            numericText(row.virtualText)
        }
        .width(min: 60, ideal: 66)
    }

    private var residentColumn: some TableColumnContent<CPUProcessRow,
                                                        KeyPathComparator<CPUProcessRow>> {
        TableColumn("RES", value: \.residentSortValue) { row in
            numericText(row.residentText)
        }
        .width(min: 60, ideal: 66)
    }

    private var stateColumn: some TableColumnContent<CPUProcessRow,
                                                     KeyPathComparator<CPUProcessRow>> {
        TableColumn("S/THR", value: \.stateSortValue) { row in
            stateCell(row)
        }
        .width(min: 40, ideal: 48)
    }

    private var cpuColumnView: some TableColumnContent<CPUProcessRow,
                                                       KeyPathComparator<CPUProcessRow>> {
        TableColumn("CPU%", value: \.cpuSortValue) { row in
            cpuCell(row)
        }
        .width(min: 50, ideal: 56)
    }

    private var memoryColumn: some TableColumnContent<CPUProcessRow,
                                                      KeyPathComparator<CPUProcessRow>> {
        TableColumn("MEM%", value: \.memorySortValue) { row in
            numericText(row.memoryText)
        }
        .width(min: 50, ideal: 56)
    }

    private var timeColumn: some TableColumnContent<CPUProcessRow,
                                                    KeyPathComparator<CPUProcessRow>> {
        TableColumn("TIME+", value: \.timeSortValue) { row in
            numericText(row.timeText)
        }
        .width(min: 60, ideal: 66)
    }

    private var commandColumn: some TableColumnContent<CPUProcessRow,
                                                       KeyPathComparator<CPUProcessRow>> {
        TableColumn("Command", value: \.commandSortValue) { row in
            commandCell(row)
        }
        .width(min: 110, ideal: 140)
    }

    private func pidCell(_ row: CPUProcessRow) -> some View {
        Text(String(row.process.pid))
            .monospacedDigit()
    }

    private func userCell(_ row: CPUProcessRow) -> some View {
        Text(model.userName(for: row.process.uid))
            .lineLimit(1)
    }

    private func priorityCell(_ row: CPUProcessRow) -> some View {
        Text(row.priorityNiceText)
            .monospacedDigit()
            .help("Priority / nice (Mach task priority)")
    }

    private func stateCell(_ row: CPUProcessRow) -> some View {
        Text(row.stateThreadsText)
            .monospaced()
            .help("\(row.stateHelp) / \(row.threadsText) threads")
    }

    private func cpuCell(_ row: CPUProcessRow) -> some View {
        Text(row.cpuText)
            .monospacedDigit()
            .foregroundStyle(cpuColor(row.cpuPercent))
    }

    private func commandCell(_ row: CPUProcessRow) -> some View {
        Text(row.commandText)
            .lineLimit(1)
            .help(row.process.path.isEmpty ? row.commandText : row.process.path)
    }

    private func numericText(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
    }

    private func cpuColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 50 { return .orange }
        if value >= 10 { return .primary }
        return .secondary
    }
}
