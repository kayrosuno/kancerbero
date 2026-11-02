import Darwin
import SwiftUI
import KancerberoCore
import KancerberoFilterContract

/// Interfaces table row: counters live on KBInterfaceInfo but the rates live
/// in AppModel, so sorting by RX/TX bit/s needs a wrapper row.
struct InterfaceRow: Identifiable {
    let item: KBInterfaceInfo
    let rxRate: Double
    let txRate: Double

    var id: UInt32 { item.id }
    var kindText: String { item.kind.displayName }
    var stateText: String { item.stateDescription }
    /// Up first, then Dormant, then Down.
    var stateRank: Int {
        if !item.isUp { return 2 }
        return item.isRunning ? 0 : 1
    }
}

struct InterfacesView: View {
    let items: [KBInterfaceInfo]
    let context: String
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    private var search: Binding<String> {
        Binding(
            get: { ui.networking.interfaceSearch },
            set: { ui.networking.interfaceSearch = $0 }
        )
    }

    private var sortOrder: Binding<[KeyPathComparator<InterfaceRow>]> {
        Binding(
            get: { ui.networking.interfaceSortOrder },
            set: { ui.networking.interfaceSortOrder = $0 }
        )
    }

    private var rows: [InterfaceRow] {
        items.map { item in
            let rates = model.interfaceRates[item.id]
            return InterfaceRow(item: item,
                                rxRate: rates?.rxBytesPerSecond ?? 0,
                                txRate: rates?.txBytesPerSecond ?? 0)
        }
    }

