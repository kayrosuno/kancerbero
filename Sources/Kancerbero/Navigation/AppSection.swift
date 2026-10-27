import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case networking
    case disk
    case daemons
    case cpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .networking: return "Networking"
        case .disk: return "Disk"
        case .daemons: return "Daemons"
        case .cpu: return "CPU"
        }
    }

    var subtitle: String {
        switch self {
        case .networking: return "Traffic & connections"
        case .disk: return "Storage & I/O"
        case .daemons: return "launchd services"
        case .cpu: return "Cores & processes"
        }
    }

    var systemImage: String {
        switch self {
        case .networking: return "network"
        case .disk: return "internaldrive"
        case .daemons: return "gearshape.2"
        case .cpu: return "cpu"
        }
    }

    var tint: Color {
        switch self {
        case .networking: return Color(red: 0.16, green: 0.62, blue: 0.94)
        case .disk: return Color(red: 0.94, green: 0.56, blue: 0.18)
        case .daemons: return Color(red: 0.62, green: 0.42, blue: 0.95)
        case .cpu: return Color(red: 0.20, green: 0.72, blue: 0.52)
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .networking: return "1"
        case .disk: return "2"
        case .daemons: return "3"
        case .cpu: return "4"
        }
    }

    static func fromCommandLine() -> AppSection? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--section"),
              flag + 1 < arguments.count else {
            return nil
        }
        let value = arguments[flag + 1].lowercased()
        if let section = AppSection(rawValue: value) { return section }
        switch value {
        case "0": return .networking
        case "1": return .disk
        case "2": return .daemons
        case "3": return .cpu
        default: return nil
        }
    }
}

protocol PillTabItem: CaseIterable, Identifiable, Hashable {
    var title: String { get }
    var systemImage: String { get }
    var tint: Color { get }
}

enum NetworkingTab: String, CaseIterable, Identifiable, Hashable, PillTabItem {
    case interfaces
    case connections
    case processes
    case filter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interfaces: return "Interfaces"
        case .connections: return "Connections"
        case .processes: return "Processes"
        case .filter: return "Filter"
        }
    }

    var systemImage: String {
        switch self {
        case .interfaces: return "network"
        case .connections: return "point.3.connected.trianglepath.dotted"
        case .processes: return "list.bullet"
        case .filter: return "shield.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .interfaces: return Color(red: 0.16, green: 0.62, blue: 0.94)
        case .connections: return Color(red: 0.20, green: 0.70, blue: 0.62)
        case .processes: return Color(red: 0.55, green: 0.45, blue: 0.92)
        case .filter: return Color(red: 0.86, green: 0.42, blue: 0.20)
        }
    }

    static func fromCommandLine() -> NetworkingTab? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--tab"),
              flag + 1 < arguments.count else {
            return nil
        }
        let value = arguments[flag + 1].lowercased()
        if let tab = NetworkingTab(rawValue: value) { return tab }
        switch value {
        case "0": return .interfaces
        case "1": return .connections
        case "2": return .processes
        case "3": return .filter
        default: return nil
        }
    }
}

enum DiskTab: String, CaseIterable, Identifiable, Hashable, PillTabItem {
    case volumes
    case analyzer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volumes: return "Volumes"
        case .analyzer: return "Analyzer"
        }
    }

    var systemImage: String {
        switch self {
        case .volumes: return "internaldrive"
        case .analyzer: return "chart.pie"
        }
    }

    var tint: Color {
        switch self {
        case .volumes: return Color(red: 0.94, green: 0.56, blue: 0.18)
        case .analyzer: return Color(red: 0.90, green: 0.42, blue: 0.25)
        }
    }

    static func fromCommandLine() -> DiskTab? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--disk-tab"),
              flag + 1 < arguments.count else {
            return nil
        }
        let value = arguments[flag + 1].lowercased()
        if let tab = DiskTab(rawValue: value) { return tab }
        switch value {
        case "0": return .volumes
        case "1": return .analyzer
        default: return nil
        }
    }
}

extension Notification.Name {
    static let kbSelectSection = Notification.Name("kancerbero.selectSection")
}
