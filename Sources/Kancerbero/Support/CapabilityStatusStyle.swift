import SwiftUI

/// Didactic presentation of `net.statistics_privcheck`, shared by the status
/// bar, the sidebar and System status.
extension AppModel {
    var trafficAccessLabel: String {
        switch privcheck {
        case 0: return "Traffic data: full"
        case 1...: return "Traffic data: limited"
        default: return "Traffic data: n/a"
        }
    }

    var trafficAccessShortLabel: String {
        switch privcheck {
        case 0: return "Traffic full"
        case 1...: return "Traffic limited"
        default: return "Traffic n/a"
        }
    }

    var trafficAccessValue: String {
        switch privcheck {
        case 0: return "Full"
        case 1...: return "Limited"
        default: return "Unavailable"
        }
    }

    var trafficAccessDetail: String {
        switch privcheck {
        case 0:
            return "NetworkStatistics reports per-process traffic (net.statistics_privcheck = 0)."
        case 1...:
            return "Per-process traffic is degraded: this process lacks Apple's private NetworkStatistics entitlement (net.statistics_privcheck = \(privcheck)). Interface totals are still accurate."
        default:
            return "net.statistics_privcheck could not be read; per-process traffic may be incomplete."
        }
    }

    var trafficAccessTint: Color {
        switch privcheck {
        case 0: return .green
        case 1...: return .orange
        default: return .gray
        }
    }

    var trafficAccessHelp: String {
        switch privcheck {
        case 0:
            return "Traffic data: full. net.statistics_privcheck = 0, so NetworkStatistics reports per-process traffic."
        case 1...:
            return "Traffic data: limited. net.statistics_privcheck = \(privcheck): this process lacks Apple's private NetworkStatistics entitlement, so per-process traffic falls back to degraded mode."
        default:
            return "Traffic data: n/a. net.statistics_privcheck could not be read."
        }
    }
}
