import AppKit
import SwiftUI
import KancerberoCore

enum ProcessInspectorWindow {
    static let id = "process-inspector"
}

enum ProcessInspectorTab: String, CaseIterable, Identifiable, Hashable, PillTabItem {
    case statistics
    case openFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .statistics: return "Statistics"
        case .openFiles: return "Open Files and Ports"
        }
    }

    var systemImage: String {
        switch self {
        case .statistics: return "list.bullet.rectangle"
        case .openFiles: return "doc.on.doc"
        }
    }

    var tint: Color {
        switch self {
        case .statistics: return AppSection.cpu.tint
        case .openFiles: return AppSection.networking.tint
        }
    }
}

/// Activity Monitor-style process inspector hosted in its own window. Each
/// `KBProcessKey` opens an independent window, so several processes can be
/// inspected at once.
struct ProcessInspectorWindowView: View {
    let key: KBProcessKey?

    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(KBPreferences.diskUnitSystemKey)
    private var storedUnitSystem = KBPreferences.diskUnitSystemDefault

    @State private var tab: ProcessInspectorTab = .statistics
    @State private var detail: KBProcessDetail?
    @State private var cardsVisible = false
    /// Local fallback for the task counters when the connected daemon predates
    /// them (launchd keeps the old process mapped after a binary update).
    @State private var localCounters: ProcessCountersReader.Counters?
    /// Local fallback for private/shared memory when the detail payload lacks it.
    @State private var localVMInfo: ProcessVMInfoReader.VMInfo?
    /// Only a process that was once present in `model.processes` can end; a
    /// restricted process never listed there must not show a false "ended".
    @State private var sawLiveProcess = false
    @State private var ended = false
    @State private var killConfirmation: ProcessKillConfirmation?

    private var unitSystem: KBByteUnitSystem {
        KBByteUnitSystem.fromCommandLine()
            ?? KBByteUnitSystem(rawValue: storedUnitSystem)
            ?? .decimal
    }

    /// Live snapshot resolved by stable key. `ConnectionsView` can synthesise a
    /// key with `startTimeUS == 0`, so fall back to the pid for that case only.
    private var liveProcess: KBProcessInfo? {
        guard let key else { return nil }
        if let exact = model.processes.first(where: { $0.id == key }) {
            return exact
        }
        if key.startTimeUS == 0 {
            return model.processes.first { $0.pid == key.pid }
        }
        return nil
    }

    private var displayProcess: KBProcessInfo? { liveProcess ?? detail?.process }

    private var pid: Int32 { key?.pid ?? displayProcess?.pid ?? 0 }

    private var parentProcess: KBProcessInfo? {
        guard let ppid = displayProcess?.ppid, ppid > 0 else { return nil }
        return model.processes.first { $0.pid == ppid }
    }

    private var descriptorRows: [DescriptorRow] {
        guard let detail else { return [] }
        var socketsByFD: [Int32: KBSocketInfo] = [:]
        for socket in detail.sockets {
            socketsByFD[socket.fd] = socket
        }

        var rows: [DescriptorRow] = []
        var seen = Set<Int32>()
        for file in detail.openFiles {
            seen.insert(file.fd)
            if let socket = socketsByFD[file.fd] {
                rows.append(DescriptorRow(fd: file.fd,
                                          type: socket.protocolLabel,
                                          name: endpointText(socket),
                                          state: socket.stateName.isEmpty ? "—" : socket.stateName,
                                          size: nil))
            } else {
                rows.append(DescriptorRow(fd: file.fd,
                                          type: file.type,
                                          name: file.path.isEmpty ? "—" : file.path,
                                          state: "—",
                                          size: file.size > 0 ? file.size : nil))
            }
        }
        for socket in detail.sockets where !seen.contains(socket.fd) {
            rows.append(DescriptorRow(fd: socket.fd,
                                      type: socket.protocolLabel,
                                      name: endpointText(socket),
                                      state: socket.stateName.isEmpty ? "—" : socket.stateName,
                                      size: nil))
        }
        return rows.sorted { $0.fd < $1.fd }
    }

    var body: some View {
        Group {
            if key == nil {
                ContentUnavailableView(
                    "No Process",
                    systemImage: "questionmark.circle",
                    description: Text("Open an inspector from a process table."))
            } else if ended {
                endedView
            } else if let process = displayProcess {
                content(process)
            } else if model.lastUpdate == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Process Unavailable",
                    systemImage: "xmark.circle",
                    description: Text(verbatim: "PID \(pid) is not available."))
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .navigationTitle(displayProcess?.name ?? "Process \(pid)")
        .navigationSubtitle(Text(verbatim: "PID \(pid)"))
        .processKillConfirmation($killConfirmation)
        .task(id: key) {
            await refreshLoop()
        }
    }

