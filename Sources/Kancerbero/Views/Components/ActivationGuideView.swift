import AppKit
import ServiceManagement
import SwiftUI

/// The two macOS approvals Kancerbero can need. Each guide mirrors what
/// LaunchControl shows when its helper needs approval: an illustration of the
/// relevant System Settings pane, the exact list to look for, and a button that
/// opens Settings.
enum ActivationGuide: String, Identifiable, CaseIterable {
    case networkExtension
    case backgroundService

    var id: String { rawValue }

    var title: String {
        switch self {
        case .networkExtension: return "How to activate the network extension"
        case .backgroundService: return "How to activate the background service"
        }
    }

    var intro: String {
        switch self {
        case .networkExtension:
            return "macOS manages system extensions under Login Items & Extensions, "
                + "not inside Kancerbero."
        case .backgroundService:
            return "macOS manages background helpers under Login Items & Extensions, "
                + "not inside Kancerbero."
        }
    }

    var highlight: SettingsMockupView.Highlight {
        switch self {
        case .networkExtension: return .networkExtensions
        case .backgroundService: return .allowInTheBackground
        }
    }

    var steps: [String] {
        switch self {
        case .networkExtension:
            return [
                "Open System Settings → General.",
                "Choose Login Items & Extensions.",
                "Under “Network Extensions”, turn on Kancerbero Filter.",
                "Return to Kancerbero. This status turns green within a few seconds."
            ]
        case .backgroundService:
            return [
                "Open System Settings → General.",
                "Choose Login Items & Extensions.",
                "Under “Allow in the Background”, turn on Kancerbero.",
                "Return to Kancerbero and click Retry connection."
            ]
        }
    }
}

