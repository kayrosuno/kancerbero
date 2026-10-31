import AppKit
import ServiceManagement
import SwiftUI

/// Identifier of the window scene that hosts `SystemStatusView`.
enum SystemStatusWindow {
    static let id = "system-status"
}

/// Status checklist shown from the Local/Daemon indicators in the sidebar and
/// status bar. Its actions only use public SMAppService/AppKit APIs and the
/// existing AppModel helpers; it never executes sudo commands.
struct SystemStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(FilterModel.self) private var filter
    @Environment(\.dismiss) private var dismiss

    @State private var copiedLegacyCommands = false
    @State private var showRepairConfirmation = false
    @State private var guide: ActivationGuide?

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            rail
                .frame(width: 190, alignment: .topLeading)
                .padding(.leading, 18)
                .padding(.top, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    contentHeader
                    overallBanner
                    primaryActions
                    if let error = model.serviceError {
                        errorText(error)
                    }
                    checklist
                    footerColumns
                }
                .padding(18)
            }
            .scrollIndicators(.visible)
        }
        .frame(minWidth: 1080, idealWidth: 1180, minHeight: 620, maxHeight: .infinity)
        .onAppear {
            model.refreshServiceStatus()
            model.refreshFullDiskAccess(force: true)
            // Do not recompute over a transient state: refresh() would erase
            // the activation error or the approval instruction.
            switch filter.controller.state {
            case .activating, .requiresApproval, .failed:
                break
            default:
                Task {
                    await filter.controller.refresh()
                    // NEFilterManager.isEnabled only proves a saved
                    // configuration. Probe the extension so a stale "Enabled"
                    // cannot paint the checklist green.
                    if filter.controller.state.isEnabled && !filter.isConnected {
                        await filter.connect()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshFullDiskAccess()
        }
        .sheet(item: $guide) { guide in
            ActivationGuideView(guide: guide)
                .environment(model)
                .environment(filter)
        }
        .confirmationDialog("Repair background service?",
                            isPresented: $showRepairConfirmation,
                            titleVisibility: .visible) {
            Button("Unregister and re-register") {
                Task { await model.repairDaemonService() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes and re-adds the background helper. macOS may ask you to approve Kancerbero again in Login Items. Privileged data will pause until it is approved.")
        }
    }

    // MARK: - Header and overview

    /// Left rail: logo, identity and the two component indicators.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppLogoView(size: 128)
            VStack(alignment: .leading, spacing: 2) {
                Text("System status")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Kancerbero \(model.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                railChip(railDaemonLabel, tint: railDaemonTint)
                railChip(filter.filterHealth.shortLabel,
                         tint: filter.filterHealth.tint)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
    }

    private func railChip(_ text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .help(text)
    }

    private var railDaemonLabel: String {
        guard model.usingDaemon else { return "Local mode" }
        return model.daemonIsRoot ? "Daemon root" : "Daemon user"
    }

    private var railDaemonTint: Color {
        if model.legacyServiceDetected { return .orange }
        if model.usingDaemon {
            return model.daemonIsRoot ? .green : .orange
        }
        return .orange
    }

    private var contentHeader: some View {
        HStack(spacing: 8) {
            sectionHeader("Overview")
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var overallBanner: some View {
        let state = overallState
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.level.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.level.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(state.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if let actionTitle = state.actionTitle, let action = state.action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if model.serviceActionInFlight || model.isConnectingToDaemon {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(state.level.color.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(state.level.color.opacity(0.35), lineWidth: 1)
        }
    }

    private var overallState: OverallState {
        if model.legacyServiceDetected {
            return OverallState(
                level: .warning,
                title: "Legacy service conflict",
                message: "An old launchd agent or daemon is installed. Remove it before enabling the modern background service.")
        }
        if !model.daemonHelperPresent || !model.daemonPlistPresent {
            return OverallState(
                level: .error,
                title: "Background helper missing",
                message: "This app bundle is incomplete. Replace it with a complete signed build in /Applications.")
        }
        if model.serviceStatus == .notFound {
            return OverallState(
                level: .error,
                title: "Background service unavailable",
                message: "macOS cannot find the service registration. Repair it or reinstall a signed, notarized build.")
        }
        if model.serviceStatus == .requiresApproval {
            return OverallState(
                level: .warning,
                title: "Approval required",
                message: "Allow Kancerbero in System Settings → General → Login Items & Extensions → Allow in the Background.")
        }
        if model.serviceStatus == .enabled && model.isConnectingToDaemon {
            return OverallState(
                level: .info,
                title: "Connecting to background service",
                message: "The service is registered. Waiting for the daemon to answer.")
        }
        if model.serviceStatus == .enabled && !model.usingDaemon {
            if model.daemonProcessRunning {
                return OverallState(
                    level: .warning,
                    title: "Daemon not answering",
                    message: "The background helper process is running but the XPC handshake failed. \(model.daemonConnectionError ?? "Try Retry connection.")")
            }
            return OverallState(
                level: .error,
                title: "Service registered, daemon not running",
                message: "macOS has the service registered but is not launching the daemon. This usually means its code signature was rejected (AMFI launch constraint). Install the signed, notarized build and use Repair.")
        }
        // A healthy daemon is not the whole story: a missing or inactive
        // network extension is a degraded system, so it must not be reported as
        // a green "Full access".
        if let filterProblem = filterComponentState {
            return filterProblem
        }
        if model.usingDaemon && model.daemonIsRoot {
            return OverallState(
                level: .ok,
                title: "Full access",
                message: "The background daemon is connected. Other users' processes, sockets and system services are available.")
        }
        if model.isRoot {
            return OverallState(
                level: .ok,
                title: "Full access (root)",
                message: "Kancerbero is running as root; all users' data is available without the background daemon.")
        }
        if model.usingDaemon {
            return OverallState(
                level: .warning,
                title: "Limited daemon access",
                message: "The daemon is connected but is not running as root. Some protected data stays restricted.")
        }
        return OverallState(
            level: .warning,
            title: "Running in local mode",
            message: "Kancerbero can only see your user's processes and sockets. Enable and approve the background service for full access.")
    }

    /// Overall state contributed by the network filter. Returns `nil` when the
    /// filter is running or was deliberately disabled, so the daemon's access
    /// state stays visible.
    private var filterComponentState: OverallState? {
        switch filter.filterHealth {
        case .configuredNotRunning:
            return OverallState(
                level: .warning,
                title: "Network extension not active",
                message: "The filter is configured in macOS, but the network extension is not running. Turn on Kancerbero Filter in System Settings → General → Login Items & Extensions → Network Extensions.",
                actionTitle: "How to activate…",
                action: { guide = .networkExtension })
        case .requiresApproval, .notInstalled:
            return OverallState(
                level: .warning,
                title: "Network extension not active",
                message: "Install and approve the network extension in System Settings → General → Login Items & Extensions → Network Extensions.",
                actionTitle: "How to activate…",
                action: { guide = .networkExtension })
        case .failed(let message):
            return OverallState(
                level: .warning,
                title: "Network extension unavailable",
                message: [message, filter.controller.failureGuidance]
                    .compactMap { $0 }
                    .joined(separator: " "),
                actionTitle: "How to activate…",
                action: { guide = .networkExtension })
        case .unsupported:
            return OverallState(
                level: .warning,
                title: "Network extension unavailable",
                message: "This build cannot host the filter system extension. Use a signed, notarized build installed in /Applications.",
                actionTitle: "How to activate…",
                action: { guide = .networkExtension })
        case .activating:
            return OverallState(
                level: .info,
                title: "Activating network extension",
                message: "Waiting for macOS to activate the system extension.")
        case .running, .disabled:
            return nil
        }
    }

    // MARK: - Checklist

    private var checklist: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                card("Application") {
                    applicationRow
                    helperRow
                }
                card("Data access") {
                    dataCollectionRow
                    trafficAttributionRow
                    privilegedRow
                    fullDiskAccessRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 14) {
                card("Background service") {
                    serviceRow
                    approvalRow
                    connectionRow
                    daemonProcessRow
                    if model.daemonProcessesIncomplete {
                        processDataRow
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 14) {
                card("Network filter") {
                    filterExtensionRow
                    filterConfigurationRow
                }
                card("Compatibility") {
                    legacyRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader(title)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private var footerColumns: some View {
        HStack(alignment: .top, spacing: 14) {
            if showsSetupSteps {
                setupSteps
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            actions
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var applicationRow: some View {
        let inApplications = model.appIsInApplications
        return statusRow(
            inApplications ? .ok : .info,
            title: "Application",
            value: inApplications ? "Running" : "Development build",
            detail: "\(model.appVersion) · \(model.appBundlePath)"
                + (inApplications ? "" : "\nInstall in /Applications for production use."),
            actionTitle: inApplications ? nil : "Reveal",
            action: { model.revealAppInFinder() }
        )
    }

    private var helperRow: some View {
        let present = model.daemonHelperPresent && model.daemonPlistPresent
        let value: String
        if present {
            value = "Present"
        } else if model.daemonHelperPresent || model.daemonPlistPresent {
            value = "Incomplete"
        } else {
            value = "Missing"
        }
        return statusRow(
            present ? .ok : .error,
            title: "Bundle helper",
            value: value,
            detail: present
                ? "Contents/Library/LaunchDaemons/KancerberoDaemon and its launchd plist are present."
                : "The app bundle is missing the daemon executable or plist. Kancerbero cannot reinstall itself; replace the app in /Applications with a complete signed build.",
            actionTitle: "Reveal",
            action: { model.revealAppInFinder() }
        )
    }

    private var dataCollectionRow: some View {
        let level: StatusLevel
        var detail: String
        if model.isRoot && !model.usingDaemon {
            level = .ok
            detail = "The app is running as root; all users' data is visible."
        } else if model.usingDaemon && model.daemonIsRoot {
            level = .ok
            detail = "The root daemon is collecting all users' processes, sockets and CPU/memory."
        } else if model.usingDaemon {
            level = .warning
            detail = "The daemon is connected without root; only your user's data is visible."
        } else if model.mode == .localFullNStat {
            level = model.lastError == nil ? .ok : .warning
            detail = "Local NetworkStatistics. Only your user's processes and sockets are visible."
        } else if model.mode == .localDegraded {
            level = .warning
            detail = "NetworkStatistics is unavailable. Some connection data may be missing."
        } else {
            level = .info
            detail = "Waiting for the first collection sample."
        }
        if let error = model.lastError {
            detail += "\n\(error)"
        }
        return statusRow(level, title: "Data collection",
                         value: model.modeDescription, detail: detail)
    }

    private var trafficAttributionRow: some View {
        let level: StatusLevel
        switch model.privcheck {
        case 0: level = .ok
        case 1...: level = .warning
        default: level = .info
        }
        return statusRow(level,
                         title: "Per-process traffic",
                         value: model.trafficAccessValue,
                         detail: model.trafficAccessDetail)
    }

    private var privilegedRow: some View {
        let full = model.hasFullDataAccess
        let detail: String
        if model.isRoot && !model.usingDaemon {
            detail = "The app is running as root; protected data from other users is visible."
        } else if full {
            detail = "Processes, CPU/memory counters and protected data owned by other users are visible."
        } else {
            detail = "Data owned by other users is hidden. Enable and approve the background service to unlock it."
        }
        return statusRow(full ? .ok : .warning,
                         title: "Privileged data",
                         value: full ? "Full access" : "Your user only",
                         detail: detail)
    }

    private var fullDiskAccessRow: some View {
        let level: StatusLevel
        let actionTitle: String
        let action: () -> Void

        switch model.fullDiskAccess {
        case .granted:
            level = .ok
            actionTitle = "Open Settings"
            action = { model.openFullDiskAccessSettings() }
        case .denied:
            level = .warning
            actionTitle = "How to activate…"
            action = { guide = .fullDiskAccess }
        case .unknown:
            level = .info
            actionTitle = "Open Settings"
            action = { model.openFullDiskAccessSettings() }
        }

        return statusRow(level,
                         title: "Full Disk Access",
                         value: model.fullDiskAccessValue,
                         detail: model.fullDiskAccessDetail,
                         actionTitle: actionTitle,
                         action: action)
    }

    private var serviceRow: some View {
        let level: StatusLevel
        let value: String
        let detail: String
        var actionTitle: String?
        var action: (() -> Void)?
        var actionDisabled = model.serviceActionInFlight
        switch model.serviceStatus {
        case .enabled:
            level = model.daemonProcessRunning ? .ok : .warning
            value = "Registered"
            detail = model.daemonProcessRunning
                ? "macOS has the background helper registered and its process is running."
                : "macOS has the background helper registered, but no daemon process is running."
            actionTitle = "Open Login Items"
            action = { model.openLoginItemsSettings() }
        case .requiresApproval:
            level = .warning
            value = "Needs approval"
            detail = "Approve Kancerbero in Login Items → Allow in the Background."
            actionTitle = "How to activate…"
            action = { guide = .backgroundService }
            actionDisabled = model.serviceActionInFlight
        case .notRegistered:
            level = .warning
            value = "Not registered"
            detail = "Enable it to collect other users and control system services."
            actionTitle = "How to activate…"
            action = { guide = .backgroundService }
            actionDisabled = model.serviceActionInFlight
        case .notFound:
            level = .error
            value = "Unavailable"
            detail = "The helper or plist is missing, or the app cannot register the service."
            if model.daemonHelperPresent && model.daemonPlistPresent {
                actionTitle = "Repair…"
                action = { showRepairConfirmation = true }
                actionDisabled = actionDisabled
                    || model.isConnectingToDaemon
                    || model.legacyServiceDetected
            } else {
                actionTitle = "Reveal"
                action = { model.revealAppInFinder() }
                actionDisabled = false
            }
        @unknown default:
            level = .info
            value = "Unknown"
            detail = "macOS reported an unfamiliar service state."
        }

        return statusRow(level, title: "Background service",
                         value: value, detail: detail,
                         actionTitle: actionTitle,
                         actionDisabled: actionDisabled,
                         action: action)
    }

    private var approvalRow: some View {
        let level: StatusLevel
        let value: String
        let detail: String
        switch model.serviceStatus {
        case .enabled:
            level = .ok
            value = "Approved"
            detail = "Kancerbero is allowed to run in the background."
        case .requiresApproval:
            level = .warning
            value = "Pending"
            detail = "Turn on Kancerbero under Allow in the Background in Login Items."
        case .notRegistered:
            level = .info
            value = "Not requested"
            detail = "Register the background service first; macOS will ask for approval afterwards."
        case .notFound:
            level = .error
            value = "Unavailable"
            detail = "The service cannot be registered, so there is nothing to approve yet."
        @unknown default:
            level = .info
            value = "Unknown"
            detail = "macOS reported an unfamiliar approval state."
        }
        return statusRow(level, title: "Login Items approval",
                         value: value, detail: detail,
                         actionTitle: "Open Login Items",
                         actionDisabled: model.serviceActionInFlight,
                         action: { model.openLoginItemsSettings() })
    }

    private var connectionRow: some View {
        let connected = model.usingDaemon
        let connecting = model.isConnectingToDaemon
        let level: StatusLevel
        let value: String
        let detail: String
        if connected {
            level = model.daemonIsRoot ? .ok : .warning
            value = "Connected"
            detail = "Daemon \(model.daemonVersion ?? "unknown") · \(model.daemonIsRoot ? "root" : "non-root")."
        } else if connecting {
            level = .info
            value = "Connecting…"
            detail = "Waiting for the background service to answer."
        } else if model.serviceStatus == .enabled {
            level = .warning
            value = "Not connected"
            if model.daemonProcessRunning {
                detail = model.daemonConnectionError
                    ?? "The daemon process is running but the app is not receiving data. Try Retry connection."
            } else {
                detail = "The service is registered but no daemon process is running. Repair the registration after installing a signed build."
            }
        } else {
            level = .info
            value = "Not connected"
            detail = "The app is collecting data locally."
        }
        let canRetry = !connected && !connecting && !model.serviceActionInFlight
            && (model.serviceStatus == .enabled || model.legacyServiceDetected)
        return statusRow(level, title: "Daemon connection",
                         value: value, detail: detail,
                         actionTitle: "Retry",
                         actionDisabled: !canRetry,
                         action: { model.retryDaemonConnection() })
    }

    private var daemonProcessRow: some View {
        let enabled = model.serviceStatus == .enabled
        let running = model.daemonProcessRunning
        let level: StatusLevel = running ? .ok : (enabled ? .error : .info)
        let value: String
        let detail: String
        if running {
            value = model.daemonProcessPID.map { "Running (pid \($0))" } ?? "Running"
            detail = "The background helper process is visible in the process table."
        } else if enabled {
            value = "Not running"
            detail = "Registered but no KancerberoDaemon process was found. launchd or AMFI may have rejected the executable; reinstall the signed, notarized build and repair the registration."
        } else {
            value = "Unknown"
            detail = "Register the background service first."
        }
        let actionTitle = enabled && !running ? "Repair…" : nil
        return statusRow(level, title: "Daemon process",
                         value: value, detail: detail,
                         actionTitle: actionTitle,
                         actionDisabled: model.serviceActionInFlight,
                         action: enabled && !running ? { showRepairConfirmation = true } : nil)
    }

    private var processDataRow: some View {
        statusRow(.warning,
                  title: "Process data",
                  value: "Incomplete",
                  detail: "The background daemon reports \(model.daemonReportedProcessCount) of \(model.daemonLocalProcessCount) processes. Install the current Kancerbero build and repair the background service to update it; CPU, memory and thread values for the remaining processes stay unavailable until then.",
                  actionTitle: "Repair…",
                  actionDisabled: !canRepair,
                  action: { showRepairConfirmation = true })
    }

    private var filterExtensionRow: some View {
        let health = filter.filterHealth
        let detail: String
        if filter.controller.isActivating,
           health == .running || health == .configuredNotRunning {
            detail = "Repairing the system extension. macOS may ask you to approve it again."
        } else {
            detail = health.systemDetail(failureGuidance: filter.controller.failureGuidance)
        }

        let actionTitle: String?
        let action: (() -> Void)?
        switch health {
        case .notInstalled, .requiresApproval, .configuredNotRunning:
            actionTitle = "How to activate…"
            action = { guide = .networkExtension }
        case .disabled:
            actionTitle = "Enable"
            action = { Task { await filter.enableFilter() } }
        case .failed:
            actionTitle = "Retry"
            action = { Task { await filter.enableFilter() } }
        case .running, .activating, .unsupported:
            actionTitle = nil
            action = nil
        }

        return statusRow(StatusLevel(health.severity),
                         title: "Filter extension",
                         value: health.systemValue,
                         detail: detail,
                         actionTitle: actionTitle,
                         actionDisabled: filter.isBusy
                            || filter.isConnecting
                            || filter.controller.isActivating,
                         action: action)
    }

    private var filterConfigurationRow: some View {
        let health = filter.filterHealth
        let enabled = filter.controller.isEnabled
        let level: StatusLevel
        let value: String
        let detail: String
        switch health {
        case .running:
            level = .ok
            value = "Enabled"
            detail = "Watched processes ask for approval before each new connection. Other traffic is observed only."
        case .configuredNotRunning:
            // Do not paint the saved configuration green while the extension
            // it belongs to is dead.
            level = .info
            value = "Enabled (saved)"
            detail = "The filter configuration is saved in macOS. This does not prove the extension was approved; see Filter extension above."
        case .disabled:
            level = .info
            value = "Disabled"
            detail = "The filter is disabled; Kancerbero keeps monitoring with NetworkStatistics."
        default:
            level = .info
            value = enabled ? "Enabled" : "Disabled"
            detail = enabled
                ? "Watched processes ask for approval before each new connection. Other traffic is observed only."
                : "The filter is disabled; Kancerbero keeps monitoring with NetworkStatistics."
        }

        return statusRow(level,
                         title: "Filter configuration",
                         value: value,
                         detail: detail,
                         actionTitle: enabled ? "Disable" : "Enable",
                         actionDisabled: filter.isBusy || !filter.controller.isSupported,
                         action: {
                             Task {
                                 if enabled {
                                     await filter.disableFilter()
                                 } else {
                                     await filter.enableFilter()
                                 }
                             }
                         })
    }

    private var legacyRow: some View {
        let detected = model.legacyServiceDetected
        let value: String
        let detail: String
        switch (model.legacyAgentDetected, model.legacyDaemonDetected) {
        case (true, true):
            value = "Agent and daemon"
            detail = "Both an old launch agent and an old system daemon are installed. Remove both before repairing the service."
        case (true, false):
            value = "Legacy agent"
            detail = "An old launch agent uses the same label. Remove it, then click Refresh status."
        case (false, true):
            value = "Legacy daemon"
            detail = "An old system daemon uses the same label and Mach service. Removing it requires sudo."
        case (false, false):
            value = "None"
            detail = "No old launchd jobs were found."
        }

        return VStack(alignment: .leading, spacing: 8) {
            statusRow(detected ? .warning : .ok,
                      title: "Legacy services", value: value, detail: detail)
            if detected {
                Text(model.legacyRemovalCommands)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                HStack(spacing: 10) {
                    Button(copiedLegacyCommands ? "Copied" : "Copy removal commands") {
                        model.copyLegacyRemovalCommands()
                        copiedLegacyCommands = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            copiedLegacyCommands = false
                        }
                    }
                    .buttonStyle(.link)
                    Text("Run these in Terminal. Kancerbero never runs sudo commands.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Setup guidance

    private var showsSetupSteps: Bool {
        !model.hasFullDataAccess
            || model.legacyServiceDetected
            || !model.daemonHelperPresent
            || !model.daemonPlistPresent
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("To enable full access")
                .font(.system(size: 12, weight: .semibold))

            if model.legacyServiceDetected {
                Text("Remove the legacy services listed under Compatibility first.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else if !model.daemonHelperPresent || !model.daemonPlistPresent {
                Text("Reinstall a complete Kancerbero app first; this bundle is missing its helper.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else {
                stepRow(1, "Enable the background service.",
                        done: model.serviceStatus != .notRegistered
                            && model.serviceStatus != .notFound)
                stepRow(2, "Allow Kancerbero in System Settings → General → Login Items & Extensions → Allow in the Background.",
                        done: model.serviceStatus == .enabled)
                stepRow(3, "Return here and click Retry connection.",
                        done: model.usingDaemon)
                Text("If macOS does not list Kancerbero, use Repair / re-register. A Debug or unsigned build may not be approvable; use a signed, notarized build in /Applications.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous))
    }

    private func stepRow(_ number: Int, _ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(done ? Color.green : Color.secondary)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private var primaryActions: some View {
        HStack(spacing: 10) {
            primaryActionButton

            if model.serviceStatus != .requiresApproval {
                Button("Open Login Items") {
                    model.openLoginItemsSettings()
                }
                .buttonStyle(.bordered)
                .disabled(model.serviceActionInFlight)
            }

            if canRepair && model.serviceStatus != .notFound {
                Button("Repair…") {
                    showRepairConfirmation = true
                }
                .buttonStyle(.bordered)
                .help("Remove and re-add the background helper; macOS may ask for approval again.")
            }

            if model.serviceActionInFlight {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Troubleshooting")

            HStack(spacing: 10) {
                Button("Retry connection") {
                    model.retryDaemonConnection()
                }
                .buttonStyle(.bordered)
                .disabled(!canRetryConnection)

                Button("Refresh status") {
                    model.refreshServiceStatus()
                    model.refreshFullDiskAccess(force: true)
                }
                .buttonStyle(.bordered)

                Button("Reveal app in Finder") {
                    model.revealAppInFinder()
                }
                .buttonStyle(.bordered)
            }

            if !model.appIsInApplications {
                Button("Open Applications folder") {
                    model.openApplicationsFolder()
                }
                .buttonStyle(.bordered)
            }

            Text("Repair removes and re-adds the background helper. macOS may ask you to approve Kancerbero again in Login Items; privileged data pauses until it is approved.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.appIsInApplications
                || !model.daemonHelperPresent
                || !model.daemonPlistPresent
                || model.serviceStatus == .notFound {
                Text("Kancerbero cannot reinstall itself. Quit it, replace Kancerbero.app in /Applications with a complete signed build, reopen it, then repair the background service.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if model.legacyServiceDetected {
            EmptyView()
        } else if !model.daemonHelperPresent || !model.daemonPlistPresent {
            Button("Reveal app in Finder") {
                model.revealAppInFinder()
            }
            .buttonStyle(.borderedProminent)
        } else {
            switch model.serviceStatus {
            case .notRegistered:
                Button("Enable background service") {
                    Task { await model.registerDaemonService() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.serviceActionInFlight)
            case .requiresApproval:
                Button("Open Login Items") {
                    model.openLoginItemsSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.serviceActionInFlight)
            case .enabled:
                if model.usingDaemon {
                    EmptyView()
                } else if !model.daemonProcessRunning {
                    Button("Repair / re-register…") {
                        showRepairConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRepair)
                } else {
                    Button("Retry connection") {
                        model.retryDaemonConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.serviceActionInFlight || model.isConnectingToDaemon)
                }
            case .notFound:
                Button("Repair / re-register…") {
                    showRepairConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRepair)
            @unknown default:
                EmptyView()
            }
        }
    }

    private var canRetryConnection: Bool {
        !model.usingDaemon
            && !model.isConnectingToDaemon
            && !model.serviceActionInFlight
            && (model.serviceStatus == .enabled || model.legacyServiceDetected)
    }

    private var canRepair: Bool {
        !model.serviceActionInFlight
            && !model.isConnectingToDaemon
            && !model.legacyServiceDetected
            && model.daemonHelperPresent
            && model.daemonPlistPresent
    }

    // MARK: - Small building blocks

    private func statusRow(_ level: StatusLevel,
                           title: String,
                           value: String,
                           detail: String,
                           actionTitle: String? = nil,
                           actionDisabled: Bool = false,
                           action: (() -> Void)? = nil) -> some View {
        StatusRow(level: level, title: title, value: value, detail: detail,
                  actionTitle: actionTitle, actionDisabled: actionDisabled,
                  action: action)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
    }

    private func errorText(_ error: String) -> some View {
        Text(error)
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct OverallState {
    let level: StatusLevel
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
}

private enum StatusLevel {
    case ok
    case info
    case warning
    case error

    var color: Color {
        switch self {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    var icon: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

private extension StatusLevel {
    init(_ severity: FilterHealth.Severity) {
        switch severity {
        case .ok: self = .ok
        case .info: self = .info
        case .warning: self = .warning
        case .error: self = .error
        }
    }
}

private struct StatusRow: View {
    let level: StatusLevel
    let title: String
    let value: String
    let detail: String
    var actionTitle: String?
    var actionDisabled: Bool
    var action: (() -> Void)?

    init(level: StatusLevel, title: String, value: String, detail: String,
         actionTitle: String? = nil, actionDisabled: Bool = false,
         action: (() -> Void)? = nil) {
        self.level = level
        self.title = title
        self.value = value
        self.detail = detail
        self.actionTitle = actionTitle
        self.actionDisabled = actionDisabled
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: level.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(level.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                // A single wrapping paragraph so a long title or value wraps
                // instead of being truncated in a narrow column.
                (Text(title).font(.system(size: 11, weight: .semibold))
                    + Text("   ")
                    + Text(value)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(level.color))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(actionDisabled)
            }
        }
        .padding(.vertical, 2)
    }
}
