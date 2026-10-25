import SwiftUI

struct SettingsView: View {
    @AppStorage(KBPreferences.tabAnimationsKey)
    private var tabAnimations = KBPreferences.tabAnimationsDefault
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

            if reduceMotion {
                Section {
                    Label("Tab animations are off while Reduce Motion is enabled in System Settings. Your preference is kept for when it is turned off.",
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
