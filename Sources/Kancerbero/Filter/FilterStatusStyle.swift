import SwiftUI
import KancerberoFilterContract

/// Single source of truth for how the network filter is presented in the
/// status bar, the sidebar footer and System status.
///
/// `FilterController.State.enabled` only proves that macOS has a saved filter
/// configuration (`NEFilterManager.isEnabled`). It does not prove that the
/// system extension was approved and is running, so `.enabled` is split using
/// XPC reachability.
enum FilterHealth: Equatable {
    case running
    case configuredNotRunning
    case disabled
    case notInstalled
    case requiresApproval
    case activating
    case unsupported
    case failed(String)

    /// Compact status-bar wording.
    var shortLabel: String {
        switch self {
        case .running: return "Filter"
        case .configuredNotRunning: return "Filter idle"
        case .disabled: return "Filter off"
        case .requiresApproval: return "Approval"
        case .activating: return "Filter…"
        case .notInstalled, .unsupported: return "No filter"
        case .failed: return "Error"
        }
    }

    /// Sidebar wording: spell out that this is the Network Extension.
    var sidebarLabel: String {
        switch self {
        case .running: return "Network extension filter: on"
        case .configuredNotRunning: return "Network extension filter: not running"
        case .disabled: return "Network extension filter: off"
        case .requiresApproval: return "Network extension filter: approval"
        case .activating: return "Network extension filter: starting"
        case .notInstalled, .unsupported: return "Network extension filter: unavailable"
        case .failed: return "Network extension filter: error"
        }
    }

    /// Status-bar and sidebar tint.
    var tint: Color {
        switch self {
        case .running: return .green
        case .configuredNotRunning, .disabled, .notInstalled,
             .requiresApproval, .activating: return .orange
        case .failed: return .red
        case .unsupported: return .gray
        }
    }

    var help: String {
        switch self {
        case .running:
            return "Network filter: running and connected"
        case .configuredNotRunning:
            return "Network filter: enabled in macOS, but the network extension is not "
                + "answering. Turn on Kancerbero Filter in System Settings → General → "
                + "Login Items & Extensions → Network Extensions."
        case .disabled:
            return "Network filter: disabled"
        case .requiresApproval:
            return "Network filter: approval required — open System Settings → General → "
                + "Login Items & Extensions → Network Extensions."
        case .activating:
            return "Network filter: activating…"
        case .notInstalled:
            return "Network filter: not installed"
        case .unsupported:
            return "Network filter: unsupported build"
        case .failed(let message):
            return "Network filter: failed — \(message)"
        }
    }

    /// Severity used by System status. Kept separate from `tint` because
    /// `disabled` is orange in the status bar but informational in System
    /// status, and `unsupported` is gray in the bar but an error there.
    enum Severity {
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

    var severity: Severity {
        switch self {
        case .running: return .ok
        case .disabled: return .info
        case .notInstalled, .requiresApproval, .activating,
             .configuredNotRunning: return .warning
        case .unsupported, .failed: return .error
        }
    }

    /// Value shown next to the row title in System status and in
    /// accessibility labels.
    var systemValue: String {
        switch self {
        case .running: return "Running"
        case .configuredNotRunning: return "Not running"
        case .disabled: return "Disabled"
        case .notInstalled: return "Not installed"
        case .requiresApproval: return "Approval required"
        case .activating: return "Activating…"
        case .unsupported: return "Unsupported build"
        case .failed: return "Failed"
        }
    }

    /// Detail shown under the "Filter extension" row in System status.
    func systemDetail(failureGuidance: String?) -> String {
        switch self {
        case .running:
            return "The filter extension is running and reporting flows."
        case .configuredNotRunning:
            return "The filter is configured in macOS, but the network extension is not "
                + "answering. Turn on Kancerbero Filter in System Settings → General → "
                + "Login Items & Extensions → Network Extensions."
        case .disabled:
            return "Not enabled. Enabling installs the system extension and asks for "
                + "approval in Settings if macOS has not approved it yet."
        case .notInstalled:
            return "Install the filter system extension, then turn it on in System Settings "
                + "→ General → Login Items & Extensions → Network Extensions."
        case .requiresApproval:
            return "Open System Settings → General → Login Items & Extensions → Network "
                + "Extensions and turn on Kancerbero Filter."
        case .activating:
            return "Waiting for macOS to activate the system extension."
        case .unsupported:
            return "This build does not carry the filter system-extension entitlements. "
                + "Sign with Developer ID and provisioning profiles via "
                + "Config/Signing.local.xcconfig."
        case .failed(let message):
            return [message, failureGuidance].compactMap { $0 }.joined(separator: " ")
        }
    }
}

extension FilterModel {
    /// Resolves the controller state plus XPC reachability exactly once; every
    /// presentation surface reads this.
    var filterHealth: FilterHealth {
        switch controller.state {
        case .unsupported: return .unsupported
        case .notInstalled: return .notInstalled
        case .requiresApproval: return .requiresApproval
        case .activating: return .activating
        case .disabled: return .disabled
        case .failed(let message): return .failed(message)
        case .enabled: return isConnected ? .running : .configuredNotRunning
        }
    }

    var filterStatusLabel: String { filterHealth.shortLabel }
    var filterSidebarLabel: String { filterHealth.sidebarLabel }
    var filterStatusTint: Color { filterHealth.tint }
    var filterStatusHelp: String { filterHealth.help }
}

/// Compact, colored policy pill shared by the Filter rules window and the
/// Processes Guard column. The owning surface decides whether it is wrapped
/// in a Menu (editable) or shown read-only.
struct PolicyBadge: View {
    let policy: FilterPolicy

    var body: some View {
        Text(policy.title)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                Capsule().fill(color.opacity(0.16))
            }
            .foregroundStyle(color)
            .fixedSize()
    }

    private var color: Color {
        switch policy {
        case .ask: return .orange
        case .allow: return .green
        case .deny: return .red
        }
    }
}
