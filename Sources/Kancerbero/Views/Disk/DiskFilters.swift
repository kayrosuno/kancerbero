import Foundation

enum DiskVolumesFocus: String, CaseIterable, Identifiable, Sendable {
    case disks
    case volumes
    case capacity
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disks: return "Disks"
        case .volumes: return "Volumes"
        case .capacity: return "Capacity"
        case .free: return "Free"
        }
    }
}

enum DiskAnalyzerFocus: String, CaseIterable, Identifiable, Sendable {
    case scanned
    case files
    case folders
    case denied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanned: return "Scanned"
        case .files: return "Files"
        case .folders: return "Folders"
        case .denied: return "Denied"
        }
    }
}