    // MARK: - Layout

    private func content(_ process: KBProcessInfo) -> some View {
        let usage = effectiveUsage(process.usage)
        return VStack(spacing: 0) {
            header(process, usage: usage)
            PillTabBar(selection: $tab)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Group {
                switch tab {
                case .statistics:
                    statisticsTab(process, usage: usage)
                case .openFiles:
                    openFilesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ process: KBProcessInfo,
                        usage: KBProcessUsage?) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 14) {
                ProcessIconView(process: process, tint: headerTint,
                                symbol: processSymbol(process), size: 56)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(process.name.isEmpty
                             ? "Process \(process.pid)"
                             : process.name)
                            .font(.system(size: 23, weight: .semibold,
                                          design: .rounded))
                            .foregroundStyle(LinearGradient(
                                colors: [Color.primary,
                                         Color.primary.opacity(0.62)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .textSelection(.enabled)
                        if let state = process.state {
                            statePill(state)
                        }
                        LiveDot(isLive: !ended)
                    }

                    HStack(spacing: 6) {
                        infoChip("number", "PID \(process.pid)")
                        infoChip("person.fill",
                                 "\(model.userName(for: process.uid)) (\(process.uid))")
                    }

                    if !process.path.isEmpty {
                        pathLine(process.path)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    iconButton("folder", help: "Reveal in Finder",
                               tint: headerTint) { reveal(process) }
                        .disabled(process.path.isEmpty)
                    iconButton("arrow.clockwise", help: "Refresh",
                               tint: headerTint) {
                        Task { await refresh() }
                    }
                    let killAvailability = model.killAvailability(for: process)
                    iconButton("xmark.octagon",
                               help: killAvailability.reason ?? "Kill Process…",
                               tint: .red) {
                        killConfirmation = ProcessKillConfirmation(
                            process: process,
                            requiresAdministrator: killAvailability.status == .needsAdministrator)
                    }
                    .disabled(!killAvailability.isEnabled || ended)
                    iconButton("xmark", help: "Close", tint: headerTint) {
                        close()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }

            HStack(spacing: 8) {
                headerMetric("CPU",
                             usage?.cpuPercent.map(KBFormat.usagePercent) ?? "—",
                             icon: "cpu",
                             tint: usage?.cpuPercent.map { KBTheme.loadHeat($0) }
                                 ?? headerTint)
                headerMetric("Memory", bytes(usage?.physFootprintBytes),
                             icon: "memorychip",
                             tint: AppSection.memory.tint)
                headerMetric("Threads",
                             usage.map { String($0.threads) } ?? "—",
                             icon: "list.number", tint: headerTint)
                headerMetric("CPU Time", cpuTimeText(usage),
                             icon: "clock", tint: headerTint)
                headerMetric("Ports",
                             detail.map { String($0.sockets.count) } ?? "—",
                             icon: "point.3.connected.trianglepath.dotted",
                             tint: AppSection.networking.tint)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background { heroBackground(process) }
    }

    private var headerTint: Color {
        guard let state = displayProcess?.state else {
            return AppSection.cpu.tint
        }
        switch state {
        case .running: return Color(red: 0.18, green: 0.78, blue: 0.50)
        case .sleeping: return AppSection.networking.tint
        case .idle: return Color(red: 0.45, green: 0.55, blue: 0.78)
        case .stopped: return AppSection.energy.tint
        case .zombie: return Color(red: 0.92, green: 0.30, blue: 0.26)
        case .unknown: return AppSection.cpu.tint
        }
    }

    private func processSymbol(_ process: KBProcessInfo) -> String {
        let path = process.path.lowercased()
        if path.contains(".app/") { return "app" }
        if path.hasPrefix("/system/") || path.contains("/usr/libexec/") {
            return "gearshape.2"
        }
        if path.contains("/bin/") || path.contains("/sbin/") {
            return "terminal"
        }
        return "cpu"
    }

    private func statePill(_ state: KBProcessState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(headerTint)
                .frame(width: 5, height: 5)
            Text(state.displayName)
                .font(.system(size: 8.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(headerTint)
        .background(Capsule().fill(headerTint.opacity(0.14)))
        .overlay {
            Capsule().strokeBorder(headerTint.opacity(0.35), lineWidth: 0.75)
        }
    }

    private func infoChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .textSelection(.enabled)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(.quaternary.opacity(0.32)))
        .overlay {
            Capsule().strokeBorder(.quaternary.opacity(0.42), lineWidth: 0.5)
        }
    }

    private func pathLine(_ path: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(headerTint.opacity(0.85))
            Text(path)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.28)))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.35), lineWidth: 0.5)
        }
    }

