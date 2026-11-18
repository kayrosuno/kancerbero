import SwiftUI

struct SettingsView: View {
    @AppStorage(KBPreferences.appearanceModeKey)
    private var appearanceRaw = KBPreferences.appearanceModeDefault
    @AppStorage(KBPreferences.diskUnitSystemKey)
    private var diskUnitRaw = KBPreferences.diskUnitSystemDefault
    @AppStorage(KBPreferences.tabAnimationsKey)
    private var tabAnimations = KBPreferences.tabAnimationsDefault
    @AppStorage(KBPreferences.statusBarTextAnimationsKey)
    private var statusBarTextAnimations = KBPreferences.statusBarTextAnimationsDefault
    @AppStorage(KBPreferences.startupIntervalKey)
    private var startupInterval = KBPreferences.startupIntervalDefault
    @AppStorage(KBPreferences.dockIconStyleKey)
    private var dockIconStyle = KBPreferences.dockIconStyleDefault
    @AppStorage(KBPreferences.activeWindowKey)
    private var activeWindowSeconds = KBPreferences.activeWindowDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    @Environment(FilterModel.self) private var filter
    @Environment(UpdaterModel.self) private var updater

    @State private var category: SettingsCategory = .general
    @Namespace private var railNamespace

    /// Keeps the choice bar and the stored value on one of the supported windows.
    private var activeWindowSelection: Binding<Int> {
        Binding(
            get: { KBPreferences.activeWindow(stored: activeWindowSeconds) },
            set: { activeWindowSeconds = KBPreferences.activeWindow(stored: $0) }
        )
    }

    private var automaticChecks: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var automaticDownloads: Binding<Bool> {
        Binding(
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.setAutomaticallyDownloadsUpdates($0) }
        )
    }

    private var updateInterval: Binding<TimeInterval> {
        Binding(
            get: { updater.updateCheckInterval },
            set: { updater.setUpdateCheckInterval($0) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle()
                .fill(.quaternary.opacity(0.35))
                .frame(width: 1)
            detail
        }
        .frame(minWidth: 880, minHeight: 620)
        .background { KBTheme.background }
        .onChange(of: appearanceRaw) { _, raw in
            KBAppearance.apply(KBAppearanceMode(rawValue: raw) ?? .system)
        }
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 16) {
            brand

            VStack(spacing: 3) {
                ForEach(SettingsCategory.allCases) { item in
                    railRow(item)
                }
            }

            Spacer(minLength: 12)

            railFooter
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: 232)
        .background(.ultraThinMaterial)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            AppLogoView(size: 40)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kancerbero")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Settings")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 2)
    }

    private func railRow(_ item: SettingsCategory) -> some View {
        let selected = category == item
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                category = item
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected
                                  ? AnyShapeStyle(Color.white.opacity(0.22))
                                  : AnyShapeStyle(KBTheme.gradient(item.tint)))
                    }
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(KBTheme.gradient(item.tint))
                        .matchedGeometryEffect(id: "railSelection", in: railNamespace)
                        .shadow(color: item.tint.opacity(0.32), radius: 5, y: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var railFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
#if APP_STORE
                Circle()
                    .fill(Color(red: 0.20, green: 0.72, blue: 0.52))
                    .frame(width: 6, height: 6)
                Text("App Store · Sandboxed")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
#else
                Circle()
                    .fill(model.usingDaemon
                          ? Color(red: 0.20, green: 0.72, blue: 0.52)
                          : Color(red: 0.94, green: 0.56, blue: 0.18))
                    .frame(width: 6, height: 6)
                Text(model.usingDaemon ? "Background daemon" : "Local mode")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
#endif
                Spacer(minLength: 4)
            }
            .foregroundStyle(.secondary)

            Text("v\(model.appVersion)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        }
    }

    // MARK: - Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                content
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hero: some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(KBTheme.gradient(category.tint))
                }
                .shadow(color: category.tint.opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(category.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        switch category {
        case .general:
            generalSettings
        case .monitoring:
            monitoringSettings
        case .interface:
            interfaceSettings
        case .updates:
            updatesSettings
        }
    }

    // MARK: - General

    private var generalSettings: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Appearance",
                         subtitle: "How Kancerbero looks across every window.",
                         systemImage: "circle.lefthalf.filled",
                         tint: Color(red: 0.18, green: 0.62, blue: 0.94)) {
                SettingsRow(title: "Theme",
                            detail: "System follows macOS. Light and Dark override it for every window and menu.") {
                    SettingsChoiceBar(selection: $appearanceRaw, options: [
                        SettingsChoice(value: KBAppearanceMode.system.rawValue,
                                       title: "System", symbol: "circle.lefthalf.filled"),
                        SettingsChoice(value: KBAppearanceMode.light.rawValue,
                                       title: "Light", symbol: "sun.max.fill"),
                        SettingsChoice(value: KBAppearanceMode.dark.rawValue,
                                       title: "Dark", symbol: "moon.stars.fill")
                    ])
                }
            }

            SettingsCard(title: "Disk units",
                         subtitle: "Format used for sizes in Disk, the status bar and inspectors.",
                         systemImage: "internaldrive.fill",
                         tint: Color(red: 0.20, green: 0.70, blue: 0.62)) {
                SettingsRow(title: "File size units",
                            detail: "Decimal uses KB/MB/GB (base 1000, like Finder). Binary uses KiB/MiB/GiB (base 1024).") {
                    SettingsChoiceBar(selection: $diskUnitRaw, options: [
                        SettingsChoice(value: KBByteUnitSystem.decimal.rawValue, title: "Decimal"),
                        SettingsChoice(value: KBByteUnitSystem.binary.rawValue, title: "Binary")
                    ])
                }
            }

