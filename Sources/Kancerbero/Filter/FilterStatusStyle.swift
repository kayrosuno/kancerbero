import SwiftUI

/// Shared presentation of the network filter state, used by the status bar,
/// the sidebar and System status so they all read the same.
extension FilterModel {
    var filterStatusLabel: String {
        switch controller.state {
        case .enabled: return "Filter"
        case .disabled: return "Filter off"
        case .requiresApproval: return "Approval"
        case .activating: return "Filter…"
        case .notInstalled, .unsupported: return "No filter"
        case .failed: return "Error"
        }
    }

    /// Sidebar wording: spell out that this is the Network Extension.
    var filterSidebarLabel: String {
        switch controller.state {
        case .enabled: return "Network extension filter: on"
        case .disabled: return "Network extension filter: off"
        case .requiresApproval: return "Network extension filter: approval"
        case .activating: return "Network extension filter: starting"
        case .notInstalled, .unsupported: return "Network extension filter: unavailable"
        case .failed: return "Network extension filter: error"
        }
    }

    var filterStatusTint: Color {
        switch controller.state {
        case .enabled:
            return isConnected ? .green : .orange
        case .failed:
            return .red
        case .unsupported:
            return .gray
        case .disabled, .notInstalled, .requiresApproval, .activating:
            return .orange
        }
    }

    var filterStatusHelp: String {
        var text = "Network filter: \(controller.state.title)"
        if case .failed(let message) = controller.state {
            text += " — \(message)"
        }
        return text
    }
}
