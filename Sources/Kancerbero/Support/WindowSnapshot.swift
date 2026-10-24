import AppKit

enum WindowSnapshot {
    enum SnapshotError: Error, CustomStringConvertible {
        case noContentView
        case emptyBounds
        case noBitmap
        case noPNG

        var description: String {
            switch self {
            case .noContentView: return "window has no content view"
            case .emptyBounds: return "window content has zero size"
            case .noBitmap: return "could not create a bitmap representation"
            case .noPNG: return "could not encode the bitmap as PNG"
            }
        }
    }

    /// Captures the window's own view hierarchy. This does not use
    /// CGWindowListCreateImage or screencapture, so it needs no Screen
    /// Recording permission.
    @MainActor
    static func capture(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else {
            throw SnapshotError.noContentView
        }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            throw SnapshotError.emptyBounds
        }
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw SnapshotError.noBitmap
        }
        view.cacheDisplay(in: bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.noPNG
        }
        try data.write(to: url, options: .atomic)
    }
}
