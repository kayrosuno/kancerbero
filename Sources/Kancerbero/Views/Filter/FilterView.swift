import SwiftUI
import KancerberoCore
import KancerberoFilterContract

struct FilterView: View {
    @Environment(FilterModel.self) private var filter
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow

    private var search: Binding<String> {
        Binding(
            get: { ui.filter.search },
            set: { ui.filter.search = $0 }
        )
    }

    private var sortOrder: Binding<[KeyPathComparator<FlowRecord>]> {
        Binding(
            get: { ui.filter.sortOrder },
            set: { ui.filter.sortOrder = $0 }
        )
    }

    private var displayRows: [FlowRecord] {
        let query = ui.filter.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = query.isEmpty
            ? filter.flows
            : filter.flows.filter { row in
                row.processName.lowercased().contains(query)
                    || row.executablePath.lowercased().contains(query)
                    || (row.remote?.display.lowercased().contains(query) ?? false)
                    || (row.local?.display.lowercased().contains(query) ?? false)
            }
        return ui.filter.sortOrder.isEmpty ? matched : matched.sorted(using: ui.filter.sortOrder)
    }

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            if !filter.controller.isSupported {
                unsupportedState
            } else if !filter.controller.state.isEnabled {
                disabledState
            } else {
                flowsContent
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Filter")
                .font(.system(size: 12, weight: .semibold))

            TextField("Filter flows", text: search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .help("Filter by process, path or endpoint")

            Spacer()

            if filter.controller.isEnabled {
                Text("\(displayRows.count) flows · \(filter.watchedCount) watched")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if filter.isBusy || filter.controller.isActivating {
                ProgressView().controlSize(.mini)
            }

            Button("Rules…") {
                openWindow(id: FilterRulesWindow.id)
            }
            .help("Show configured filters, rules and remembered decisions")

            FilterPowerButton()
        }
    }

    private var unsupportedState: some View {
        placeholder(
            icon: "shield.slash",
            title: "Network filter unavailable",
            message: "This build does not carry the filter system-extension entitlements. Sign with Config/Signing.local.xcconfig (Developer ID + provisioning profiles); see docs/verification.md."
        )
    }

    private var disabledState: some View {
        placeholder(
            icon: "shield.lefthalf.filled",
            title: "Filter is off",
            message: "Enable the filter to observe every flow and require approval for the processes you watch in the Processes tab."
        )
    }

    private var flowsContent: some View {
        VStack(spacing: 8) {
            if let status = filter.status {
                HStack(spacing: 14) {
                    Label("\(status.clientCount) app client", systemImage: "link")
                    Label("\(status.pausedFlows) waiting", systemImage: "pause.circle")
                    Label("\(status.observedFlows) observed", systemImage: "eye")
                    if let error = status.lastError {
                        Text(error)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Table(displayRows, sortOrder: sortOrder) {
                TableColumn("Process", value: \.processName) { row in
                    Text(row.processName)
                        .lineLimit(1)
                        .help(row.executablePath)
                }
                .width(min: 110, ideal: 150)
                TableColumn("PID", value: \.pid) { row in
                    Text("\(row.pid)").monospacedDigit()
                }
                .width(min: 45, ideal: 55)
                TableColumn("Local", value: \.localSortValue) { row in
                    Text(row.local?.display ?? "—")
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 160)
                TableColumn("Remote", value: \.remoteSortValue) { row in
                    Text(row.remote?.display ?? "—")
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .width(min: 130, ideal: 180)
                TableColumn("Proto", value: \.transport) { row in
                    Text(row.transport.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .width(min: 45, ideal: 55)
                TableColumn("RX", value: \.bytesIn) { row in
                    Text(KBFormat.bytes(row.bytesIn)).monospacedDigit()
                }
                .width(min: 70, ideal: 85)
                TableColumn("TX", value: \.bytesOut) { row in
                    Text(KBFormat.bytes(row.bytesOut)).monospacedDigit()
                }
                .width(min: 70, ideal: 85)
                TableColumn("State", value: \.stateSortValue) { row in
                    FlowStateBadge(state: row.state, reason: row.deniedReason)
                }
                .width(min: 90, ideal: 110)
                TableColumn("Started", value: \.startedAt) { row in
                    Text(KBFormat.time(row.startedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .width(min: 65, ideal: 75)
            }

            if !filter.recentBlocks.isEmpty {
                recentBlocks
            }
        }
    }

    private var recentBlocks: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent blocks")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(filter.recentBlocks) { block in
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                    Text(block.processName)
                        .font(.system(size: 10, weight: .medium))
                    Text(block.remote?.display ?? "—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(block.deniedReason ?? "denied")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Spacer()
                    Text(KBFormat.time(block.endedAt ?? block.startedAt))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func placeholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if let error = filter.controller.lastError ?? filter.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            if let guidance = filter.controller.failureGuidance {
                Text(guidance)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            } else if filter.controller.isDevelopmentSigned, filter.controller.state != .enabled {
                Text("Development-signed build: with SIP enabled macOS will reject the system extension. Use a Developer ID + notarized build (scripts/build-release.sh, scripts/notarize.sh, scripts/install-app.sh).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            if let detail = filter.controller.lastErrorDetail {
                DisclosureGroup("Technical details") {
                    Text(detail)
                        .font(.system(size: 9, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10))
                .frame(maxWidth: 440)
                Button("Copy diagnostics") { filter.controller.copyDiagnostics() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
            if filter.controller.state == .requiresApproval {
                Text("Open System Settings → General → Login Items & Extensions → Network Extensions and turn on Kancerbero Filter, then try again.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct FlowStateBadge: View {
    let state: FilterFlowState
    let reason: String?

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
            .help(reason ?? label)
    }

    private var label: String {
        switch state {
        case .observing: return "OBSERVING"
        case .allowed: return "ALLOWED"
        case .denied: return reason.map { "DENIED (\($0))" } ?? "DENIED"
        case .pending: return "WAITING"
        }
    }

    private var color: Color {
        switch state {
        case .observing: return .secondary
        case .allowed: return .green
        case .denied: return .red
        case .pending: return .orange
        }
    }
}

private extension FlowRecord {
    var localSortValue: String { local?.display ?? "" }
    var remoteSortValue: String { remote?.display ?? "" }
    var stateSortValue: String { state.rawValue }
}
