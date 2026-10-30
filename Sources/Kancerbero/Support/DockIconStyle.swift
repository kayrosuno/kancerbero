import Foundation

/// What the Dock icon shows. The first five mirror Activity Monitor's
/// View → Dock Icon menu; the rest expose Kancerbero's other live metrics.
enum DockIconStyle: String, CaseIterable, Identifiable, Equatable {
    case applicationIcon
    case cpuUsage
    case cpuHistory
    case networkUsage
    case diskActivity
    case memoryUsage
    case memoryPressure
    case gpuUsage
    case energyUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applicationIcon: return "Show Application Icon"
        case .cpuUsage: return "Show CPU Usage"
        case .cpuHistory: return "Show CPU History"
        case .networkUsage: return "Show Network Usage"
        case .diskActivity: return "Show Disk Activity"
        case .memoryUsage: return "Show Memory Usage"
        case .memoryPressure: return "Show Memory Pressure"
        case .gpuUsage: return "Show GPU Usage"
        case .energyUsage: return "Show Energy Usage"
        }
    }

    var shortLabel: String {
        switch self {
        case .applicationIcon: return ""
        case .cpuUsage, .cpuHistory: return "CPU"
        case .networkUsage: return "NET"
        case .diskActivity: return "DISK"
        case .memoryUsage, .memoryPressure: return "MEM"
        case .gpuUsage: return "GPU"
        case .energyUsage: return "PWR"
        }
    }
}
