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
    var name: CGFloat = 132
    var disk: CGFloat = 70
    var type: CGFloat = 72
    var size: CGFloat = 46
    var used: CGFloat = 46
    var free: CGFloat = 46
    var mounted: CGFloat = 50
    /// The Mount column absorbs any width left over by the other columns.
    var mountMinimum: CGFloat = 40

    static let nameRange: ClosedRange<CGFloat> = 90...400
    static let diskRange: ClosedRange<CGFloat> = 62...150
    static let typeRange: ClosedRange<CGFloat> = 58...180
    static let sizeRange: ClosedRange<CGFloat> = 44...100
    static let usedRange: ClosedRange<CGFloat> = 44...110
    static let freeRange: ClosedRange<CGFloat> = 44...110
    static let mountedRange: ClosedRange<CGFloat> = 50...90
    static let mountMinimumRange: ClosedRange<CGFloat> = 40...400

    static func clamp(_ value: CGFloat,
                      to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Layout constants and clamping for the two-panel Volumes layout.
enum DiskVolumesSplit {
    static let dividerWidth: CGFloat = 10
    static let treeMinimumWidth: CGFloat = 300
    static let detailsMinimumWidth: CGFloat = 360
    static let defaultFraction: CGFloat = 0.5

    static func clampedFraction(_ fraction: CGFloat,
                                availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0, fraction.isFinite else {
            return defaultFraction
        }
        let lower = treeMinimumWidth / availableWidth
        let upper = 1 - detailsMinimumWidth / availableWidth
        guard lower < upper else { return defaultFraction }
        return min(max(fraction, lower), upper)
    }
}

/// Layout constants and clamping for the Analyzer's two right-hand tables.
enum DiskAnalyzerSplit {
    /// Height of the horizontal divider row; the 1 pt line is centered in it
    /// and it replaces the previous 12 pt spacing between the two cards.
    static let dividerHeight: CGFloat = 12
    static let childrenMinimumHeight: CGFloat = 160
    static let largestMinimumHeight: CGFloat = 110
    static let defaultLargestHeight: CGFloat = 190
    static let collapsedLargestHeight: CGFloat = 80

    static func clampedLargestHeight(_ height: CGFloat,
                                     availableHeight: CGFloat) -> CGFloat {
        guard availableHeight > 0 else { return 0 }
        let requested = height.isFinite ? height : defaultLargestHeight
        let maximum = availableHeight - childrenMinimumHeight

        // Too short for both minimums: keep a usable Largest files card (80 pt
        // floor or half the space) and give the rest to Contents.
        if maximum < largestMinimumHeight {
            let floor = min(collapsedLargestHeight, availableHeight * 0.5)
            return min(max(requested, floor), max(floor, maximum))
        }
        return min(max(requested, largestMinimumHeight), maximum)
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
