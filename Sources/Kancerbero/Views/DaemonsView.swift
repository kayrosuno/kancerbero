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
            types: ui.daemons.types,
            scopes: ui.daemons.scopes,
            origins: ui.daemons.origins,
            states: ui.daemons.states
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

    private var displayedEntries: [DaemonListEntry] {
        ui.daemons.sortOrder.isEmpty
            ? filteredEntries
            : filteredEntries.sorted(using: ui.daemons.sortOrder)
    }

    private var selectedEntry: DaemonListEntry? {
        guard let selection = ui.daemons.selection else { return nil }
        guard let entry = entries.first(where: { $0.id == selection }) else { return nil }
        return filter.matches(entry.service) ? entry : nil
    }

    var body: some View {
        VStack(spacing: 14) {
            CollapsibleSectionHeader(
                section: .daemons,
                title: "Daemons",
                subtitle: "launchd services, agents and daemons"
            )

            if !ui.cardsCollapsed(for: .daemons) {
                cards
                    .transition(.opacity)
            }

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
                isSelected: ui.daemons.states.contains(.running),
                filterHint: "Toggle running services"
            )
            SummaryCard(
                title: "Stopped",
                value: KBFormat.compactCount(stopped),
                caption: "loaded but idle",
                systemImage: "pause.circle.fill",
                tint: Color(red: 0.94, green: 0.56, blue: 0.18),
                action: { toggleState(.stopped) },
                isSelected: ui.daemons.states.contains(.stopped),
                filterHint: "Toggle stopped services"
            )
            SummaryCard(
                title: "Disabled",
                value: KBFormat.compactCount(disabled),
                caption: "launchd overrides",
                systemImage: "slash.circle.fill",
                tint: Color(red: 0.62, green: 0.42, blue: 0.95),
                action: { toggleState(.disabled) },
                isSelected: ui.daemons.states.contains(.disabled),
                filterHint: "Toggle disabled services"
            )
        }
    }

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                MultiSelectChipBar(
                    selection: bind(\.types),
                    label: "Type",
                    options: [.agent, .daemon],
                    title: { $0.title },
                    systemImage: { $0.systemImage }
                )
                MultiSelectChipBar(
                    selection: bind(\.scopes),
                    label: "Scope",
                    title: { $0.title }
                )
                MultiSelectChipBar(
                    selection: bind(\.origins),
                    label: "Origin",
                    title: { $0.title }
                )
                MultiSelectChipBar(
                    selection: bind(\.states),
                    label: "State",
                    title: { $0.displayName }
                )
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tableCard: some View {
        VStack(spacing: 8) {
            tableFilterHeader

            Table(displayedEntries,
                  selection: bind(\.selection),
                  sortOrder: bind(\.sortOrder)) {
                TableColumn("Label", value: \.labelSortValue) { entry in
                    Text(entry.service.label)
                        .lineLimit(1)
                        .help(entry.service.label)
                }
                .width(min: 180, ideal: 280)

                TableColumn("Type", value: \.typeSortRank) { entry in
                    Text(entry.service.serviceType.singularTitle)
                }
                .width(min: 60, ideal: 70)

                TableColumn("Scope", value: \.scopeSortRank) { entry in
                    Text(entry.service.scope.title)
                }
                .width(min: 55, ideal: 70)

                TableColumn("PID", value: \.pidSortValue) { entry in
                    Text(entry.service.pid.map { String($0) } ?? "—").monospacedDigit()
                }
                .width(min: 45, ideal: 60)

                TableColumn("State", value: \.stateSortRank) { entry in
                    DaemonStateBadge(state: entry.service.state)
                }
                .width(min: 75, ideal: 95)

                TableColumn("Program", value: \.programSortValue) { entry in
                    Text(entry.service.program.isEmpty ? "—" : entry.service.program)
                        .lineLimit(1)
                        .help(entry.service.program)
                }
                .width(min: 140, ideal: 220)

                TableColumn("Plist", value: \.plistSortValue) { entry in
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
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private var tableFilterHeader: some View {
        HStack(spacing: 10) {
            Text("Services")
                .font(.system(size: 12, weight: .semibold))

            TextField("Filter label, program or plist", text: bind(\.search))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .help("Search label, program, arguments or plist")

            Spacer(minLength: 8)

            daemonModePill

            if model.daemonActionInFlight {
                ProgressView().controlSize(.small)
            }
            if let error = model.daemonServicesError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(error)
            }
            Text("\(filteredEntries.count) of \(entries.count) services")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var actionTitle: String {
        pendingAction?.rawValue.capitalized ?? "Action"
    }

    private func toggleState(_ state: KBDaemonState) {
        withAnimation(.snappy(duration: 0.2)) {
            var states = ui.daemons.states
            if states.contains(state) {
                states.remove(state)
            } else {
                states.insert(state)
            }
            ui.daemons.states = states
        }
    }

    private func clearFilters() {
        withAnimation(.snappy(duration: 0.2)) {
            ui.daemons.search = ""
            ui.daemons.types = DaemonFilter.allTypes
            ui.daemons.scopes = DaemonFilter.allScopes
            ui.daemons.origins = DaemonFilter.allOrigins
            ui.daemons.states = DaemonFilter.allStates
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