    private func headerMetric(_ title: String, _ value: String,
                              icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 7.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold,
                                  design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: value)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .help("\(title): \(value)")
    }

    private func iconButton(_ systemImage: String, help: String,
                            tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay {
                    Circle().strokeBorder(tint.opacity(0.28), lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func heroBackground(_ process: KBProcessInfo) -> some View {
        ZStack {
            LinearGradient(
                colors: [headerTint.opacity(0.34), headerTint.opacity(0.10),
                         .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
            RadialGradient(colors: [headerTint.opacity(0.28), .clear],
                           center: .topLeading,
                           startRadius: 8,
                           endRadius: 380)
            LinearGradient(colors: [.white.opacity(0.08), .clear],
                           startPoint: .top,
                           endPoint: .bottom)
            Image(systemName: processSymbol(process))
                .font(.system(size: 150, weight: .bold))
                .foregroundStyle(headerTint.opacity(0.14))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 34, y: 10)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [headerTint.opacity(0.7), headerTint.opacity(0.12),
                         .clear],
                startPoint: .leading,
                endPoint: .trailing)
                .frame(height: 1)
        }
        .clipped()
    }

    private var endedView: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                "Process Ended",
                systemImage: "xmark.circle",
                description: Text(verbatim: "PID \(pid) is no longer running."))
            Button("Close") { close() }
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Statistics

    private func statisticsTab(_ process: KBProcessInfo,
                               usage: KBProcessUsage?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: 14,
                                       alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    processCard(process, usage: usage)
                    memoryCard(usage)
                    systemCard(usage)
                }

                if detail?.restricted == true {
                    restrictedNotice
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onAppear { cardsVisible = true }
        }
    }

    // MARK: - Group cards

    private func processCard(_ process: KBProcessInfo,
                             usage: KBProcessUsage?) -> some View {
        InspectorGroupCard(title: "Process", subtitle: "CPU & identity",
                           systemImage: "cpu", tint: AppSection.cpu.tint,
                           badge: process.state?.displayName,
                           index: 0, appeared: cardsVisible,
                           reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 12) {
                HeroStat(title: "% CPU",
                         value: usage?.cpuPercent.map(KBFormat.usagePercent) ?? "—",
                         caption: "CPU time \(cpuTimeText(usage))",
                         valueColor: usage?.cpuPercent.map { KBTheme.loadHeat($0) })

                cardDivider

                microGrid([
                    MicroItem(title: "Threads",
                              value: usage.map { String($0.threads) } ?? "—",
                              help: runningThreadsHelp(usage)),
                    MicroItem(title: "Process Group",
                              value: process.processGroupID.map(String.init) ?? "—"),
                    MicroItem(title: "Parent",
                              value: parentText(process),
                              help: parentHelp(process)),
                    MicroItem(title: "User",
                              value: model.userName(for: process.uid),
                              help: "UID \(process.uid)")
                ])

                cardDivider

                pathFooter(process)
            }
        }
    }

    private func memoryCard(_ usage: KBProcessUsage?) -> some View {
        let percent = usage?.memoryPercent
        let privateBytes = detail?.privateMemoryBytes ?? localVMInfo?.privateBytes
        let sharedBytes = detail?.sharedMemoryBytes ?? localVMInfo?.sharedBytes
        return InspectorGroupCard(title: "Memory",
                                  subtitle: "Footprint & capacity",
                                  systemImage: "memorychip",
                                  tint: AppSection.memory.tint,
                                  badge: percent.map { KBFormat.percent($0 / 100) },
                                  index: 1, appeared: cardsVisible,
                                  reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 12) {
                HeroStat(title: "Memory Footprint",
                         value: bytes(usage?.physFootprintBytes),
                         caption: memoryCaption(percent: percent),
                         valueColor: AppSection.memory.tint)

                if let percent, percent.isFinite {
                    CapacityBar(fraction: percent / 100,
                                tint: AppSection.memory.tint,
                                height: 6,
                                accessibilityLabel: "Memory used")
                }

                cardDivider

                microGrid([
                    MicroItem(title: "Real Memory",
                              value: bytes(usage?.residentBytes)),
                    MicroItem(title: "Virtual Memory",
                              value: bytes(usage?.virtualBytes)),
                    MicroItem(title: "Private Memory",
                              value: bytes(privateBytes),
                              help: "Private resident memory (task_vm_info.internal)."),
                    MicroItem(title: "Shared Memory",
                              value: bytes(sharedBytes),
                              help: "Shared/file-backed resident memory (task_vm_info.external)."),
                    MicroItem(title: "Ports",
                              value: detail.map { String($0.sockets.count) } ?? "—",
                              help: "Open sockets. Mach port counts are not exposed by public APIs."),
                    MicroItem(title: "Memory Used",
                              value: percent.map { KBFormat.percent($0 / 100) } ?? "—")
                ])

                Text("Private and shared memory come from task_vm_info; other users require the root daemon.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func systemCard(_ usage: KBProcessUsage?) -> some View {
        InspectorGroupCard(title: "System", subtitle: "Mach & Unix calls",
                           systemImage: "terminal",
                           tint: AppSection.networking.tint,
                           live: true, index: 2, appeared: cardsVisible,
                           reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    HeroStat(title: "Mach System Calls",
                             value: countText(usage?.machSystemCalls),
                             valueColor: AppSection.networking.tint,
                             valueSize: 24)
                    Rectangle()
                        .fill(.quaternary.opacity(0.55))
                        .frame(width: 1, height: 46)
                        .padding(.top, 2)
                    HeroStat(title: "Unix System Calls",
                             value: countText(usage?.unixSystemCalls),
                             valueColor: AppSection.cpu.tint,
                             valueSize: 24)
                }

                Text("Cumulative counters since process launch")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)

                cardDivider

                microGrid([
                    MicroItem(title: "Mach Messages Out",
                              value: countText(usage?.machMessagesSent),
                              help: "Cumulative Mach messages sent by this process."),
                    MicroItem(title: "Mach Messages In",
                              value: countText(usage?.machMessagesReceived),
                              help: "Cumulative Mach messages received by this process."),
                    MicroItem(title: "Context Switches",
                              value: countText(usage?.contextSwitches),
                              help: "Cumulative context switches."),
                    MicroItem(title: "Faults",
                              value: countText(usage?.faults),
                              help: "Cumulative page faults."),
                    MicroItem(title: "Page Ins",
                              value: countText(usage?.pageIns),
                              help: "Cumulative page-ins.")
                ])
            }
        }
    }

    private var cardDivider: some View {
        Divider().opacity(0.45)
    }

    private func microGrid(_ items: [MicroItem]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .topLeading),
                      GridItem(.flexible(), alignment: .topLeading)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(items) { item in
                MicroStat(title: item.title, value: item.value, help: item.help)
            }
        }
    }

    private func pathFooter(_ process: KBProcessInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(process.path.isEmpty ? "—" : process.path)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(process.path)
            Spacer(minLength: 4)
            Button {
                reveal(process)
            } label: {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppSection.cpu.tint)
            .disabled(process.path.isEmpty)
            .help("Reveal in Finder")
        }
    }

    private func cpuTimeText(_ usage: KBProcessUsage?) -> String {
        usage.map { KBFormat.cpuDuration($0.cpuTimeNanoseconds) } ?? "—"
    }

    private func countText(_ value: UInt64?) -> String {
        value.map(KBFormat.count) ?? "—"
    }

    private func memoryCaption(percent: Double?) -> String {
        guard let percent else { return "Physical memory unavailable" }
        let used = KBFormat.percent(percent / 100)
        if let total = model.hostMetrics?.memory.totalBytes {
            return "\(used) of \(KBFormat.bytes(total, units: unitSystem))"
        }
        return used
    }

    private func parentHelp(_ process: KBProcessInfo) -> String? {
        guard process.ppid > 0 else { return nil }
        if let parent = parentProcess, !parent.name.isEmpty {
            return "\(parent.name) (PID \(parent.ppid))"
        }
        return "PID \(process.ppid)"
    }

    private func parentText(_ process: KBProcessInfo) -> String {
        guard process.ppid > 0 else { return "—" }
        if let parent = parentProcess, !parent.name.isEmpty {
            return "\(parent.name) (\(parent.ppid))"
        }
        return String(process.ppid)
    }

    private func runningThreadsHelp(_ usage: KBProcessUsage?) -> String? {
        guard let usage else { return nil }
        return "\(usage.runningThreads) running"
    }

    private func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return KBFormat.bytes(value, units: unitSystem)
    }

    // MARK: - Open files and ports

    private var openFilesTab: some View {
        Group {
            if let detail {
                if !descriptorRows.isEmpty {
                    Table(descriptorRows) {
                        TableColumn("FD") { row in
                            Text("\(row.fd)").monospacedDigit()
                        }
                        .width(min: 42, ideal: 55)

                        TableColumn("Type") { row in
                            Text(row.type).lineLimit(1)
                        }
                        .width(min: 70, ideal: 100)

                        TableColumn("Name") { row in
                            Text(row.name)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(row.name)
                        }

                        TableColumn("State") { row in
                            Text(row.state).lineLimit(1)
                        }
                        .width(min: 70, ideal: 100)

                        TableColumn("Size") { row in
                            Text(row.sizeText(units: unitSystem)).monospacedDigit()
                        }
                        .width(min: 70, ideal: 100)
                    }
                } else if detail.restricted {
                    restrictedNotice
                        .padding(14)
                } else {
                    ContentUnavailableView(
                        "No Open Files or Ports",
                        systemImage: "doc",
                        description: Text("No descriptors are readable for this process."))
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var restrictedNotice: some View {
        Text("Permission denied for this process. Install the daemon (root) to inspect other users.")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func endpointText(_ socket: KBSocketInfo) -> String {
        let local = socket.local.display
        let remote = socket.remote.display
        // A zero remote port means the socket is not connected (listening or
        // bound only); showing "[::]:0" would be misleading.
        if socket.remote.port != 0 {
            return "\(local) → \(remote)"
        }
        return local
    }

    // MARK: - Actions and refresh

    private func reveal(_ process: KBProcessInfo) {
        guard !process.path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: process.path)])
    }

    private func close() {
        if let key {
            dismissWindow(id: ProcessInspectorWindow.id, value: key)
        } else {
            dismissWindow(id: ProcessInspectorWindow.id)
        }
    }

    private func refreshLoop() async {
        guard key != nil else { return }
        while !Task.isCancelled {
            await refresh()
            if ended { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func effectiveUsage(_ usage: KBProcessUsage?) -> KBProcessUsage? {
        guard var usage else { return nil }
        guard usage.machSystemCalls == nil,
              let counters = localCounters else { return usage }
        usage.machSystemCalls = counters.machSystemCalls
        usage.unixSystemCalls = counters.unixSystemCalls
        usage.machMessagesSent = counters.machMessagesSent
        usage.machMessagesReceived = counters.machMessagesReceived
        usage.contextSwitches = counters.contextSwitches
        usage.faults = counters.faults
        if usage.pageIns == nil {
            usage.pageIns = counters.pageIns
        }
        return usage
    }

    private func refresh() async {
        guard let key else { return }
        if let live = liveProcess {
            sawLiveProcess = true
            ended = false
            detail = await model.detail(for: live)
            if let usage = live.usage, usage.machSystemCalls == nil {
                localCounters = ProcessCountersReader.current(pid: live.pid)
            } else {
                localCounters = nil
            }
            if detail?.privateMemoryBytes == nil {
                localVMInfo = ProcessVMInfoReader.current(pid: live.pid)
            } else {
                localVMInfo = nil
            }
            return
        }
        if sawLiveProcess, model.lastUpdate != nil, !model.processes.isEmpty {
            ended = true
            return
        }
        // The shared snapshot may not include this process yet (startup or a
        // restricted row). Ask the detail endpoint directly so the window can
        // show whatever libproc exposes.
        let placeholder = KBProcessInfo(pid: key.pid,
                                        startTimeUS: key.startTimeUS)
        detail = await model.detail(for: placeholder)
        if let usage = detail?.process.usage, usage.machSystemCalls == nil {
            localCounters = ProcessCountersReader.current(pid: key.pid)
        }
        if detail?.privateMemoryBytes == nil {
            localVMInfo = ProcessVMInfoReader.current(pid: key.pid)
        }
    }
}

private struct DescriptorRow: Identifiable {
    let fd: Int32
    let type: String
    let name: String
    let state: String
    let size: Int64?

    var id: Int32 { fd }

    func sizeText(units: KBByteUnitSystem) -> String {
        guard let size, size > 0 else { return "—" }
        return KBFormat.bytes(UInt64(clamping: size), units: units)
    }
}

// MARK: - Statistics cards

/// Large identity icon for the inspector header. App bundles show their real
/// icon; everything else gets a glossy gradient badge with an SF Symbol.
private struct ProcessIconView: View {
    let process: KBProcessInfo
    let tint: Color
    let symbol: String
    var size: CGFloat = 56

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
            } else {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(KBTheme.gradient(tint))
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.34), .clear],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(.white.opacity(0.30), lineWidth: 0.75)
                .opacity(image == nil ? 1 : 0)
        }
        .shadow(color: tint.opacity(0.5), radius: 12, y: 4)
        .task(id: process.path) {
            image = Self.loadIcon(for: process.path)
        }
        .accessibilityHidden(true)
    }

    private static func loadIcon(for path: String) -> NSImage? {
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let range = path.range(of: ".app/") else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        guard FileManager.default.fileExists(atPath: bundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: bundle)
    }
}

