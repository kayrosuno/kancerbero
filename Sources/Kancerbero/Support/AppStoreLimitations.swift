import SwiftUI

enum AppStoreLimitationsWindow {
    static let id = "app-store-limitations"
}

#if APP_STORE

enum AppStoreLimitations {
    static let downloadURL = URL(string: "https://kayros.uno")!
    static let daemonUnavailable =
        "Background service and privileged actions are unavailable in the Mac App Store version."
    static let sandboxUnavailable =
        "This action is unavailable in the Mac App Store version."
}

/// Small inline notice used next to the features the sandboxed App Store build
/// cannot provide. It opens the full explanation window.
struct AppStoreLimitationNotice: View {
    let text: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.94, green: 0.56, blue: 0.18))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Why?") {
                openWindow(id: AppStoreLimitationsWindow.id)
            }
            .buttonStyle(.link)
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.94, green: 0.56, blue: 0.18).opacity(0.08))
        }
    }
}

struct AppStoreLimitationsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(KBTheme.brandGradient)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac App Store version")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Sandboxed build with the limits Apple requires.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                bullet("shield.lefthalf.filled",
                       "App Sandbox",
                       "The app can only read folders you choose with the folder picker. Typed paths and the home folder are not available.")
                bullet("gearshape.2.fill",
                       "No background service",
                       "The Mac App Store version cannot install a root helper: other users' processes and sockets, system service control and privileged cleanup or termination are unavailable.")
                bullet("externaldrive.fill",
                       "No disk operations",
                       "Mounting, unmounting and ejecting volumes is unavailable; use Disk Utility.")
                bullet("network",
                       "Network filter available",
                       "The content filter system extension and its per-flow approvals work in this version.")
                bullet("arrow.triangle.2.circlepath",
                       "Updates",
                       "Updates are delivered by the Mac App Store instead of Sparkle.")
            }

            Text("For the full version, with the background service, all disks, all users and unrestricted analysis, download Kancerbero from kayros.uno.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link(destination: AppStoreLimitations.downloadURL) {
                    Label("Download the full version at kayros.uno", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppSection.disk.tint)
                Spacer()
            }
        }
        .padding(22)
        .frame(minWidth: 560, minHeight: 440, alignment: .topLeading)
        .background { KBTheme.background }
    }

    private func bullet(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppSection.disk.tint)
                .frame(width: 20, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppSection.disk.tint.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#endif
