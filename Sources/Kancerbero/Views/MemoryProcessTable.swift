import SwiftUI
import KancerberoCore

/// Process list for the Memory tab: resident memory first, then its share of
/// physical memory. Selection, search and inspection mirror the CPU table.
struct MemoryProcessTable: View {
    let rows: [CPUProcessRow]

    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var inspected: KBProcessInfo?

    private var selection: Binding<KBProcessKey?> {
        Binding(
            get: { ui.memory.selectedProcess },
            set: { ui.memory.selectedProcess = $0 }
        )
    }

    private var sortOrder: Binding<[KeyPathComparator<CPUProcessRow>]> {
        Binding(
            get: { ui.memory.processSortOrder },
            set: { ui.memory.processSortOrder = $0 }
        )
    }

    private var search: Binding<String> {
        Binding(
            get: { ui.memory.search },
            set: { ui.memory.search = $0 }
        )
    }

    private var displayRows: [CPUProcessRow] {
        let filtered = rows.filter { $0.matches(ui.memory.search, userNames: model.userNames) }
        if ui.memory.processSortOrder.isEmpty {
            return filtered.sorted { $0.residentSortValue > $1.residentSortValue }
        }
        return filtered.sorted(using: ui.memory.processSortOrder)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Processes by memory")
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
                commandColumn
                residentColumn
                memoryColumn
                threadsColumn
                pidColumn
                userColumn
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
            if let pid = ui.memory.pendingSelectionPID {
                if let row = rows.first(where: { $0.process.pid == pid }) {
                    ui.memory.selectedProcess = row.id
                }
                ui.memory.pendingSelectionPID = nil
            }
            guard let selected = ui.memory.selectedProcess,
                  !ids.contains(selected) else { return }
            ui.memory.selectedProcess = nil
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
        .width(min: 160, ideal: 320)
    }

    private var residentColumn: some TableColumnContent<CPUProcessRow,
                                                        KeyPathComparator<CPUProcessRow>> {
        TableColumn("Memory", value: \.residentSortValue) { row in
            Text(row.residentText)
                .monospacedDigit()
        }
        .width(min: 80, ideal: 100)
    }

    private var memoryColumn: some TableColumnContent<CPUProcessRow,
                                                      KeyPathComparator<CPUProcessRow>> {
        TableColumn("MEM%", value: \.memorySortValue) { row in
            Text(row.memoryText)
                .monospacedDigit()
                .foregroundStyle(memoryColor(row.memoryPercent))
        }
        .width(min: 55, ideal: 65)
    }

    private var threadsColumn: some TableColumnContent<CPUProcessRow,
                                                       KeyPathComparator<CPUProcessRow>> {
        TableColumn("Threads", value: \.threadsSortValue) { row in
            Text(row.threadsText)
                .monospacedDigit()
        }
        .width(min: 55, ideal: 70)
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
        .width(min: 70, ideal: 110)
    }

    private var selectedRow: CPUProcessRow? {
        guard let selection = ui.memory.selectedProcess else { return nil }
        return rows.first { $0.id == selection }
    }

    private func memoryColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 10 { return .orange }
        if value >= 2 { return .primary }
        return .secondary
    }
}
