import SwiftUI
import KancerberoFilterContract

enum FilterRulesWindow {
    static let id = "filter-rules"
}

/// Enable/disable/install button shared by the Filter tab and the rules window.
struct FilterPowerButton: View {
    @Environment(FilterModel.self) private var filter

    var body: some View {
        switch filter.controller.state {
        case .enabled:
            Button("Disable filter") {
                Task { await filter.disableFilter() }
            }
            .buttonStyle(.bordered)
        case .disabled, .failed:
            Button("Enable filter") {
                Task { await filter.enableFilter() }
            }
            .buttonStyle(.borderedProminent)
        case .notInstalled, .requiresApproval:
            Button("Install filter extension") {
                Task { await filter.enableFilter() }
            }
            .buttonStyle(.borderedProminent)
        case .activating:
            Button("Installing…") {}
                .buttonStyle(.bordered)
                .disabled(true)
        case .unsupported:
            EmptyView()
        }
    }
}

struct FilterRulesView: View {
    @Environment(FilterModel.self) private var filter
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var rulePendingDeletion: FilterRule?
    @State private var selectedRuleID: FilterRule.ID?
    @State private var ruleSortOrder: [KeyPathComparator<FilterRule>] = []
    @State private var rememberedSortOrder: [KeyPathComparator<RememberedDecision>] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusCard
            rulesSection
            rememberedSection
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 560)
        .onChange(of: filter.rules.map(\.id), initial: true) { _, ids in
            if let selected = selectedRuleID, !ids.contains(selected) {
                selectedRuleID = nil
            }
        }
        .alert("Delete rule?",
               isPresented: Binding(
                   get: { rulePendingDeletion != nil },
                   set: { if !$0 { rulePendingDeletion = nil } }
               ),
               presenting: rulePendingDeletion) { rule in
            Button("Delete rule and remembered decisions", role: .destructive) {
                filter.removeRule(id: rule.id)
                selectedRuleID = nil
                rulePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { rulePendingDeletion = nil }
        } message: { rule in
            Text("\(rule.displayName) stops being watched and its Always "
                 + "allow/deny decisions are removed.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KBTheme.connectionsTint)

            VStack(alignment: .leading, spacing: 1) {
                Text("Filter rules")
                    .font(.system(size: 15, weight: .semibold))
                Text("Configured filter, per-process rules and remembered decisions")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Close") { dismissWindow(id: FilterRulesWindow.id) }
                .buttonStyle(.borderless)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Circle()
                    .fill(filter.controller.state.isEnabled ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)

                Text(filter.controller.state.title)
                    .font(.system(size: 12, weight: .semibold))

                Text(filter.isConnected ? "Extension connected"
                                       : "Extension not connected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                FilterPowerButton()
            }

            HStack(spacing: 18) {
                metric("Rules", "\(filter.rules.count)")
                metric("Flows", "\(filter.status?.observedFlows ?? 0)")
                metric("Paused", "\(filter.status?.pausedFlows ?? 0)")
                metric("Clients", "\(filter.status?.clientCount ?? 0)")
            }

            if let error = filter.controller.lastError ?? filter.status?.lastError,
               !error.isEmpty {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.18))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Rules")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(filter.rules.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    if let id = selectedRuleID,
                       let rule = filter.rules.first(where: { $0.id == id }) {
                        rulePendingDeletion = rule
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(selectedRuleID == nil ? Color.secondary : Color.red)
                .disabled(selectedRuleID == nil)
                .help("Delete the selected rule and its remembered decisions")
            }
            if filter.rules.isEmpty {
                emptyState("No rules yet. Watch a process from Processes "
                           + "(shield button or context menu).")
            } else {
                rulesTable
            }
        }
    }

    private var rulesTable: some View {
        Table(filter.rules, selection: $selectedRuleID, sortOrder: $ruleSortOrder) {
            TableColumn("On") { rule in
                Toggle("", isOn: enabledBinding(rule))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(rule.enabled ? "Rule enabled" : "Rule disabled")
            }
            .width(min: 38, ideal: 42)
            TableColumn("Process", value: \.displayName) { rule in
                Text(rule.displayName).lineLimit(1)
            }
            .width(min: 110, ideal: 130)
            TableColumn("Policy", value: \.policy.rawValue) { rule in
                PolicyBadge(policy: rule.policy)
            }
            .width(min: 60, ideal: 70)
            TableColumn("Executable", value: \.executablePath) { rule in
                Text(rule.executablePath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.executablePath)
            }
            .width(min: 150, ideal: 200)
            TableColumn("Created", value: \.createdAt) { rule in
                Text(rule.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 125)
            TableColumn("") { rule in
                Button(role: .destructive) {
                    rulePendingDeletion = rule
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete rule")
            }
            .width(min: 44, ideal: 48)
        }
        .frame(minHeight: 140)
        .contextMenu(forSelectionType: FilterRule.ID.self) { ids in
            if let id = ids.first,
               let rule = filter.rules.first(where: { $0.id == id }) {
                Button("Delete rule…", role: .destructive) {
                    rulePendingDeletion = rule
                }
            }
        }
    }

    private func enabledBinding(_ rule: FilterRule) -> Binding<Bool> {
        Binding(
            get: { rule.enabled },
            set: { filter.setRuleEnabled($0, ruleID: rule.id) }
        )
    }

    private var rememberedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Remembered decisions", detail: "\(filter.remembered.count)")
            if filter.remembered.isEmpty {
                emptyState("No remembered decisions. Approve a flow with "
                           + "“Always allow/deny” to add one.")
            } else {
                rememberedTable
            }
        }
    }

    private var rememberedTable: some View {
        Table(filter.remembered, sortOrder: $rememberedSortOrder) {
            TableColumn("App", value: \.executablePath) { item in
                Text(appName(for: item))
                    .lineLimit(1)
                    .help(item.executablePath)
            }
            .width(min: 120, ideal: 170)
            TableColumn("Destination") { item in
                Text(item.destination ?? "App-wide")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 210)
            TableColumn("Decision") { item in
                Text(item.allow ? "Allow" : "Deny")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.allow ? Color.green : Color.red)
            }
            .width(min: 60, ideal: 70)
            TableColumn("Created", value: \.createdAt) { item in
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 140)
            TableColumn("") { item in
                Button(role: .destructive) {
                    filter.removeRemembered(id: item.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete remembered decision")
            }
            .width(min: 30, ideal: 34)
        }
        .frame(minHeight: 120)
    }

    private func appName(for item: RememberedDecision) -> String {
        let name = URL(fileURLWithPath: item.executablePath).lastPathComponent
        return name.isEmpty ? item.executablePath : name
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
            }
    }
}

private struct PolicyBadge: View {
    let policy: FilterPolicy

    var body: some View {
        Text(policy.title)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                Capsule().fill(color.opacity(0.16))
            }
            .foregroundStyle(color)
    }

    private var color: Color {
        switch policy {
        case .ask: return .orange
        case .allow: return .green
        case .deny: return .red
        }
    }
}