#if APP_STORE
            AppStoreLimitationNotice(
                text: "This Mac App Store version is sandboxed: no background service, privileged actions or unrestricted disk scanning.")
                .padding(.horizontal, 2)
#endif
        }
    }

    // MARK: - Monitoring

    private var monitoringSettings: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Sampling",
                         subtitle: "Cadence used by the dashboard and its charts.",
                         systemImage: "clock.fill",
                         tint: Color(red: 0.94, green: 0.56, blue: 0.18)) {
                SettingsRow(title: "Startup interval",
                            detail: "Used when Kancerbero launches. The toolbar selector changes only the current session.") {
                    SettingsChoiceBar(selection: $startupInterval, options: [
                        SettingsChoice(value: 0.5, title: "0.5 s"),
                        SettingsChoice(value: 1.0, title: "1 s"),
                        SettingsChoice(value: 2.0, title: "2 s"),
                        SettingsChoice(value: 5.0, title: "5 s")
                    ])
                }
            }

            SettingsCard(title: "Network activity",
                         subtitle: "What counts as an active connection.",
                         systemImage: "network",
                         tint: Color(red: 0.20, green: 0.70, blue: 0.62)) {
                SettingsRow(title: "Active window",
                            detail: "A connection counts as active while it has moved data within this window. It drives the Active metric and filter in Networking.") {
                    SettingsChoiceBar(selection: activeWindowSelection,
                                      options: KBPreferences.activeWindowOptions.map {
                                          SettingsChoice(value: $0, title: "\($0) s")
                                      })
                }
            }
        }
    }

    // MARK: - Interface

    private var interfaceSettings: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Motion",
                         subtitle: "Animations always respect Reduce Motion.",
                         systemImage: "sparkles",
                         tint: Color(red: 0.62, green: 0.42, blue: 0.95)) {
                SettingsRow(title: "Animate tab changes",
                            detail: "Section changes, the Networking and Disk sub-tabs, and the sidebar and pill highlights.") {
                    Toggle("", isOn: $tabAnimations)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Animate tab changes")
                }

                SettingsDivider()

                SettingsRow(title: "Animate status bar values",
                            detail: "Counters, rates and the timestamp in the bottom status bar.") {
                    Toggle("", isOn: $statusBarTextAnimations)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Animate status bar values")
                }

                if reduceMotion {
                    SettingsDivider()
                    SettingsCallout(
                        "Animations are off while Reduce Motion is enabled in System Settings. Your preferences are kept for when it is turned off.",
                        systemImage: "accessibility",
                        style: .info)
                }
            }

            SettingsCard(title: "Dock icon",
                         subtitle: "Show a live graph instead of the application icon.",
                         systemImage: "square.grid.2x2.fill",
                         tint: Color(red: 0.36, green: 0.50, blue: 0.90)) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                         count: 3),
                          spacing: 8) {
                    ForEach(DockIconStyle.allCases) { style in
                        DockIconTile(style: style,
                                     selected: dockIconStyle == style.rawValue) {
                            withAnimation(.snappy(duration: 0.2)) {
                                dockIconStyle = style.rawValue
                            }
                        }
                    }
                }
                .padding(14)

                SettingsDivider()

                SettingsRow(title: "History",
                            detail: "The live Dock graphs keep CPU, network, disk, memory and energy samples. Clearing frees them and the graphs restart.") {
                    Button("Clear history") {
                        model.clearHistories()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Updates

    private var updatesSettings: some View {
#if APP_STORE
        VStack(spacing: 14) {
            SettingsCard(title: "Updates",
                         subtitle: "Delivered by the Mac App Store.",
                         systemImage: "arrow.triangle.2.circlepath",
                         tint: Color(red: 0.20, green: 0.72, blue: 0.52)) {
                SettingsRow(title: "Kancerbero \(model.appVersion)",
                            detail: "Build \(model.appBuild)") {
                    EmptyView()
                }
                SettingsDivider()
                AppStoreLimitationNotice(
                    text: "Sparkle and external updates are not available in the Mac App Store version.")
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            if filter.extensionRequiresReboot || filter.extensionNeedsUpdate {
                SettingsCard(title: "Network filter",
                             subtitle: "System extension status.",
                             systemImage: "shield.lefthalf.filled",
                             tint: Color(red: 0.16, green: 0.62, blue: 0.94)) {
                    if filter.extensionRequiresReboot {
                        SettingsCallout("The network filter update completes after a restart.",
                                        systemImage: "arrow.clockwise",
                                        style: .warning)
                    } else if filter.extensionNeedsUpdate {
                        SettingsCallout("The network filter will be updated automatically.",
                                        systemImage: "shield.lefthalf.filled",
                                        style: .info)
                    }
                }
            }
        }
#else
        VStack(spacing: 14) {
            SettingsCard(title: "Automatic updates",
                         subtitle: "Sparkle keeps Kancerbero up to date.",
                         systemImage: "arrow.triangle.2.circlepath",
                         tint: Color(red: 0.20, green: 0.72, blue: 0.52)) {
                SettingsRow(title: "Check for updates automatically",
                            detail: "Looks for a new version in the background.") {
                    Toggle("", isOn: automaticChecks)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!updater.isEnabled)
                        .accessibilityLabel("Check for updates automatically")
                }

                SettingsDivider()

                SettingsRow(title: "Download updates automatically",
                            detail: "Requires automatic checks and a build that allows automatic updates.") {
                    Toggle("", isOn: automaticDownloads)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!updater.isEnabled
                                  || !updater.allowsAutomaticUpdates
                                  || !updater.automaticallyChecksForUpdates)
                        .accessibilityLabel("Download updates automatically")
                }

                SettingsDivider()

                SettingsRow(title: "Check frequency",
                            detail: "How often Sparkle looks for a new version.") {
                    Picker("", selection: updateInterval) {
                        Text("Hourly").tag(3600.0)
                        Text("Daily").tag(86400.0)
                        Text("Weekly").tag(604800.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 108)
                    .disabled(!updater.isEnabled)
                    .accessibilityLabel("Check frequency")
                }
            }

            SettingsCard(title: "Status",
                         subtitle: "Current version, update state and component health.",
                         systemImage: "info.circle.fill",
                         tint: Color(red: 0.16, green: 0.62, blue: 0.94)) {
                SettingsRow(title: "Kancerbero \(model.appVersion)",
                            detail: "Build \(model.appBuild) · \(updater.statusText)") {
                    Button("Check now") {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color(red: 0.16, green: 0.62, blue: 0.94))
                    .disabled(!updater.isEnabled || !updater.canCheckForUpdates)
                }

                SettingsDivider()

                if !updater.isEnabled {
                    SettingsCallout("Updates are disabled in this build.",
                                    systemImage: "hammer.fill",
                                    style: .info)
                }

                if !model.appIsInApplications {
                    SettingsCallout("Move Kancerbero to /Applications to install updates.",
                                    systemImage: "exclamationmark.triangle.fill",
                                    style: .warning)
                }

                if let message = model.daemonUpdateMessage {
                    SettingsCallout(message,
                                    systemImage: "gearshape.2.fill",
                                    style: .info)
                }

                if filter.extensionRequiresReboot {
                    SettingsCallout("The network filter update completes after a restart.",
                                    systemImage: "arrow.clockwise",
                                    style: .warning)
                } else if filter.extensionNeedsUpdate {
                    SettingsCallout("The network filter will be updated automatically.",
                                    systemImage: "shield.lefthalf.filled",
                                    style: .info)
                }

                if let error = updater.lastError {
                    SettingsCallout(error,
                                    systemImage: "xmark.octagon.fill",
                                    style: .error)
                }
            }
        }
#endif
    }
}

// MARK: - Categories

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case monitoring
    case interface
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .monitoring: return "Monitoring"
        case .interface: return "Interface"
        case .updates: return "Updates"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Appearance, size units and the disk format"
        case .monitoring: return "Sampling cadence and network activity"
        case .interface: return "Motion and how the Dock presents Kancerbero"
        case .updates: return "Sparkle, versions and component status"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .monitoring: return "gauge.with.dots.needle.50percent"
        case .interface: return "sparkles"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(red: 0.18, green: 0.62, blue: 0.94)
        case .monitoring: return Color(red: 0.94, green: 0.56, blue: 0.18)
        case .interface: return Color(red: 0.62, green: 0.42, blue: 0.95)
        case .updates: return Color(red: 0.20, green: 0.72, blue: 0.52)
        }
    }
}

