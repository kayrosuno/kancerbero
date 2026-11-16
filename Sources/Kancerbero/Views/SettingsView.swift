import SwiftUI

struct SettingsView: View {
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

    /// Keeps the picker and the stored value on one of the supported windows.
    private var activeWindowSelection: Binding<Int> {
        Binding(
            get: { KBPreferences.activeWindow(stored: activeWindowSeconds) },
            set: { activeWindowSeconds = KBPreferences.activeWindow(stored: $0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Startup interval", selection: $startupInterval) {
                    Text("0.5 s").tag(0.5)
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                }
                .pickerStyle(.menu)

                Text("Sampling cadence used when Kancerbero launches. The toolbar selector changes the current session only; it does not modify this value.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Sampling")
            }

            Section {
                Picker("Active connections window", selection: activeWindowSelection) {
                    ForEach(KBPreferences.activeWindowOptions, id: \.self) { seconds in
                        Text("\(seconds) s").tag(seconds)
                    }
                }
                .pickerStyle(.menu)

                Text("A connection counts as active while it has moved data within this window. It drives the Active metric and the Active filter in Networking.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Network activity")
            }

            Section {
                Toggle("Animate tab changes", isOn: $tabAnimations)
                    .toggleStyle(.switch)

                Text("Animates section changes, the Networking and Disk sub-tabs, and the sidebar and sub-tab pill highlights.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Navigation")
            }

            Section {
                Toggle("Animate status bar values", isOn: $statusBarTextAnimations)
                    .toggleStyle(.switch)

                Text("Animates the counters, rates and timestamp in the bottom status bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Status bar")
            }

            Section {
                Picker("Dock icon", selection: $dockIconStyle) {
                    ForEach(DockIconStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text("Shows a live graph in the Dock instead of the application icon. “Show Application Icon” restores the default; the Dock Icon menu offers the same choices.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Dock")
            }

            Section {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!updater.isEnabled)

                Toggle("Automatically download updates", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.setAutomaticallyDownloadsUpdates($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!updater.isEnabled
                          || !updater.allowsAutomaticUpdates
                          || !updater.automaticallyChecksForUpdates)

                Picker("Check for updates", selection: Binding(
                    get: { updater.updateCheckInterval },
                    set: { updater.setUpdateCheckInterval($0) }
                )) {
                    Text("Hourly").tag(3600.0)
                    Text("Daily").tag(86400.0)
                    Text("Weekly").tag(604800.0)
                }
                .pickerStyle(.menu)
                .disabled(!updater.isEnabled)

                HStack {
                    Button("Check Now") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.isEnabled || !updater.canCheckForUpdates)

                    Spacer()

                    Text(updater.statusText)
                        .foregroundStyle(.secondary)
                }

                Text("Kancerbero \(model.appVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !updater.isEnabled {
                    Text("Updates are disabled in this build.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !model.appIsInApplications {
                    Label("Move Kancerbero to /Applications to install updates.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                if let message = model.daemonUpdateMessage {
                    Label(message, systemImage: "gearshape.2")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if filter.extensionRequiresReboot {
                    Label("The network filter update completes after a restart.",
                          systemImage: "arrow.clockwise")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if filter.extensionNeedsUpdate {
                    Label("The network filter will be updated automatically.",
                          systemImage: "shield.lefthalf.filled")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let error = updater.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Updates")
            }

            if reduceMotion {
                Section {
                    Label("Animations are off while Reduce Motion is enabled in System Settings. Your preferences are kept for when it is turned off.",
                          systemImage: "accessibility")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
