import SwiftUI
import KancerberoCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Interval", selection: $model.interval) {
                    Text("0.5 s").tag(0.5)
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Toggle("Pause", isOn: $model.isPaused)
                    .toggleStyle(.switch)

                Button("Refresh") { model.refreshNow() }

                Spacer()

                Text(model.modeDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            TabView {
                InterfacesView()
                    .tabItem { Label("Interfaces", systemImage: "network") }
                ConnectionsView()
                    .tabItem { Label("Connections", systemImage: "point.3.connected.trianglepath.dotted") }
                ProcessesView()
                    .tabItem { Label("Processes", systemImage: "list.bullet") }
            }
            .padding(8)

            Divider()
            StatusBar()
        }
    }
}

struct InterfacesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Table(model.interfaces.sorted { $0.index < $1.index }) {
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
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var inspected: KBProcessInfo?

    private var rows: [KBNStatSource] {
        model.sources.sorted {
            ($0.counters.rxBytes + $0.counters.txBytes) > ($1.counters.rxBytes + $1.counters.txBytes)
        }
    }

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
            Text("\(rows.count) connections")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Text(source.local.display).monospaced()
            }
            .width(min: 160, ideal: 210)
            TableColumn("Remote") { source in
                Text(source.remote.display).monospaced()
            }
            .width(min: 160, ideal: 210)
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
                Text("\(model.processes.count) processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Table(model.processes.sorted { $0.pid < $1.pid }, selection: $selection) {
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
                }
            }
            .contextMenu(forSelectionType: KBProcessKey.self) { keys in
                if let key = keys.first,
                   let process = model.processes.first(where: { $0.id == key }) {
                    Button("Inspect \(process.name)") { inspected = process }
                }
            } primaryAction: { keys in
                if let key = keys.first,
                   let process = model.processes.first(where: { $0.id == key }) {
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
        return model.processes.first { $0.id == selection }
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            Text("\(model.processes.count) processes")
            Text("\(model.sources.count) connections")
            Text("RX \(KBFormat.rate(model.systemRates.rxBytesPerSecond))")
            Text("TX \(KBFormat.rate(model.systemRates.txBytesPerSecond))")
            Spacer()
            Text(model.usingDaemon ? "source: daemon" : "source: local")
                .foregroundStyle(.secondary)
            if model.privcheck >= 0 {
                Text("privcheck \(model.privcheck)")
            }
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Text(model.lastUpdate.map { "Updated \(KBFormat.time($0))" } ?? "Waiting…")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
