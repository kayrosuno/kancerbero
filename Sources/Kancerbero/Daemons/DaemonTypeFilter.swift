import SwiftUI

enum DaemonTypeFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case agents
    case daemons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .agents: return "Agents"
        case .daemons: return "Daemons"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .agents: return "person.crop.circle"
        case .daemons: return "gearshape.2"
        }
    }

    var tint: Color { AppSection.daemons.tint }

    var serviceType: DaemonServiceType? {
        switch self {
        case .all: return nil
        case .agents: return .agent
        case .daemons: return .daemon
        }
    }
}

extension DaemonTypeFilter: PillTabItem {}
