import AppKit
import SwiftUI
import KancerberoCore

/// Light pastel-blue palette used by the Disk → Volumes graphs.
///
/// Each hierarchy level keeps a slightly different blue while text and
/// strokes use a dark ink so the tiles stay readable on the app's light
/// materials.
enum DiskPalette {
    static let paper = Color(.sRGB, red: 0.973, green: 0.965,
                             blue: 0.980, opacity: 1)
    static let sand = Color(.sRGB, red: 0.851, green: 0.910,
                            blue: 0.969, opacity: 1)
    static let stone = Color(.sRGB, red: 0.749, green: 0.847,
                             blue: 0.941, opacity: 1)
    static let taupe = Color(.sRGB, red: 0.651, green: 0.796,
                             blue: 0.910, opacity: 1)
    static let ink = Color(.sRGB, red: 0.122, green: 0.161,
                           blue: 0.216, opacity: 1)
    static let textInk = ink

    static let partitionFill = sand
    static let containerFill = stone
    static let volumeFill = taupe
    static let usedFill = Color(.sRGB, red: 0.773, green: 0.863,
                                blue: 0.949, opacity: 1)

    static let free = Color(.sRGB, red: 0.906, green: 0.949,
                            blue: 0.984, opacity: 1)
    static let residual = Color(.sRGB, red: 0.788, green: 0.851,
                                blue: 0.925, opacity: 1)
    static let unknown = Color(.sRGB, red: 0.922, green: 0.949,
                               blue: 0.976, opacity: 1)
    static let unallocated = Color(.sRGB, red: 0.843, green: 0.882,
                                   blue: 0.925, opacity: 1)

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
