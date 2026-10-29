import Darwin
import SwiftUI
import KancerberoCore
import KancerberoFilterContract

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
            TableColumn("RX bit/s") { item in
                Text(KBFormat.bitRate(model.interfaceRates[item.id]?.rxBytesPerSecond ?? 0)).monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("TX bit/s") { item in
                Text(KBFormat.bitRate(model.interfaceRates[item.id]?.txBytesPerSecond ?? 0)).monospacedDigit()
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
    @Environment(UIState.self) private var ui
    @State private var inspected: KBProcessInfo?

    private var selection: Binding<String?> {
        Binding(
            get: { ui.networking.selectedConnection },
            set: { ui.networking.selectedConnection = $0 }
        )
    }

    private var sortOrder: Binding<[KeyPathComparator<KBNStatSource>]> {
        Binding(
            get: { ui.networking.connectionSortOrder },
            set: { ui.networking.connectionSortOrder = $0 }
        )
    }

    private var stateSelection: Binding<Set<NetworkingConnectionState>> {
        Binding(
            get: { ui.networking.connectionStates },
            set: { ui.networking.connectionStates = $0 }
        )
    }

    private var connectionSearch: Binding<String> {
        Binding(
            get: { ui.networking.connectionSearch },
            set: { ui.networking.connectionSearch = $0 }
        )
    }

    private var transports: Binding<Set<NetworkingTransport>> {
        Binding(
            get: { ui.networking.transports },
            set: { ui.networking.transports = $0 }
        )
    }

    private var ipVersions: Binding<Set<NetworkingIPVersion>> {
        Binding(
            get: { ui.networking.ipVersions },
            set: { ui.networking.ipVersions = $0 }
        )
    }

    private var ipGroup: some View {
        CheckboxFilterGroup("IP",
                            selection: ipVersions,
                            optionTitle: { $0.title })
    }

    private var transportGroup: some View {
        CheckboxFilterGroup("Transport",
                            selection: transports,
                            optionTitle: { $0.title })
    }

    private var stateGroup: some View {
        CheckboxFilterGroup("State",
                            selection: stateSelection,
                            options: [.established, .listening, .connecting, .closing, .other],
                            optionTitle: { $0.title },
                            optionHelp: { $0.checkboxHelp })
    }

    private var displayRows: [KBNStatSource] {
        ui.networking.connectionSortOrder.isEmpty
            ? rows
            : rows.sorted(using: ui.networking.connectionSortOrder)
    }

    private var selectedSource: KBNStatSource? {
        guard let id = ui.networking.selectedConnection else { return nil }
        return rows.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("Connections")
                        .font(.system(size: 12, weight: .semibold))

                    TextField("Filter process", text: connectionSearch)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .help("Filter by process name or PID")

                    Spacer(minLength: 8)

                    Button("Inspect Process") {
                        if let source = selectedSource {
                            inspected = process(for: source)
                        }
                    }
                    .disabled(selectedSource == nil)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        ipGroup
                        transportGroup
                        stateGroup
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            ipGroup
                            transportGroup
                        }
                        stateGroup
                    }
                }
            }

            Table(displayRows, selection: selection, sortOrder: sortOrder) {
                TableColumn("Process", value: \.processName) { source in
                    Text(source.processName.isEmpty ? "Unknown" : source.processName)
                    .lineLimit(1)
                    .help(source.processName)
                }
                .width(min: 110, ideal: 140)
                TableColumn("PID", value: \.pid) { source in
                    Text("\(source.pid)").monospacedDigit()
                }
                .width(min: 45, ideal: 55)
                TableColumn("Local", value: \.local, comparator: EndpointComparator()) { source in
                    Text(source.local.display).monospaced().help(source.local.display)
                }
                .width(min: 120, ideal: 170)
                TableColumn("Remote", value: \.remote, comparator: EndpointComparator()) { source in
                    Text(source.remote.display).monospaced().help(source.remote.display)
                }
                .width(min: 120, ideal: 170)
                TableColumn("Proto", value: \.protocolSortRank) { source in
                    Text(source.connectionProtocol.displayName).monospaced()
                }
                .width(min: 45, ideal: 50)
                TableColumn("RX", value: \.counters.rxBytes) { source in
                    Text(KBFormat.bytes(source.counters.rxBytes)).monospacedDigit()
                }
                .width(min: 75, ideal: 80)
                TableColumn("TX", value: \.counters.txBytes) { source in
                    Text(KBFormat.bytes(source.counters.txBytes)).monospacedDigit()
                }
                .width(min: 75, ideal: 80)
                TableColumn("State", value: \.tcpState) { source in
                    Text(source.tcpState.isEmpty ? "—" : source.tcpState)
                }
                .width(min: 75, ideal: 80)
                TableColumn("Iface", value: \.interfaceName) { source in
                    Text(source.interfaceName.isEmpty ? "—" : source.interfaceName).monospaced()
                }
                .width(min: 45, ideal: 55)
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
        .onChange(of: rows.map(\.id), initial: true) { _, ids in
            guard let selected = ui.networking.selectedConnection,
                  !ids.contains(selected) else { return }
            ui.networking.selectedConnection = nil
        }
    }

    private func process(for source: KBNStatSource) -> KBProcessInfo {
        model.processes.first { $0.pid == source.pid }
            ?? KBProcessInfo(pid: source.pid, name: source.processName)
    }
}

