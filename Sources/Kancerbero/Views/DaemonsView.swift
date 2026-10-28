import AppKit
import SwiftUI
import KancerberoCore

struct DaemonsView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    @State private var pendingAction: KBDaemonAction?
    @State private var pendingService: KBDaemonService?
    @State private var showConfirmation = false

    private func bind<Value>(
        _ keyPath: WritableKeyPath<DaemonsUIState, Value>
    ) -> Binding<Value> {
        Binding(
            get: { ui.daemons[keyPath: keyPath] },
            set: { ui.daemons[keyPath: keyPath] = $0 }
        )
    }

    private var filter: DaemonFilter {
        DaemonFilter(
            search: ui.daemons.search,
            type: ui.daemons.type.serviceType,
            scope: ui.daemons.scope,
            origin: ui.daemons.origin,
            state: ui.daemons.state
        )
    }

    /// Counts on the cards ignore the state facet so each number matches the
    /// rows shown after tapping it, even with other facets active.
    private var baseFilter: DaemonFilter { filter.clearingState() }

    private var entries: [DaemonListEntry] { model.daemonEntries }

    private var baseEntries: [DaemonListEntry] {
        entries.filter { baseFilter.matches($0.service) }
    }

    private var filteredEntries: [DaemonListEntry] {
        entries.filter { filter.matches($0.service) }
    }

    private var selectedEntry: DaemonListEntry? {
        guard let selection = ui.daemons.selection else { return nil }
        guard let entry = entries.first(where: { $0.id == selection }) else { return nil }
        return filter.matches(entry.service) ? entry : nil
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            cards
            controls
            HStack(spacing: 12) {
                tableCard
                if let entry = selectedEntry {
                    DaemonDetailView(
                        service: entry.service,
                        domains: entry.domains,
                        inFlight: model.daemonActionInFlight,
                        canControlSystem: model.canControlSystem,
                        statusMessage: model.daemonActionMessage,
                        onAction: { requestAction($0, for: entry.service) },
                        onReveal: { reveal(entry.service) },
                        onClose: { ui.daemons.selection = nil }
                    )
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.28), value: ui.daemons.selection)
        }
        .padding(.horizontal, KBTheme.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await refreshLoop() }
        .onChange(of: filter) { _, _ in
            reconcileSelection()
        }
        .alert(actionTitle, isPresented: $showConfirmation, presenting: pendingService) { service in
            Button("Cancel", role: .cancel) { clearPending() }
            Button(actionTitle,
                   role: pendingAction == .stop || pendingAction == .disable ? .destructive : nil) {
                performPendingAction(service)
            }
        } message: { service in
            Text("\(actionTitle) \(service.label) in the \(service.domain.displayName) domain?")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daemons")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("launchd services, agents and daemons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            daemonModePill

            TextField("Search label, program, arguments or plist", text: bind(\.search))
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            Button {
                Task { await model.refreshDaemons() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh services")
        }
    }

    private var daemonModePill: some View {
        let tint: Color = model.usingDaemon
            ? (model.daemonIsRoot ? .green : .orange)
            : .gray
        let label = model.usingDaemon
            ? (model.daemonIsRoot ? "Daemon · root" : "Daemon · user")
            : "Local mode"
        return Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
            .foregroundStyle(tint)
            .help(daemonModeHelp)
            .accessibilityLabel(daemonModeHelp)
    }

    private var daemonModeHelp: String {
        guard model.usingDaemon else {
            return "Local mode: no background daemon; system services cannot be controlled."
        }
        return model.daemonIsRoot
            ? "The background daemon runs as root; system services can be controlled."
            : "The daemon is connected without root; system services cannot be controlled."
    }

    private var cards: some View {
        let base = baseEntries
        let running = base.filter { $0.service.state == .running }.count
        let stopped = base.filter { $0.service.state == .stopped }.count
        let disabled = base.filter { $0.service.state == .disabled }.count
        let showingAll = !filter.hasFacets && !filter.hasSearch

        return LazyVGrid(columns: KBTheme.summaryColumns,
                         spacing: KBTheme.summaryGridSpacing) {
            SummaryCard(
                title: "Services",
                value: KBFormat.compactCount(base.count),
                caption: "matching filters",
                systemImage: "list.bullet.rectangle",
                tint: Color(red: 0.16, green: 0.62, blue: 0.94),
                action: { clearFilters() },
                isSelected: showingAll,
                filterHint: "Clear all filters"
            )
            SummaryCard(
                title: "Running",
                value: KBFormat.compactCount(running),
                caption: "active jobs",
                systemImage: "bolt.fill",
                tint: Color(red: 0.20, green: 0.70, blue: 0.42),
                action: { toggleState(.running) },
                isSelected: ui.daemons.state == .running,
                filterHint: "Show running services"
            )
            SummaryCard(
                title: "Stopped",
                value: KBFormat.compactCount(stopped),
                caption: "loaded but idle",
                systemImage: "pause.circle.fill",
                tint: Color(red: 0.94, green: 0.56, blue: 0.18),
                action: { toggleState(.stopped) },
                isSelected: ui.daemons.state == .stopped,
                filterHint: "Show stopped services"
            )
            SummaryCard(
                title: "Disabled",
                value: KBFormat.compactCount(disabled),
                caption: "launchd overrides",
                systemImage: "slash.circle.fill",
                tint: Color(red: 0.62, green: 0.42, blue: 0.95),
                action: { toggleState(.disabled) },
                isSelected: ui.daemons.state == .disabled,
                filterHint: "Show disabled services"
            )
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    PillTabBar(selection: bind(\.type))

                    filterPicker("Scope", selection: bind(\.scope),
                                 title: { $0.title })
                    filterPicker("Origin", selection: bind(\.origin),
                                 title: { $0.title })
                    filterPicker("State", selection: bind(\.state),
                                 title: { $0.displayName })
                }
            }

            Spacer(minLength: 8)

            if model.daemonActionInFlight {
                ProgressView().controlSize(.small)
            }
            Text("\(filteredEntries.count) of \(entries.count) services")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let error = model.daemonServicesError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(error)
            }
        }
    }

    private func filterPicker<Option: CaseIterable & Identifiable & Hashable>(
        _ label: String,
        selection: Binding<Option?>,
        title: @escaping (Option) -> String
    ) -> some View {
        Picker(label, selection: selection) {
            Text("All").tag(Optional<Option>.none)
            ForEach(Array(Option.allCases)) { option in
                Text(title(option)).tag(Optional(option))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    private var tableCard: some View {
        VStack(spacing: 0) {
            Table(filteredEntries, selection: bind(\.selection)) {
                TableColumn("Label") { entry in
                    Text(entry.service.label)
                        .lineLimit(1)
                        .help(entry.service.label)
                }
                .width(min: 180, ideal: 280)

                TableColumn("Type") { entry in
                    Text(entry.service.serviceType.singularTitle)
                }
                .width(min: 60, ideal: 70)

                TableColumn("Scope") { entry in
                    Text(entry.service.scope.title)
                }
                .width(min: 55, ideal: 70)

                TableColumn("PID") { entry in
                    Text(entry.service.pid.map { String($0) } ?? "—").monospacedDigit()
                }
                .width(min: 45, ideal: 60)

                TableColumn("State") { entry in
                    DaemonStateBadge(state: entry.service.state)
                }
                .width(min: 75, ideal: 95)

                TableColumn("Program") { entry in
                    Text(entry.service.program.isEmpty ? "—" : entry.service.program)
                        .lineLimit(1)
                        .help(entry.service.program)
                }
                .width(min: 140, ideal: 220)

                TableColumn("Plist") { entry in
                    Text(entry.service.plistPath.isEmpty
                         ? "—"
                         : (entry.service.plistPath as NSString).lastPathComponent)
                        .lineLimit(1)
                        .help(entry.service.plistPath)
                }
                .width(min: 120, ideal: 180)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                if let id = keys.first,
                   let entry = entries.first(where: { $0.id == id }) {
                    Button("Start") { requestAction(.start, for: entry.service) }
                    Button("Restart") { requestAction(.restart, for: entry.service) }
                    Button("Stop") { requestAction(.stop, for: entry.service) }
                    Divider()
                    Button(entry.service.isDisabled ? "Enable" : "Disable") {
                        requestAction(entry.service.isDisabled ? .enable : .disable,
                                      for: entry.service)
                    }
                    Button("Reveal plist") { reveal(entry.service) }
                }
            } primaryAction: { keys in
                if let id = keys.first { ui.daemons.selection = id }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
        .overlay {
            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No services match the current filters")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private var actionTitle: String {
        pendingAction?.rawValue.capitalized ?? "Action"
    }

    private func toggleState(_ state: KBDaemonState) {
        withAnimation(.snappy(duration: 0.2)) {
            ui.daemons.state = ui.daemons.state == state ? nil : state
        }
    }

    private func clearFilters() {
        withAnimation(.snappy(duration: 0.2)) {
            ui.daemons.search = ""
            ui.daemons.type = .all
            ui.daemons.scope = nil
            ui.daemons.origin = nil
            ui.daemons.state = nil
        }
    }

    private func refreshLoop() async {
        await model.refreshDaemons()
        applyPreselection()
        reconcileSelection()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            await model.refreshDaemons()
            applyPreselection()
            reconcileSelection()
        }
    }

    private func applyPreselection() {
        guard ui.daemons.selection == nil,
              let label = ui.daemons.pendingSelectionLabel else { return }
        if let match = entries.first(where: { $0.service.label == label }) {
            ui.daemons.selection = match.id
        }
        if !entries.isEmpty {
            ui.daemons.pendingSelectionLabel = nil
        }
    }

    private func reconcileSelection() {
        guard let selection = ui.daemons.selection else { return }
        let stillVisible = entries.contains {
            $0.id == selection && filter.matches($0.service)
        }
        if !stillVisible {
            ui.daemons.selection = nil
        }
    }

    private func requestAction(_ action: KBDaemonAction, for service: KBDaemonService) {
        if service.domain == .system || action == .stop || action == .disable {
            pendingAction = action
            pendingService = service
            showConfirmation = true
        } else {
            perform(action, on: service)
        }
    }

    private func performPendingAction(_ service: KBDaemonService) {
        guard let action = pendingAction else { return }
        perform(action, on: service)
        clearPending()
    }

    private func clearPending() {
        pendingAction = nil
        pendingService = nil
    }

    private func perform(_ action: KBDaemonAction, on service: KBDaemonService) {
        Task {
            _ = await model.performDaemonAction(KBDaemonActionRequest(
                label: service.label,
                domain: service.domain,
                action: action,
                plistPath: service.plistPath.isEmpty ? nil : service.plistPath
            ))
        }
    }

    private func reveal(_ service: KBDaemonService) {
        guard !service.plistPath.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: service.plistPath)])
    }
}
