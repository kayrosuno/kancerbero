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
    @Environment(\.dismiss) private var dismiss

    @State private var copiedLegacyCommands = false
    @State private var showRepairConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                overallBanner
                primaryActions
                if let error = model.serviceError {
                    errorText(error)
                }
                checklist
                if showsSetupSteps { setupSteps }
                actions
            }
            .padding(16)
        }
        .scrollIndicators(.visible)
        .frame(minWidth: 460, idealWidth: 480, minHeight: 560, maxHeight: .infinity)
        .onAppear { model.refreshServiceStatus() }
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("System status")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Kancerbero \(model.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            return OverallState(
                level: .warning,
                title: "Service registered, not connected",
                message: "The background service is registered but the app is not receiving daemon data. Try Retry connection.")
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

    // MARK: - Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Application")
            applicationRow
            helperRow

            sectionHeader("Data access")
            dataCollectionRow
            privilegedRow

            sectionHeader("Background service")
            serviceRow
            approvalRow
            connectionRow

            sectionHeader("Compatibility")
            legacyRow
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
        if model.privcheck >= 0 {
            detail += " privcheck \(model.privcheck)."
        }
        if let error = model.lastError {
            detail += "\n\(error)"
        }
        return statusRow(level, title: "Data collection",
                         value: model.modeDescription, detail: detail)
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

    private var serviceRow: some View {
        let level: StatusLevel
        let value: String
        let detail: String
        var actionTitle: String?
        var action: (() -> Void)?
        var actionDisabled = model.serviceActionInFlight
        switch model.serviceStatus {
        case .enabled:
            level = .ok
            value = "Registered"
            detail = "macOS has the background helper registered."
            actionTitle = "Open Login Items"
            action = { model.openLoginItemsSettings() }
        case .requiresApproval:
            level = .warning
            value = "Needs approval"
            detail = "Approve Kancerbero in Login Items → Allow in the Background."
            actionTitle = "Open Login Items"
            action = { model.openLoginItemsSettings() }
        case .notRegistered:
            level = .warning
            value = "Not registered"
            detail = "Enable it to collect other users and control system services."
            actionTitle = "Enable"
            action = { Task { await model.registerDaemonService() } }
            actionDisabled = actionDisabled
                || model.legacyServiceDetected
                || !model.daemonHelperPresent
                || !model.daemonPlistPresent
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
            detail = "The service is registered but the app is not receiving data. Try Retry connection."
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
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(value)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(level.color)
                }
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .disabled(actionDisabled)
            }
        }
        .padding(.vertical, 2)
    }
}