private struct MicroItem: Identifiable {
    let title: String
    let value: String
    var help: String? = nil

    var id: String { title }
}

private struct MicroStat: View {
    let title: String
    let value: String
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: value)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .help(help ?? value)
    }
}

private struct HeroStat: View {
    let title: String
    let value: String
    var caption: String? = nil
    var valueColor: Color? = nil
    var valueSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: valueSize, weight: .semibold,
                              design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    valueColor.map { AnyShapeStyle(KBTheme.gradient($0)) }
                        ?? AnyShapeStyle(Color.primary))
                .shadow(color: (valueColor ?? .clear).opacity(0.28),
                        radius: 7, y: 3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: value)
            if let caption {
                Text(caption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(caption.map { "\(value), \($0)" } ?? value)
    }
}

/// Glassy, tinted card used by the three Statistics groups. The header is a
/// full-bleed tinted band with a glossy icon, subtitle, status badge, live dot
/// and a one-shot light sheen. Non-interactive; the treatment is decorative.
private struct InspectorGroupCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var live: Bool = false
    var badge: String? = nil
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool
    private let content: Content
    @State private var sheen = false

    init(title: String, subtitle: String, systemImage: String, tint: Color,
         live: Bool = false, badge: String? = nil, index: Int,
         appeared: Bool, reduceMotion: Bool,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.live = live
        self.badge = badge
        self.index = index
        self.appeared = appeared
        self.reduceMotion = reduceMotion
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 12) {
                content
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: .topLeading)
        }
        .frame(minWidth: 0, maxWidth: .infinity,
               minHeight: 300, maxHeight: .infinity,
               alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: KBTheme.cardRadius,
                                    style: .continuous))
        .overlay(border)
        .shadow(color: tint.opacity(0.18), radius: 14, y: 5)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(reduceMotion
                   ? nil
                   : .snappy(duration: 0.4).delay(Double(index) * 0.06),
                   value: appeared)
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            iconBadge

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(tint)
                    .background(Capsule().fill(tint.opacity(0.16)))
                    .overlay {
                        Capsule().strokeBorder(tint.opacity(0.38), lineWidth: 0.75)
                    }
            }

            if live {
                HStack(spacing: 3) {
                    LiveDot(isLive: true)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background { headerBackground }
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(KBTheme.gradient(tint))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.34), .clear],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
        }
        .frame(width: 34, height: 34)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.75)
        }
        .shadow(color: tint.opacity(0.55), radius: 9, y: 3)
    }

    private var headerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.30), tint.opacity(0.09), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
            LinearGradient(
                colors: [.white.opacity(0.10), .clear],
                startPoint: .top,
                endPoint: .bottom)
            sheenOverlay
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [tint.opacity(0.75), tint.opacity(0.12), .clear],
                startPoint: .leading,
                endPoint: .trailing)
                .frame(height: 1)
        }
        .clipped()
    }

    private var sheenOverlay: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.16), .clear],
                    startPoint: .leading,
                    endPoint: .trailing))
                .frame(width: proxy.size.width * 0.45)
                .rotationEffect(.degrees(16))
                .offset(x: sheen
                        ? proxy.size.width * 1.15
                        : -proxy.size.width * 0.75)
                .animation(reduceMotion
                           ? nil
                           : .easeInOut(duration: 1.1)
                               .delay(0.2 + Double(index) * 0.08),
                           value: sheen)
        }
        .allowsHitTesting(false)
        .onAppear { sheen = true }
    }

    // MARK: Card chrome

    private var background: some View {
        RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(alignment: .topTrailing) {
                RadialGradient(colors: [tint.opacity(0.10), .clear],
                               center: .topTrailing,
                               startRadius: 4,
                               endRadius: 180)
                    .allowsHitTesting(false)
            }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.08)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                lineWidth: 1)
    }
}
