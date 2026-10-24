import SwiftUI
import KancerberoCore

struct DaemonDetailView: View {
    let service: KBDaemonService
    let inFlight: Bool
    let canControlSystem: Bool
    let statusMessage: String?
    let onAction: (KBDaemonAction) -> Void
    let onReveal: () -> Void
    let onClose: () -> Void

    private var controlsDisabled: Bool {
        inFlight || (service.domain == .system && !canControlSystem)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider().opacity(0.5)
                metadata
                Divider().opacity(0.5)
                actions
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if service.domain == .system && !canControlSystem {
                    Text("System services are read-only. Install the daemon as root to control them.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(14)
        }
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KBTheme.gradient(service.domain == .system
                                              ? Color(red: 0.62, green: 0.42, blue: 0.95)
                                              : AppSection.networking.tint))
                        .frame(width: 38, height: 38)
                    Image(systemName: service.domain == .system ? "gearshape.2" : "person.crop.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.label)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Text(service.domain.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        DaemonStateBadge(state: service.state)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close inspector")
            }

            HStack(spacing: 14) {
                stat("PID", service.pid.map { String($0) } ?? "—")
                stat("Last exit", service.lastExitStatus.map { String($0) } ?? "—")
                stat("UID", service.uid.map { String($0) } ?? "—")
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 7) {
            row("Program", service.program.isEmpty ? "—" : service.program)
            row("Arguments", service.arguments.isEmpty ? "—" : service.arguments)
            row("Plist", service.plistPath.isEmpty ? "—" : service.plistPath)
            row("Run at load", service.runAtLoad ? "Yes" : "No")
            row("Keep alive", service.keepAlive ? "Yes" : "No")
            if let interval = service.startInterval {
                row("Start interval", "\(interval) s")
            }
            if !service.workingDirectory.isEmpty {
                row("Working dir", service.workingDirectory)
            }
            if !service.environment.isEmpty {
                row("Environment", service.environment
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", "))
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                actionButton("Start", icon: "play.fill", action: .start,
                             enabled: service.isLoaded && !service.isRunning)
                actionButton("Restart", icon: "arrow.clockwise", action: .restart,
                             enabled: service.isLoaded)
                actionButton("Stop", icon: "stop.fill", action: .stop,
                             enabled: service.isRunning)
                actionButton(service.isDisabled ? "Enable" : "Disable",
                             icon: service.isDisabled ? "checkmark.circle" : "slash.circle",
                             action: service.isDisabled ? .enable : .disable,
                             enabled: true)
                actionButton("Load", icon: "arrow.down.circle", action: .load,
                             enabled: !service.isLoaded && !service.plistPath.isEmpty)
                actionButton("Unload", icon: "arrow.up.circle", action: .unload,
                             enabled: service.isLoaded)
            }

            Button {
                onReveal()
            } label: {
                Label("Reveal plist in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(service.plistPath.isEmpty)
        }
    }

    private func actionButton(_ title: String, icon: String,
                              action: KBDaemonAction, enabled: Bool) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled || controlsDisabled)
    }
}
