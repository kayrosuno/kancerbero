import AppKit
import SwiftUI
import KancerberoCore

/// Warm-neutral palette used by the Disk → Volumes graphs.
///
/// The five hex values form a light→dark ramp. Charts map one family per
/// hierarchy level, while text/strokes pick a contrasting tone from the
/// fill's luminance so the same palette works on every slice.
enum DiskPalette {
    static let paper = Color(.sRGB, red: 0.980, green: 0.965,
                             blue: 0.949, opacity: 1)
    static let sand = Color(.sRGB, red: 0.914, green: 0.863,
                            blue: 0.812, opacity: 1)
    static let stone = Color(.sRGB, red: 0.831, green: 0.757,
                             blue: 0.694, opacity: 1)
    static let taupe = Color(.sRGB, red: 0.722, green: 0.635,
                             blue: 0.576, opacity: 1)
    static let ink = Color(.sRGB, red: 0.494, green: 0.416,
                           blue: 0.376, opacity: 1)
    /// Darker warm ink for text and strokes over the lighter fills; `ink`
    /// itself does not reach accessible contrast on stone/taupe.
    static let textInk = Color(.sRGB, red: 0.227, green: 0.188,
                               blue: 0.169, opacity: 1)

    static let partitionFills = [sand, paper]
    static let containerFills = [stone, sand]
    static let volumeFills = [taupe, ink]

    static let free = sand
    static let residual = stone
    static let unknown = paper
    static let unallocated = stone

    static func fill(level: Int, index: Int) -> Color {
        let fills: [Color]
        switch level {
        case 0: fills = partitionFills
        case 1: fills = containerFills
        default: fills = volumeFills
        }
        return fills[index % fills.count]
    }

    static func tint(for kind: KBDiskItemKind) -> Color {
        switch kind {
        case .physicalDisk: return ink
        case .partition: return stone
        case .apfsContainer: return taupe
        case .apfsVolume, .snapshot: return ink
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
        relativeLuminance(fill) > 0.20
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