/// Sheet showing how to approve the network extension or the background
/// service. All actions use public SMAppService/NetworkExtension APIs; nothing
/// here runs sudo.
struct ActivationGuideView: View {
    let guide: ActivationGuide
    @Environment(AppModel.self) private var model
    @Environment(FilterModel.self) private var filter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            SettingsMockupView(highlight: guide.highlight)
            steps
            currentState
            Divider()
            actions
        }
        .padding(18)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            AppLogoView(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(guide.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(guide.intro)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
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

    // MARK: - Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.accentColor))
                    Text(step)
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous))
    }

    // MARK: - Live state

    private var currentState: some View {
        let state = statePresentation
        return HStack(spacing: 7) {
            Circle()
                .fill(state.tint)
                .frame(width: 7, height: 7)
            Text("Current state: \(state.text)")
                .font(.system(size: 10, weight: .medium))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var statePresentation: (text: String, tint: Color) {
        switch guide {
        case .networkExtension:
            let health = filter.filterHealth
            return (health.systemValue, health.tint)
        case .backgroundService:
            switch model.serviceStatus {
            case .enabled:
                if model.usingDaemon {
                    return ("Connected", .green)
                }
                return (model.daemonProcessRunning ? "Daemon not answering"
                        : "Registered, daemon not running", .orange)
            case .requiresApproval:
                return ("Needs approval", .orange)
            case .notRegistered:
                return ("Not registered", .orange)
            case .notFound:
                return ("Unavailable", .red)
            @unknown default:
                return ("Unknown", .secondary)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Open System Settings") {
                model.openLoginItemsSettings()
            }
            .buttonStyle(.borderedProminent)

            if let contextual = contextualAction {
                Button(contextual.title) {
                    contextual.action()
                }
                .buttonStyle(.bordered)
                .disabled(contextualDisabled)
            }

            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    private var contextualDisabled: Bool {
        switch guide {
        case .networkExtension:
            return filter.isBusy || filter.isConnecting
        case .backgroundService:
            return model.serviceActionInFlight
                || model.legacyServiceDetected
                || !model.daemonHelperPresent
                || !model.daemonPlistPresent
        }
    }

    private var contextualAction: (title: String, action: () -> Void)? {
        switch guide {
        case .networkExtension:
            switch filter.filterHealth {
            case .notInstalled, .requiresApproval:
                return ("Install filter extension", { Task { await filter.enableFilter() } })
            case .configuredNotRunning:
                return ("Retry connection", { Task { await filter.connect() } })
            case .failed:
                return ("Retry", { Task { await filter.enableFilter() } })
            case .running, .disabled, .activating, .unsupported:
                return nil
            }
        case .backgroundService:
            if model.serviceStatus == .notRegistered {
                return ("Enable background service",
                        { Task { await model.registerDaemonService() } })
            }
            if !model.usingDaemon {
                return ("Retry connection", { model.retryDaemonConnection() })
            }
            return nil
        }
    }
}

/// Stylized illustration of System Settings → General → Login Items &
/// Extensions, with the section the user must change highlighted. Drawn with
/// SwiftUI primitives so it adapts to light/dark and stays sharp at any scale.
/// It intentionally reproduces the layout of the real pane, not any third-party
/// artwork.
struct SettingsMockupView: View {
    enum Highlight {
        case allowInTheBackground
        case networkExtensions
    }

    let highlight: Highlight

    private struct SidebarRow {
        let icon: String
        let title: String
        let selected: Bool
    }

    private let sidebarRows: [SidebarRow] = [
        SidebarRow(icon: "wifi", title: "Wi-Fi", selected: false),
        SidebarRow(icon: "dot.radiowaves.left.and.right", title: "Network", selected: false),
        SidebarRow(icon: "bell.badge", title: "Notifications", selected: false),
        SidebarRow(icon: "speaker.wave.2", title: "Sound", selected: false),
        SidebarRow(icon: "switch.2", title: "General", selected: true),
        SidebarRow(icon: "paintpalette", title: "Appearance", selected: false),
        SidebarRow(icon: "hand.raised", title: "Privacy & Security", selected: false)
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .aspectRatio(827.0 / 737.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        switch highlight {
        case .allowInTheBackground:
            return "Illustration of System Settings, Login Items & Extensions, "
                + "with Allow in the Background highlighted."
        case .networkExtensions:
            return "Illustration of System Settings, Login Items & Extensions, "
                + "with Network Extensions highlighted."
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: "magnifyingglass").font(.system(size: 7))
                Text("Search").font(.system(size: 7))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            HStack(spacing: 5) {
                Circle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 12, height: 12)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sign in").font(.system(size: 7, weight: .medium))
                    Text("Apple Account").font(.system(size: 6)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)

            ForEach(sidebarRows, id: \.title) { row in
                HStack(spacing: 5) {
                    Image(systemName: row.icon)
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 13, height: 13)
                        .background {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(row.selected ? Color.accentColor
                                      : Color.secondary.opacity(0.55))
                        }
                    Text(row.title)
                        .font(.system(size: 7, weight: row.selected ? .semibold : .regular))
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background {
                    if row.selected {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor)
                    }
                }
                .foregroundStyle(row.selected ? Color.white : Color.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(width: 148)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.system(size: 7, weight: .semibold))
                Text("Login Items & Extensions")
                    .font(.system(size: 9, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)

            section(title: "Open at Login",
                    subtitle: "These items will open automatically when you log in.") {
                listBackground {
                    Text("No items")
                        .font(.system(size: 7))
                        .foregroundStyle(.tertiary)
                        .padding(6)
                }
            }

            section(title: "Allow in the Background",
                    subtitle: "Applications add background items to perform tasks when "
                        + "the application isn’t open.") {
                listBackground {
                    itemRow(name: "Kancerbero",
                            detail: "1 item · 1 item affects all users",
                            toggleOn: true,
                            highlighted: highlight == .allowInTheBackground,
                            useAppIcon: true,
                            fallbackSymbol: "gearshape.2")
                }
            }

            section(title: "Network Extensions",
                    subtitle: "Network extensions may filter or monitor network traffic.") {
                listBackground {
                    itemRow(name: "Kancerbero Filter",
                            detail: "Filters connections for watched processes",
                            toggleOn: true,
                            highlighted: highlight == .networkExtensions,
                            useAppIcon: false,
                            fallbackSymbol: "shield.lefthalf.filled")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(title: String,
                                        subtitle: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private func listBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func itemRow(name: String,
                         detail: String,
                         toggleOn: Bool,
                         highlighted: Bool,
                         useAppIcon: Bool,
                         fallbackSymbol: String) -> some View {
        HStack(spacing: 5) {
            if useAppIcon {
                AppLogoView(size: 13)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.accentColor)
                    }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.system(size: 7, weight: .medium))
                Text(detail).font(.system(size: 6)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            toggleMock(on: toggleOn, highlighted: highlighted)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            }
        }
    }

    private func toggleMock(on: Bool, highlighted: Bool) -> some View {
        Capsule()
            .fill(on ? Color.accentColor : Color.secondary.opacity(0.35))
            .frame(width: 20, height: 11)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 9, height: 9)
                    .padding(1)
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            }
            .overlay {
                if highlighted {
                    Circle()
                        .strokeBorder(Color.red, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
    }
}