    private var displayRows: [InterfaceRow] {
        ui.networking.interfaceSortOrder.isEmpty
            ? rows
            : rows.sorted(using: ui.networking.interfaceSortOrder)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Interfaces")
                    .font(.system(size: 12, weight: .semibold))

                TextField("Filter interfaces", text: search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .help("Filter by name, type or state")

                Spacer(minLength: 8)

                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            Table(displayRows, sortOrder: sortOrder) {
                TableColumn("Interface", value: \.item.name) { row in
                    Text(row.item.name).monospaced()
                }
                .width(min: 80, ideal: 100)
                TableColumn("Type", value: \.kindText) { row in
                    Text(row.kindText)
                }
                .width(min: 70, ideal: 90)
                TableColumn("State", value: \.stateRank) { row in
                    Text(row.stateText)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Received", value: \.item.counters.rxBytes) { row in
                    Text(KBFormat.bytes(row.item.counters.rxBytes)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn("Sent", value: \.item.counters.txBytes) { row in
                    Text(KBFormat.bytes(row.item.counters.txBytes)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn("RX bit/s", value: \.rxRate) { row in
                    Text(KBFormat.bitRate(row.rxRate)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn("TX bit/s", value: \.txRate) { row in
                    Text(KBFormat.bitRate(row.txRate)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn("MTU", value: \.item.mtu) { row in
                    Text("\(row.item.mtu)").monospacedDigit()
                }
                .width(min: 50, ideal: 60)
            }
        }
    }
}

struct ConnectionsView: View {
    let rows: [KBNStatSource]
    let context: String
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

    private var connectionSearch: Binding<String> {
        Binding(
            get: { ui.networking.connectionSearch },
            set: { ui.networking.connectionSearch = $0 }
        )
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
            HStack(spacing: 10) {
                Text("Connections")
                    .font(.system(size: 12, weight: .semibold))

                TextField("Filter process", text: connectionSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .help("Filter by process name or PID")

                Button("Inspect Process") {
                    if let source = selectedSource {
                        inspected = process(for: source)
                    }
                }
                .disabled(selectedSource == nil)

                Spacer(minLength: 8)

                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
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
                TableColumn("State", value: \.stateDisplay) { source in
                    Text(source.stateDisplay)
                }
                .width(min: 75, ideal: 80)
                TableColumn("RX", value: \.counters.rxBytes) { source in
                    Text(KBFormat.bytes(source.counters.rxBytes)).monospacedDigit()
                }
                .width(min: 75, ideal: 80)
                TableColumn("TX", value: \.counters.txBytes) { source in
                    Text(KBFormat.bytes(source.counters.txBytes)).monospacedDigit()
                }
                .width(min: 75, ideal: 80)
                TableColumn("Rate", value: \.rates.totalBytesPerSecond) { source in
                    Text(KBFormat.bitRate(source.rates.totalBytesPerSecond))
                        .monospacedDigit()
                        .help("RX \(KBFormat.bitRate(source.rates.rxBytesPerSecond)) · "
                              + "TX \(KBFormat.bitRate(source.rates.txBytesPerSecond))")
                }
                .width(min: 80, ideal: 96)
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

    /// TCP flows show their state; UDP has no TCP state, so show the transport.
    var stateDisplay: String {
        if !tcpState.isEmpty { return tcpState }
        switch connectionProtocol {
        case .udp4, .udp6: return "Datagram"
        default: return "—"
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
    let context: String
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

    @TableColumnBuilder<ProcessInventoryRow, KeyPathComparator<ProcessInventoryRow>>
    private var processColumns: some TableColumnContent<ProcessInventoryRow,
                                                        KeyPathComparator<ProcessInventoryRow>> {
        Group {
            TableColumn("Process", value: \ProcessInventoryRow.process.name) { row in
                ProcessNameCell(name: displayName(row))
            }
            .width(min: 110, ideal: 150)
            TableColumn("PID", value: \ProcessInventoryRow.process.pid) { row in
                Text("\(row.process.pid)").monospacedDigit()
            }
            .width(min: 50, ideal: 60)
            TableColumn("Guard") { row in
                guardCell(for: row)
            }
            .width(min: 64, ideal: 78)
        }
        Group {
            TableColumn("Domain", value: \ProcessInventoryRow.domainSortRank) { row in
                SocketBadges(labels: row.domainBadgeLabels,
                             details: row.signatureDetails.isEmpty
                                ? row.domainLabels : row.signatureDetails,
                             kind: .domain)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Protocols", value: \ProcessInventoryRow.protocolSortRank) { row in
                SocketBadges(labels: row.protocolLabels,
                             details: row.signatureDetails,
                             kind: .protocolKind)
            }
            .width(min: 80, ideal: 120)
            TableColumn("Type", value: \ProcessInventoryRow.socketCount) { row in
                SocketTypeCell(row: row)
            }
            .width(min: 140, ideal: 175)
            TableColumn("Flows", value: \ProcessInventoryRow.connectionCount) { row in
                FlowsCell(row: row)
            }
            .width(min: 50, ideal: 60)
        }
        Group {
            TableColumn("RX", value: \ProcessInventoryRow.counters.rxBytes) { row in
                ByteCounterCell(text: row.connectionCount > 0
                                ? KBFormat.bytes(row.counters.rxBytes) : "—")
            }
            .width(min: 75, ideal: 90)
            TableColumn("TX", value: \ProcessInventoryRow.counters.txBytes) { row in
                ByteCounterCell(text: row.connectionCount > 0
                                ? KBFormat.bytes(row.counters.txBytes) : "—")
            }
            .width(min: 75, ideal: 90)
            TableColumn("Rate", value: \ProcessInventoryRow.rates.totalBytesPerSecond) { row in
                ProcessRateCell(row: row)
            }
            .width(min: 70, ideal: 80)
            TableColumn("Path", value: \ProcessInventoryRow.process.path) { row in
                ProcessPathCell(path: row.process.path)
            }
            .width(min: 120, ideal: 130)
        }
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

                Button("Inspect Selected") {
                    inspected = selectedRow?.process
                }
                .disabled(selectedRow == nil)

                Spacer()

                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            Table(displayRows, selection: selection, sortOrder: sortOrder) {
                processColumns
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
    private func guardCell(for row: ProcessInventoryRow) -> some View {
        let watched = filterModel.isWatched(row.process)
        let policy = filterModel.policy(for: row.process)

        HStack(spacing: 4) {
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
            .accessibilityLabel(watched ? "Stop watching network access"
                                        : "Watch network access")
            .accessibilityValue(policy?.title ?? "Ask")

            if watched {
                PolicyBadge(policy: policy ?? .ask)
                    .help(policy?.detail ?? FilterPolicy.ask.detail)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedRow: ProcessInventoryRow? {
        guard let selection = ui.networking.selectedProcess else { return nil }
        return rows.first { $0.id == selection }
    }

    private func displayName(_ row: ProcessInventoryRow) -> String {
        row.process.name.isEmpty ? "Process \(row.process.pid)" : row.process.name
    }

}

private extension ProcessInventoryRow {
    var socketTypeText: String {
        guard let types = socketTypes else { return "—" }
        var parts: [String] = []
        if types.stream > 0 { parts.append("\(types.stream) stream") }
        if types.dgram > 0 { parts.append("\(types.dgram) dgram") }
        if types.raw > 0 { parts.append("\(types.raw) raw") }
        if types.seqpacket > 0 { parts.append("\(types.seqpacket) seqpacket") }
        if types.otherType > 0 { parts.append("\(types.otherType) other") }
        return parts.isEmpty ? "0" : parts.joined(separator: " · ")
    }

    var socketTypeHelp: String {
        guard hasSocketData else {
            return restricted
                ? "Socket details unavailable (permissions)"
                : "Socket scan not available yet"
        }
        if restricted { return "Partial: some sockets were not readable" }
        if truncated { return "Truncated at the per-process socket cap" }
        if socketSignaturesTruncated {
            return "\(socketCount) unique sockets; some distinct socket "
                + "signatures were not recorded"
        }
        if socketSignatures == nil {
            return "\(socketCount) unique sockets (signature detail "
                + "unavailable; filters use aggregate counts)"
        }
        return "\(socketCount) unique sockets"
    }
}

private struct ProcessNameCell: View {
    let name: String

    var body: some View {
        Text(name)
            .lineLimit(1)
            .help(name)
    }
}

private struct SocketTypeCell: View {
    let row: ProcessInventoryRow

    var body: some View {
        Text(row.socketTypeText)
            .font(.system(size: 10))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(row.hasSocketData ? .primary : .secondary)
            .help(row.socketTypeHelp)
    }
}

private struct FlowsCell: View {
    let row: ProcessInventoryRow

    var body: some View {
        Text(row.connectionCount > 0 ? "\(row.connectionCount)" : "—")
            .monospacedDigit()
            .help(row.listeningCount > 0 ? "\(row.listeningCount) listening" : "")
    }
}

private struct ByteCounterCell: View {
    let text: String

    var body: some View {
        Text(text).monospacedDigit()
    }
}

private struct ProcessRateCell: View {
    let row: ProcessInventoryRow

    var body: some View {
        Text(row.connectionCount > 0
             ? KBFormat.bitRate(row.rates.totalBytesPerSecond) : "—")
            .monospacedDigit()
            .help(row.connectionCount > 0
                  ? "RX \(KBFormat.bitRate(row.rates.rxBytesPerSecond)) · "
                    + "TX \(KBFormat.bitRate(row.rates.txBytesPerSecond))"
                  : "")
    }
}

private struct ProcessPathCell: View {
    let path: String

    var body: some View {
        Text(path.isEmpty ? "—" : path)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(path)
    }
}

private enum SocketBadgeKind {
    case domain
    case protocolKind
}

private struct SocketBadges: View {
    let labels: [String]
    var details: [String] = []
    let kind: SocketBadgeKind

    var body: some View {
        content
            .help(details.isEmpty
                  ? labels.joined(separator: ", ")
                  : details.joined(separator: "\n"))
    }

    @ViewBuilder
    private var content: some View {
        if labels.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else {
            HStack(spacing: 3) {
                ForEach(labels, id: \.self) { label in
                    badge(label, color: color(for: label))
                }
            }
        }
    }

    private func color(for label: String) -> Color {
        switch kind {
        case .domain:
            switch label {
            case "INET", "AF_INET": return KBTheme.downloadTint
            case "INET6", "AF_INET6": return KBTheme.uploadTint
            case "UNIX", "AF_UNIX": return KBTheme.processesTint
            default: return Color(red: 0.62, green: 0.64, blue: 0.70)
            }
        case .protocolKind:
            switch label {
            case "TCP": return KBTheme.downloadTint
            case "UDP": return KBTheme.connectionsTint
            default: return KBTheme.processesTint
            }
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 7.5, weight: .semibold))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .lineLimit(1)
            .background {
                Capsule().fill(color.opacity(0.15))
            }
            .foregroundStyle(color)
    }
}