// MARK: - Card

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let content: Content

    init(title: String,
         subtitle: String,
         systemImage: String,
         tint: Color,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(KBTheme.gradient(tint))
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [tint.opacity(0.24), Color.white.opacity(0.04)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .opacity(0.4)
            .padding(.horizontal, 14)
    }
}

// MARK: - Rows

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String
    let trailing: Trailing

    init(title: String,
         detail: String,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private enum SettingsCalloutStyle {
    case info
    case warning
    case error

    var tint: Color {
        switch self {
        case .info: return .secondary
        case .warning: return Color(red: 0.94, green: 0.56, blue: 0.18)
        case .error: return Color(red: 0.90, green: 0.35, blue: 0.30)
        }
    }

    var textColor: Color {
        switch self {
        case .info: return .secondary
        case .warning: return Color(red: 0.94, green: 0.56, blue: 0.18)
        case .error: return Color(red: 0.90, green: 0.35, blue: 0.30)
        }
    }
}

private struct SettingsCallout: View {
    let text: String
    let systemImage: String
    let style: SettingsCalloutStyle

    init(_ text: String,
         systemImage: String,
         style: SettingsCalloutStyle) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(style.tint)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(style.textColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(style.tint.opacity(0.08))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Choices

private struct SettingsChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var symbol: String? = nil

    var id: Value { value }
}

private struct SettingsChoiceBar<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SettingsChoice<Value>]

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = selection == option.value
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = option.value
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(option.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background {
                        if selected {
                            Capsule(style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "choice", in: namespace)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background {
            Capsule(style: .continuous)
                .fill(.quaternary.opacity(0.45))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
        .fixedSize()
    }
}

// MARK: - Dock grid

private struct DockIconTile: View {
    let style: DockIconStyle
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: style.settingsSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : style.settingsTint)
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected
                                  ? AnyShapeStyle(KBTheme.gradient(style.settingsTint))
                                  : AnyShapeStyle(style.settingsTint.opacity(0.12)))
                    }
                Text(style.settingsShortTitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? style.settingsTint.opacity(0.10) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected
                                  ? style.settingsTint.opacity(0.85)
                                  : Color.primary.opacity(hovering ? 0.14 : 0.07),
                                  lineWidth: selected ? 1.4 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.snappy(duration: 0.15)) {
                hovering = inside
            }
        }
        .help(style.title)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension DockIconStyle {
    var settingsSymbol: String {
        switch self {
        case .applicationIcon: return "app.fill"
        case .cpuUsage: return "cpu"
        case .cpuHistory: return "chart.xyaxis.line"
        case .networkUsage: return "network"
        case .diskActivity: return "internaldrive"
        case .memoryUsage: return "memorychip"
        case .memoryPressure: return "gauge.with.dots.needle.50percent"
        case .gpuUsage: return "rectangle.3.group"
        case .energyUsage: return "bolt.fill"
        }
    }

    var settingsShortTitle: String {
        switch self {
        case .applicationIcon: return "App icon"
        case .cpuUsage: return "CPU"
        case .cpuHistory: return "CPU history"
        case .networkUsage: return "Network"
        case .diskActivity: return "Disk"
        case .memoryUsage: return "Memory"
        case .memoryPressure: return "Pressure"
        case .gpuUsage: return "GPU"
        case .energyUsage: return "Energy"
        }
    }

    var settingsTint: Color {
        switch self {
        case .applicationIcon: return Color(red: 0.18, green: 0.62, blue: 0.94)
        case .cpuUsage: return Color(red: 0.20, green: 0.72, blue: 0.52)
        case .cpuHistory: return Color(red: 0.20, green: 0.70, blue: 0.62)
        case .networkUsage: return Color(red: 0.16, green: 0.62, blue: 0.94)
        case .diskActivity: return Color(red: 0.94, green: 0.56, blue: 0.18)
        case .memoryUsage: return Color(red: 0.62, green: 0.42, blue: 0.95)
        case .memoryPressure: return Color(red: 0.90, green: 0.35, blue: 0.30)
        case .gpuUsage: return Color(red: 0.36, green: 0.50, blue: 0.90)
        case .energyUsage: return Color(red: 0.92, green: 0.74, blue: 0.24)
        }
    }
}
