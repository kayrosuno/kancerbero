import SwiftUI
import KancerberoCore

struct InterfacesView: View {
    let items: [KBInterfaceInfo]
    @Environment(AppModel.self) private var model

    var body: some View {
        Table(items) {
            TableColumn("Interface") { item in
                Text(item.name).monospaced()
            }
            .width(min: 80, ideal: 100)
            TableColumn("Type") { item in
                Text(item.kind.displayName)
            }
            .width(min: 70, ideal: 90)
            TableColumn("State") { item in
                Text(state(item))
            }
            .width(min: 60, ideal: 80)
            TableColumn("Received") { item in
                Text(KBFormat.bytes(item.counters.rxBytes)).monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("Sent") { item in
                Text(KBFormat.bytes(item.counters.txBytes)).monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("RX/s") { item in
                Text(KBFormat.rate(model.interfaceRates[item.id]?.rxBytesPerSecond ?? 0)).monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("TX/s") { item in
                Text(KBFormat.rate(model.interfaceRates[item.id]?.txBytesPerSecond ?? 0)).monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("MTU") { item in
                Text("\(item.mtu)").monospacedDigit()
            }
            .width(min: 50, ideal: 60)
        }
    }

    private func state(_ item: KBInterfaceInfo) -> String {
        if !item.isUp { return "Down" }
        return item.isRunning ? "Up" : "Dormant"
    }
}

struct ConnectionsView: View {
    let rows: [KBNStatSource]
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var inspected: KBProcessInfo?

    private var selectedSource: KBNStatSource? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Inspect Process") {
                    if let source = selectedSource {
                        inspected = process(for: source)
                    }
                }
                .disabled(selectedSource == nil)
                Spacer()
            }

            Table(rows, selection: $selection) {
                TableColumn("Process") { source in
                    Text(source.processName.isEmpty ? "Unknown" : source.processName)
                }
                .width(min: 120, ideal: 180)
                TableColumn("PID") { source in
                    Text("\(source.pid)").monospacedDigit()
                }
                .width(min: 50, ideal: 70)
                TableColumn("Proto") { source in
                    Text(source.connectionProtocol.displayName).monospaced()
                }
                .width(min: 50, ideal: 60)
                TableColumn("Local") { source in
                    Text(source.local.display).monospaced().help(source.local.display)
                }
                .width(min: 160, ideal: 250)
                TableColumn("Remote") { source in
                    Text(source.remote.display).monospaced().help(source.remote.display)
                }
                .width(min: 160, ideal: 250)
                TableColumn("State") { source in
                    Text(source.tcpState.isEmpty ? "—" : source.tcpState)
                }
                .width(min: 90, ideal: 110)
                TableColumn("Iface") { source in
                    Text(source.interfaceName.isEmpty ? "—" : source.interfaceName).monospaced()
                }
                .width(min: 50, ideal: 70)
                TableColumn("RX") { source in
                    Text(KBFormat.bytes(source.counters.rxBytes)).monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("TX") { source in
                    Text(KBFormat.bytes(source.counters.txBytes)).monospacedDigit()
                }
                .width(min: 80, ideal: 100)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                if let id = keys.first, let source = rows.first(where: { $0.id == id }) {
                    Button("Inspect \(source.processName)") { inspected = process(for: source) }
                }
            } primaryAction: { keys in
                if let id = keys.first, let source = rows.first(where: { $0.id == id }) {
                    inspected = process(for: source)
                }
            }
        }
        .sheet(item: $inspected) { process in
            ProcessInspectorView(process: process)
                .environment(model)
        }
    }

    private func process(for source: KBNStatSource) -> KBProcessInfo {
        model.processes.first { $0.pid == source.pid }
            ?? KBProcessInfo(pid: source.pid, name: source.processName)
    }
}

struct ProcessesView: View {
    let items: [KBProcessInfo]
    @Environment(AppModel.self) private var model
    @State private var selection: KBProcessKey?
    @State private var inspected: KBProcessInfo?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Inspect Selected") {
                    inspected = selectedProcess
                }
                .disabled(selectedProcess == nil)
                Spacer()
            }

            Table(items, selection: $selection) {
                TableColumn("PID") { item in
                    Text("\(item.pid)").monospacedDigit()
                }
                .width(min: 50, ideal: 70)
                TableColumn("PPID") { item in
                    Text("\(item.ppid)").monospacedDigit()
                }
                .width(min: 50, ideal: 70)
                TableColumn("UID") { item in
                    Text("\(item.uid)").monospacedDigit()
                }
                .width(min: 50, ideal: 70)
                TableColumn("Name") { item in
                    Text(item.name)
                }
                .width(min: 140, ideal: 200)
                TableColumn("Path") { item in
                    Text(item.path.isEmpty ? "—" : item.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(item.path)
                }
            }
            .contextMenu(forSelectionType: KBProcessKey.self) { keys in
                if let key = keys.first,
                   let process = items.first(where: { $0.id == key }) {
                    Button("Inspect \(process.name)") { inspected = process }
                }
            } primaryAction: { keys in
                if let key = keys.first,
                   let process = items.first(where: { $0.id == key }) {
                    inspected = process
                }
            }
        }
        .sheet(item: $inspected) { process in
            ProcessInspectorView(process: process)
                .environment(model)
        }
    }

    private var selectedProcess: KBProcessInfo? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
    }
}
