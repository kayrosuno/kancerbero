import SwiftUI
import KancerberoCore

/// Shared copy and color for the Full Disk Access row, banner, alert and guide,
/// so the same permission is described consistently everywhere.
extension AppModel {
    var fullDiskAccessValue: String {
        switch fullDiskAccess {
        case .granted: return "Granted"
        case .denied: return "Not granted"
        case .unknown: return "Unknown"
        }
    }

    var fullDiskAccessTint: Color {
        switch fullDiskAccess {
        case .granted: return .green
        case .denied: return .orange
        case .unknown: return .gray
        }
    }

    var fullDiskAccessDetail: String {
        switch fullDiskAccess {
        case .granted:
            return "Kancerbero can read data protected by macOS, including other apps' "
                + "containers and group containers. The grant also covers the background helper."
        case .denied:
            if usingDaemon && daemonIsRoot {
                return "macOS protects other apps' data. The root helper does not bypass TCC; "
                    + "allow Kancerbero in Privacy & Security → Full Disk Access to remove their "
                    + "containers and protected leftovers."
            }
            return "macOS protects other apps' data. Allow Kancerbero in Privacy & Security → "
                + "Full Disk Access to remove their containers and protected leftovers."
        case .unknown:
            return "No protected test path was available, so Kancerbero cannot confirm the "
                + "permission. Open System Settings → Privacy & Security → Full Disk Access to check."
        }
    }

    var fullDiskAccessBannerDetail: String {
        "macOS protects other apps' data. Their containers, group containers and Application "
            + "Scripts cannot be removed until Kancerbero is allowed. After granting access, "
            + "restart Kancerbero if this message remains."
    }

    var fullDiskAccessAlertGuidance: String {
        "macOS protects other apps' data. Allow Kancerbero in System Settings → Privacy & "
            + "Security → Full Disk Access and try again."
    }
}
