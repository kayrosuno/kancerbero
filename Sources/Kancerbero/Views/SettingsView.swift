import SwiftUI

struct SettingsView: View {
    @AppStorage(KBPreferences.tabAnimationsKey)
    private var tabAnimations = KBPreferences.tabAnimationsDefault
    @AppStorage(KBPreferences.statusBarTextAnimationsKey)
    private var statusBarTextAnimations = KBPreferences.statusBarTextAnimationsDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
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
