import Foundation

enum DiskVolumesFocus: String, CaseIterable, Identifiable, Sendable {
    case disks
    case containers
    case volumes
    case capacity
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disks: return "Disks"
        case .containers: return "Containers"
        case .volumes: return "Volumes"
        case .capacity: return "Capacity"
        case .free: return "Free"
        }
    }
}

/// Detail card that can be maximized in Disk → Volumes.
enum DiskVolumesPanel: String, CaseIterable, Identifiable, Sendable {
    case tree
    case details

    var id: String { rawValue }
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
