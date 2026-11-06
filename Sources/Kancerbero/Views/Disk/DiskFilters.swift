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

/// Session-only widths for the Disk → Volumes tables. Stored in `DiskUIState`
/// so every disk table shares the same columns while the section is visible.
struct DiskVolumeColumnWidths: Equatable {
    var name: CGFloat = 150
    var disk: CGFloat = 96
    var type: CGFloat = 92
    var size: CGFloat = 54
    var used: CGFloat = 56
    var free: CGFloat = 56
    var mounted: CGFloat = 56
    /// The Mount column absorbs any width left over by the other columns.
    var mountMinimum: CGFloat = 64

    static let nameRange: ClosedRange<CGFloat> = 90...400
    static let diskRange: ClosedRange<CGFloat> = 70...150
    static let typeRange: ClosedRange<CGFloat> = 60...180
    static let sizeRange: ClosedRange<CGFloat> = 48...100
    static let usedRange: ClosedRange<CGFloat> = 48...110
    static let freeRange: ClosedRange<CGFloat> = 48...110
    static let mountedRange: ClosedRange<CGFloat> = 48...90
    static let mountMinimumRange: ClosedRange<CGFloat> = 56...400

    static func clamp(_ value: CGFloat,
                      to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
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
