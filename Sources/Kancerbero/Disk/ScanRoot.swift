import Foundation

#if APP_STORE

enum ScanRootError: LocalizedError {
    case accessDenied(String)
    case missingBookmark
    case staleBookmark

    var errorDescription: String? {
        switch self {
        case .accessDenied(let path):
            return "Kancerbero cannot read \(path). Choose the folder again."
        case .missingBookmark:
            return "Choose a folder to scan. The Mac App Store version can only read folders you select."
        case .staleBookmark:
            return "The saved folder is no longer available. Choose it again."
        }
    }
}

/// Owns a security-scoped URL for the lifetime of one scan. The scope is
/// started before the detached scan and stopped when the object is released,
/// which happens after the scan task returns.
final class ScanRoot: @unchecked Sendable {
    let path: String
    private let scopedURL: URL?
    private let accessStarted: Bool

    init(url: URL) throws {
        let standardized = url.standardizedFileURL
        guard standardized.startAccessingSecurityScopedResource() else {
            throw ScanRootError.accessDenied(standardized.path)
        }
        self.path = standardized.path
        self.scopedURL = standardized
        self.accessStarted = true
    }

    deinit {
        if accessStarted {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
    }

    var bookmarkData: Data {
        get throws {
            guard let scopedURL else { throw ScanRootError.accessDenied(path) }
            return try scopedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil)
        }
    }

    static func fromBookmark(_ data: Data) throws -> (root: ScanRoot, refreshed: Data?) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data,
                          options: .withSecurityScope,
                          relativeTo: nil,
                          bookmarkDataIsStale: &stale)
        let root = try ScanRoot(url: url)
        return (root, stale ? try? root.bookmarkData : nil)
    }
}

#else

/// Developer ID builds keep scanning arbitrary paths; no sandbox scope is
/// involved.
final class ScanRoot: @unchecked Sendable {
    let path: String

    init(path: String) {
        self.path = (path as NSString).expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#endif
