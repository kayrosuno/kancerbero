import AppKit
import SwiftUI
import KancerberoCore

/// Warm bone/ivory palette used by the Disk → Volumes treemap.
///
/// Each hierarchy level keeps a slightly darker bone tone while text and
/// strokes use a warm dark ink so the tiles stay readable.
enum DiskPalette {
    static let paper = Color(.sRGB, red: 0.969, green: 0.953,
                             blue: 0.918, opacity: 1)
    static let sand = Color(.sRGB, red: 0.910, green: 0.886,
                            blue: 0.843, opacity: 1)
    static let stone = Color(.sRGB, red: 0.851, green: 0.820,
                             blue: 0.765, opacity: 1)
    static let taupe = Color(.sRGB, red: 0.788, green: 0.749,
                             blue: 0.682, opacity: 1)
    static let ink = Color(.sRGB, red: 0.122, green: 0.161,
                           blue: 0.216, opacity: 1)
    static let textInk = Color(.sRGB, red: 0.196, green: 0.165,
                               blue: 0.125, opacity: 1)

    static let partitionFill = sand
    static let containerFill = stone
    static let volumeFill = taupe
    static let usedFill = Color(.sRGB, red: 0.871, green: 0.824,
                                blue: 0.749, opacity: 1)

    static let free = Color(.sRGB, red: 0.969, green: 0.953,
                            blue: 0.918, opacity: 1)
    static let residual = Color(.sRGB, red: 0.824, green: 0.788,
                                blue: 0.729, opacity: 1)
    static let unknown = Color(.sRGB, red: 0.929, green: 0.910,
                               blue: 0.871, opacity: 1)
    static let unallocated = Color(.sRGB, red: 0.867, green: 0.835,
                                   blue: 0.780, opacity: 1)

    /// Neutral greys for the volumes that are not selected: present but
    /// visually "off". Three shades keep adjacent tiles distinguishable.
    static let mutedVolume1 = Color(.sRGB, red: 0.788, green: 0.796,
                                    blue: 0.816, opacity: 1)
    static let mutedVolume2 = Color(.sRGB, red: 0.725, green: 0.737,
                                    blue: 0.761, opacity: 1)
    static let mutedVolume3 = Color(.sRGB, red: 0.663, green: 0.678,
                                    blue: 0.706, opacity: 1)

    static func mutedVolume(_ index: Int) -> Color {
        switch index % 3 {
        case 0: return mutedVolume1
        case 1: return mutedVolume2
        default: return mutedVolume3
        }
    }

    static func fill(level: Int) -> Color {
        switch level {
        case 0: return partitionFill
        case 1: return containerFill
        default: return volumeFill
        }
    }

    static func tint(for kind: KBDiskItemKind) -> Color {
        switch kind {
        case .physicalDisk:
            return Color(.sRGB, red: 0.310, green: 0.576,
                         blue: 0.800, opacity: 1)
        case .partition:
            return Color(.sRGB, red: 0.435, green: 0.663,
                         blue: 0.839, opacity: 1)
        case .apfsContainer:
            return Color(.sRGB, red: 0.357, green: 0.596,
                         blue: 0.780, opacity: 1)
        case .apfsVolume, .snapshot:
            return Color(.sRGB, red: 0.310, green: 0.576,
                         blue: 0.800, opacity: 1)
        }
    }

    static func relativeLuminance(_ color: Color) -> CGFloat {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else {
            return 1
        }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.03928
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(ns.redComponent)
            + 0.7152 * linear(ns.greenComponent)
            + 0.0722 * linear(ns.blueComponent)
    }

    static func isLight(_ fill: Color) -> Bool {
        relativeLuminance(fill) > 0.28
    }

    static func contentColor(on fill: Color) -> Color {
        isLight(fill) ? textInk : .white
    }

    static func bandColor(on fill: Color) -> Color {
        isLight(fill) ? textInk : sand
    }

    static func kindLabel(for kind: KBDiskItemKind) -> String {
        switch kind {
        case .physicalDisk: return "Disk"
        case .partition: return "Partition"
        case .apfsContainer: return "APFS container"
        case .apfsVolume: return "APFS volume"
        case .snapshot: return "Snapshot"
        }
    }
}
