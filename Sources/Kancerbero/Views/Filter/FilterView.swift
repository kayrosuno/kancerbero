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
            blockAllBanner
            if !filter.controller.isSupported {
                unsupportedState
            } else if !filter.controller.state.isEnabled {
                disabledState
            } else {
                flowsContent
            }
        }
        .animation(.snappy(duration: 0.2), value: filter.blockAllNewConnections)
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

    /// Always visible: it also renders in the unsupported/disabled states so
    /// the armed flag survives (and is explained) while the filter is off.
    private var blockAllBanner: some View {
        let active = filter.blockAllNewConnections
        let tint = active ? KBTheme.approvalDenyTint : Color.secondary
        let binding = Binding(
            get: { filter.blockAllNewConnections },
            set: { filter.setBlockAllNewConnections($0) }
        )

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(active ? 0.20 : 0.10))
                    .frame(width: 30, height: 30)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(active ? "Blocking new connections"
                                : "Block all new connections")
                        .font(.system(size: 12, weight: .semibold))
                    if active {
                        BlockingPulse()
                    }
                }
                Text(active
                     ? "Every new connection is denied, including processes with Allow rules or remembered decisions. Existing connections stay open."
                     : "Deny every new connection from every process. Applies only while the filter extension is running.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if active && !filter.controller.state.isEnabled {
                    Text("The filter is off — blocking starts when you enable it.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 8)

            Toggle("Block all new connections", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(KBTheme.approvalDenyTint)
                .controlSize(.small)
                .accessibilityLabel("Block all new connections")
                .help(active
                      ? "Stop blocking new connections"
                      : "Deny every new network connection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(active
                      ? AnyShapeStyle(LinearGradient(
                            colors: [KBTheme.approvalDenyTint.opacity(0.20),
                                     KBTheme.approvalDenyTint.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.gray.opacity(0.08)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(active
                              ? KBTheme.approvalDenyTint.opacity(0.45)
                              : Color.gray.opacity(0.15),
                              lineWidth: 1)
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

/// Small red pulse matching `LiveDot`'s state-driven animation (a repeating
/// `symbolEffect` broke offscreen window captures).
private struct BlockingPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .stroke(KBTheme.approvalDenyTint.opacity(0.5), lineWidth: 1)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulsing ? 2.4 : 1)
                    .opacity(pulsing ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false),
                               value: pulsing)
            }
            Circle()
                .fill(KBTheme.approvalDenyTint)
                .frame(width: 7, height: 7)
        }
        .frame(width: 16, height: 16)
        .onAppear { pulsing = true }
        .accessibilityHidden(true)
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
