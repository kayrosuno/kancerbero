import AppKit
import SwiftUI
import KancerberoCore

private enum DaemonDomainFilter: String, CaseIterable, Identifiable {
    case all
    case system
    case gui
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .system: return "System"
        case .gui: return "GUI"
        case .user: return "User"
        }
    }

    func matches(_ service: KBDaemonService) -> Bool {
        self == .all || service.domain.rawValue == rawValue
    }
}

struct DaemonsView: View {
    @Environment(AppModel.self) private var model

    @State private var search = ""
    @State private var domainFilter: DaemonDomainFilter
    @State private var runningOnly = false
    @State private var selection: String?
    @State private var pendingAction: KBDaemonAction?
    @State private var pendingService: KBDaemonService?
    @State private var showConfirmation = false

    private let preselectedLabel: String?

    init() {
        let arguments = CommandLine.arguments
        var filter = DaemonDomainFilter.all
        if let flag = arguments.firstIndex(of: "--daemon-domain"),
           flag + 1 < arguments.count,
           let parsed = DaemonDomainFilter(rawValue: arguments[flag + 1].lowercased()) {
            filter = parsed
        }
        _domainFilter = State(initialValue: filter)

        if let flag = arguments.firstIndex(of: "--daemon-selected"),
           flag + 1 < arguments.count {
            preselectedLabel = arguments[flag + 1]
        } else {
            preselectedLabel = nil
        }
    }

    private var filtered: [KBDaemonService] {
        model.allDaemons.filter { service in
            guard domainFilter.matches(service) else { return false }
            guard !runningOnly || service.isRunning else { return false }
            guard !search.isEmpty else { return true }
            return service.label.localizedCaseInsensitiveContains(search)
                || service.program.localizedCaseInsensitiveContains(search)
                || service.plistPath.localizedCaseInsensitiveContains(search)
        }
    }

    private var selectedService: KBDaemonService? {
        guard let selection else { return nil }
        return model.allDaemons.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            cards
            controls
            HStack(spacing: 12) {
                tableCard
                if let service = selectedService {
                    DaemonDetailView(
                        service: service,
                        inFlight: model.daemonActionInFlight,
                        canControlSystem: model.canControlSystem,
                        statusMessage: model.daemonActionMessage,
                        onAction: { requestAction($0, for: service) },
                        onReveal: { reveal(service) },
                        onClose: { selection = nil }
                    )
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.28), value: selection)
        }
        .padding(.horizontal, KBTheme.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await refreshLoop() }
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

            TextField("Search label, program or plist", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 230)

            Button {
                Task { await model.refreshDaemons() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh services")
        }
    }

    private var cards: some View {
        let all = model.allDaemons
        let running = all.filter(\.isRunning).count
        let stopped = all.filter { $0.isLoaded && !$0.isRunning }.count
        let disabled = all.filter(\.isDisabled).count

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 12)],
                         spacing: 12) {
            SummaryCard(
                title: "Services",
                value: KBFormat.compactCount(all.count),
                caption: "across all domains",
                systemImage: "list.bullet.rectangle",
                tint: Color(red: 0.16, green: 0.62, blue: 0.94)
            )
            SummaryCard(
                title: "Running",
                value: KBFormat.compactCount(running),
                caption: "active jobs",
                systemImage: "bolt.fill",
                tint: Color(red: 0.20, green: 0.70, blue: 0.42)
            )
            SummaryCard(
                title: "Stopped",
                value: KBFormat.compactCount(stopped),
                caption: "loaded but idle",
                systemImage: "pause.circle.fill",
                tint: Color(red: 0.94, green: 0.56, blue: 0.18)
            )
            SummaryCard(
                title: "Disabled",
                value: KBFormat.compactCount(disabled),
                caption: "launchd overrides",
                systemImage: "slash.circle.fill",
                tint: Color(red: 0.62, green: 0.42, blue: 0.95)
            )
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Domain", selection: $domainFilter) {
                ForEach(DaemonDomainFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            Toggle("Running only", isOn: $runningOnly)
                .toggleStyle(.switch)

            Spacer()

            if model.daemonActionInFlight {
                ProgressView().controlSize(.small)
            }
            Text("\(filtered.count) services")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var tableCard: some View {
        VStack(spacing: 0) {
            Table(filtered, selection: $selection) {
                TableColumn("Label") { service in
                    Text(service.label)
                        .lineLimit(1)
                        .help(service.label)
                }
                .width(min: 180, ideal: 280)

                TableColumn("Domain") { service in
                    Text(service.domain.displayName)
                }
                .width(min: 60, ideal: 75)

                TableColumn("PID") { service in
                    Text(service.pid.map { String($0) } ?? "—").monospacedDigit()
                }
                .width(min: 45, ideal: 60)

                TableColumn("State") { service in
                    DaemonStateBadge(state: service.state)
                }
                .width(min: 75, ideal: 95)

                TableColumn("Last exit") { service in
                    Text(service.lastExitStatus.map { String($0) } ?? "—").monospacedDigit()
                }
                .width(min: 60, ideal: 80)

                TableColumn("Program") { service in
                    Text(service.program.isEmpty ? "—" : service.program)
                        .lineLimit(1)
                        .help(service.program)
                }
                .width(min: 140, ideal: 220)

                TableColumn("Plist") { service in
                    Text(service.plistPath.isEmpty
                         ? "—"
                         : (service.plistPath as NSString).lastPathComponent)
                        .lineLimit(1)
                        .help(service.plistPath)
                }
                .width(min: 120, ideal: 180)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                if let id = keys.first,
                   let service = model.allDaemons.first(where: { $0.id == id }) {
                    Button("Start") { requestAction(.start, for: service) }
                    Button("Restart") { requestAction(.restart, for: service) }
                    Button("Stop") { requestAction(.stop, for: service) }
                    Divider()
                    Button(service.isDisabled ? "Enable" : "Disable") {
                        requestAction(service.isDisabled ? .enable : .disable, for: service)
                    }
                    Button("Reveal plist") { reveal(service) }
                }
            } primaryAction: { keys in
                if let id = keys.first { selection = id }
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
            if filtered.isEmpty {
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

    private func refreshLoop() async {
        await model.refreshDaemons()
        applyPreselection()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            await model.refreshDaemons()
            applyPreselection()
        }
    }

    private func applyPreselection() {
        guard selection == nil, let label = preselectedLabel else { return }
        if let match = model.allDaemons.first(where: { $0.label == label }) {
            selection = match.id
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
