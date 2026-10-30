import SwiftUI
import KancerberoCore

/// Process list for the Disk → I/O tab: per-process read/write rates and
/// cumulative disk counters, sorted by combined activity.
struct DiskIOProcessTable: View {
    let rows: [CPUProcessRow]

    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var inspected: KBProcessInfo?

    private var selection: Binding<KBProcessKey?> {
        Binding(
            get: { ui.disk.ioSelectedProcess },
            set: { ui.disk.ioSelectedProcess = $0 }
        )
    }

    private var sortOrder: Binding<[KeyPathComparator<CPUProcessRow>]> {
        Binding(
            get: { ui.disk.ioSortOrder },
            set: { ui.disk.ioSortOrder = $0 }
        )
    }

    private var search: Binding<String> {
        Binding(
            get: { ui.disk.ioSearch },
            set: { ui.disk.ioSearch = $0 }
        )
    }

    private var displayRows: [CPUProcessRow] {
        let filtered = rows.filter { $0.matches(ui.disk.ioSearch, userNames: model.userNames) }
        if ui.disk.ioSortOrder.isEmpty {
            return filtered.sorted { $0.diskSortValue > $1.diskSortValue }
        }
        return filtered.sorted(using: ui.disk.ioSortOrder)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Processes by disk activity")
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

                if diskMissingCount > 0 {
                    Label("\(diskMissingCount) partial", systemImage: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help("Per-process disk counters require the current background daemon; install the current build and repair the service to update it.")
                }

                if let cpu = model.hostMetrics?.cpu, cpu.threadsRestricted > 0 {
                    Label("\(cpu.threadsRestricted) restricted", systemImage: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help("Per-process disk counters for other users require the root daemon; reinstall the current build if the daemon is outdated.")
                }

                Text("\(displayRows.count) of \(rows.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Table(displayRows, selection: selection, sortOrder: sortOrder) {
                commandColumn
                readRateColumn
                writeRateColumn
                bytesReadColumn
                bytesWrittenColumn
                writesColumn
                stateColumn
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
            if let pid = ui.disk.ioPendingSelectionPID {
                if let row = rows.first(where: { $0.process.pid == pid }) {
                    ui.disk.ioSelectedProcess = row.id
                }
                ui.disk.ioPendingSelectionPID = nil
            }
            guard let selected = ui.disk.ioSelectedProcess,
                  !ids.contains(selected) else { return }
            ui.disk.ioSelectedProcess = nil
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
        .width(min: 150, ideal: 250)
    }

    private var readRateColumn: some TableColumnContent<CPUProcessRow,
                                                        KeyPathComparator<CPUProcessRow>> {
        TableColumn("Read/s", value: \.diskReadSortValue) { row in
            Text(row.diskReadRateText)
                .monospacedDigit()
        }
        .width(min: 75, ideal: 90)
    }

    private var writeRateColumn: some TableColumnContent<CPUProcessRow,
                                                         KeyPathComparator<CPUProcessRow>> {
        TableColumn("Write/s", value: \.diskWriteSortValue) { row in
            Text(row.diskWriteRateText)
                .monospacedDigit()
        }
        .width(min: 75, ideal: 90)
    }

    private var bytesReadColumn: some TableColumnContent<CPUProcessRow,
                                                         KeyPathComparator<CPUProcessRow>> {
        TableColumn("Bytes Read", value: \.diskBytesReadSortValue) { row in
            Text(row.diskBytesReadText)
                .monospacedDigit()
                .help("Cumulative bytes read by this process")
        }
        .width(min: 85, ideal: 100)
    }

    private var bytesWrittenColumn: some TableColumnContent<CPUProcessRow,
                                                            KeyPathComparator<CPUProcessRow>> {
        TableColumn("Bytes Written", value: \.diskBytesWrittenSortValue) { row in
            Text(row.diskBytesWrittenText)
                .monospacedDigit()
                .help("Cumulative bytes written by this process")
        }
        .width(min: 95, ideal: 110)
    }

    private var writesColumn: some TableColumnContent<CPUProcessRow,
                                                      KeyPathComparator<CPUProcessRow>> {
        TableColumn("Writes", value: \.logicalWritesSortValue) { row in
            Text(row.logicalWritesText)
                .monospacedDigit()
                .help("Logical writes reported by rusage_info_v6")
        }
        .width(min: 65, ideal: 80)
    }

    private var stateColumn: some TableColumnContent<CPUProcessRow,
                                                     KeyPathComparator<CPUProcessRow>> {
        TableColumn("State", value: \.stateSortValue) { row in
            Text(row.stateThreadsText)
                .monospaced()
                .help("\(row.stateHelp) / \(row.threadsText) threads")
        }
        .width(min: 55, ideal: 65)
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

    private var selectedRow: CPUProcessRow? {
        guard let selection = ui.disk.ioSelectedProcess else { return nil }
        return rows.first { $0.id == selection }
    }

    /// Processes whose task info is available but whose disk counters are not
    /// (typically a daemon built before rusage_info_v6 disk fields).
    private var diskMissingCount: Int {
        rows.filter { $0.process.usage != nil && $0.diskReadRate == nil }.count
    }
}