private extension KBNStatSource {
    var protocolSortRank: Int {
        switch connectionProtocol {
        case .tcp4: return 0
        case .tcp6: return 1
        case .udp4: return 2
        case .udp6: return 3
        case .unix: return 4
        case .other: return 5
        }
    }
}

/// Numeric endpoint ordering (family, address, port) instead of comparing the
/// rendered "address:port" text, which would sort 10.x before 2.x.
private struct EndpointComparator: SortComparator {
    var order: SortOrder = .forward

    func compare(_ lhs: KBEndpoint, _ rhs: KBEndpoint) -> ComparisonResult {
        oriented(Self.compare(lhs, rhs))
    }

    private func oriented(_ result: ComparisonResult) -> ComparisonResult {
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private static func compare(_ lhs: KBEndpoint, _ rhs: KBEndpoint) -> ComparisonResult {
        let lhsRank = familyRank(lhs.family)
        let rhsRank = familyRank(rhs.family)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank ? .orderedAscending : .orderedDescending
        }

        if lhs.family == 4,
           let left = ipv4Value(lhs.address),
           let right = ipv4Value(rhs.address),
           left != right {
            return left < right ? .orderedAscending : .orderedDescending
        }

        if lhs.family == 6,
           let left = ipv6Bytes(lhs.address),
           let right = ipv6Bytes(rhs.address) {
            for (a, b) in zip(left, right) where a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
        }

        let text = lhs.address.localizedStandardCompare(rhs.address)
        if text != .orderedSame { return text }
        if lhs.port != rhs.port {
            return lhs.port < rhs.port ? .orderedAscending : .orderedDescending
        }
        if lhs.scopeID != rhs.scopeID {
            return lhs.scopeID < rhs.scopeID ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    private static func familyRank(_ family: UInt8) -> Int {
        switch family {
        case 4: return 0
        case 6: return 1
        default: return 2
        }
    }

    private static func ipv4Value(_ address: String) -> UInt32? {
        var addr = in_addr()
        guard inet_pton(AF_INET, address, &addr) == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)
    }

    private static func ipv6Bytes(_ address: String) -> [UInt8]? {
        let host = address.split(separator: "%", maxSplits: 1).first.map(String.init)
            ?? address
        var addr = in6_addr()
        guard inet_pton(AF_INET6, host, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }
}

struct ProcessesView: View {
    let rows: [ProcessInventoryRow]
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(FilterModel.self) private var filterModel
    @State private var inspected: KBProcessInfo?

    private var selection: Binding<KBProcessKey?> {
        Binding(
            get: { ui.networking.selectedProcess },
            set: { ui.networking.selectedProcess = $0 }
        )
    }

    private var sortOrder: Binding<[KeyPathComparator<ProcessInventoryRow>]> {
        Binding(
            get: { ui.networking.processSortOrder },
            set: { ui.networking.processSortOrder = $0 }
        )
    }

    private var search: Binding<String> {
        Binding(
            get: { ui.networking.processSearch },
            set: { ui.networking.processSearch = $0 }
        )
    }

    private var displayRows: [ProcessInventoryRow] {
        ui.networking.processSortOrder.isEmpty
            ? rows
            : rows.sorted(using: ui.networking.processSortOrder)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Processes")
                    .font(.system(size: 12, weight: .semibold))

                TextField("Filter processes", text: search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .help("Filter by name, path, PID or user")

                Spacer()

                Button("Inspect Selected") {
                    inspected = selectedRow?.process
                }
                .disabled(selectedRow == nil)
            }

            Table(displayRows, selection: selection, sortOrder: sortOrder) {
                TableColumn("Process", value: \.process.name) { row in
                    Text(displayName(row))
                        .lineLimit(1)
                        .help(displayName(row))
                }
                .width(min: 110, ideal: 150)
                TableColumn("PID", value: \.process.pid) { row in
                    Text("\(row.process.pid)").monospacedDigit()
                }
                .width(min: 50, ideal: 60)
                TableColumn("Guard") { row in
                    guardButton(for: row)
                }
                .width(min: 46, ideal: 54)
                TableColumn("Protocols", value: \.protocolSortRank) { row in
                    ProcessProtocolBadges(tags: row.protocols)
                }
                .width(min: 150, ideal: 230)
                TableColumn("Sockets", value: \.socketCount) { row in
                    Text(socketText(row))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(row.hasSocketData ? .primary : .secondary)
                        .help(socketHelp(row))
                }
                .width(min: 140, ideal: 175)
                TableColumn("Flows", value: \.connectionCount) { row in
                    Text(row.connectionCount > 0 ? "\(row.connectionCount)" : "—")
                        .monospacedDigit()
                        .help(row.listeningCount > 0
                              ? "\(row.listeningCount) listening" : "")
                }
                .width(min: 50, ideal: 60)
                TableColumn("RX", value: \.counters.rxBytes) { row in
                    Text(row.connectionCount > 0
                         ? KBFormat.bytes(row.counters.rxBytes) : "—")
                        .monospacedDigit()
                }
                .width(min: 75, ideal: 90)
                TableColumn("TX", value: \.counters.txBytes) { row in
                    Text(row.connectionCount > 0
                         ? KBFormat.bytes(row.counters.txBytes) : "—")
                        .monospacedDigit()
                }
                .width(min: 75, ideal: 90)
                TableColumn("Path", value: \.process.path) { row in
                    Text(row.process.path.isEmpty ? "—" : row.process.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(row.process.path)
                }
                .width(min: 120, ideal: 160)
            }
            .contextMenu(forSelectionType: KBProcessKey.self) { keys in
                if let key = keys.first,
                   let row = rows.first(where: { $0.id == key }) {
                    Button("Inspect \(displayName(row))") {
                        inspected = row.process
                    }
                    Divider()
                    if filterModel.isWatched(row.process) {
                        Button("Stop watching network access") {
                            filterModel.unwatch(row.process)
                        }
                        Menu("Policy") {
                            ForEach(FilterPolicy.allCases) { policy in
                                Button(policy.title) {
                                    filterModel.setPolicy(policy, for: row.process)
                                }
                                .disabled(filterModel.policy(for: row.process) == policy)
                            }
                        }
                    } else {
                        Button("Watch network access") {
                            filterModel.watch(row.process)
                        }
                    }
                }
            } primaryAction: { keys in
                if let key = keys.first,
                   let row = rows.first(where: { $0.id == key }) {
                    inspected = row.process
                }
            }
        }
        .sheet(item: $inspected) { process in
            ProcessInspectorView(process: process)
                .environment(model)
        }
        .onChange(of: rows.map(\.id), initial: true) { _, ids in
            guard let selected = ui.networking.selectedProcess,
                  !ids.contains(selected) else { return }
            ui.networking.selectedProcess = nil
        }
    }

    @ViewBuilder
    private func guardButton(for row: ProcessInventoryRow) -> some View {
        let watched = filterModel.isWatched(row.process)
        let policy = filterModel.policy(for: row.process)
        Button {
            if watched {
                filterModel.unwatch(row.process)
            } else {
                filterModel.watch(row.process)
            }
        } label: {
            Image(systemName: watched ? "shield.lefthalf.filled" : "shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(watched ? Color.orange : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(row.process.path.isEmpty)
        .help(watched
              ? "Watching network access (\(policy?.title ?? "Ask"))"
              : "Watch network access and ask before each connection")
    }

    private var selectedRow: ProcessInventoryRow? {
        guard let selection = ui.networking.selectedProcess else { return nil }
        return rows.first { $0.id == selection }
    }

    private func displayName(_ row: ProcessInventoryRow) -> String {
        row.process.name.isEmpty ? "Process \(row.process.pid)" : row.process.name
    }

    private func socketText(_ row: ProcessInventoryRow) -> String {
        guard let types = row.socketTypes else { return "—" }
        var parts: [String] = []
        if types.stream > 0 { parts.append("\(types.stream) stream") }
        if types.dgram > 0 { parts.append("\(types.dgram) dgram") }
        if types.raw > 0 { parts.append("\(types.raw) raw") }
        if types.seqpacket > 0 { parts.append("\(types.seqpacket) seqpacket") }
        if types.otherType > 0 { parts.append("\(types.otherType) other") }
        return parts.isEmpty ? "0" : parts.joined(separator: " · ")
    }

    private func socketHelp(_ row: ProcessInventoryRow) -> String {
        guard row.hasSocketData else {
            return row.restricted
                ? "Socket details unavailable (permissions)"
                : "Socket scan not available yet"
        }
        if row.restricted { return "Partial: some sockets were not readable" }
        if row.truncated { return "Truncated at the per-process socket cap" }
        return "\(row.socketCount) unique sockets"
    }
}

private struct ProcessProtocolBadges: View {
    let tags: Set<ProcessProtocolTag>

    var body: some View {
        let ordered = tags.sorted { $0.sortRank < $1.sortRank }
        if ordered.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else {
            HStack(spacing: 3) {
                ForEach(ordered) { tag in
                    Text(tag.title)
                        .font(.system(size: 8, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background {
                            Capsule().fill(color(tag).opacity(0.15))
                        }
                        .foregroundStyle(color(tag))
                }
            }
            .help(ordered.map(\.title).joined(separator: ", "))
        }
    }

    private func color(_ tag: ProcessProtocolTag) -> Color {
        switch tag {
        case .tcp4: return KBTheme.downloadTint
        case .tcp6: return Color(red: 0.35, green: 0.70, blue: 0.95)
        case .udp4: return KBTheme.connectionsTint
        case .udp6: return Color(red: 0.40, green: 0.80, blue: 0.72)
        case .unix: return KBTheme.uploadTint
        case .raw4: return KBTheme.processesTint
        case .raw6: return Color(red: 0.90, green: 0.42, blue: 0.25)
        case .other: return Color(red: 0.55, green: 0.57, blue: 0.63)
        }
    }
}
