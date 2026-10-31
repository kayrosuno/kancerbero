import Foundation

/// Finds the files an installed bundle leaves behind. AppCleaner scans the
/// whole `~/Library` and `/Library` trees (unlimited depth) and matches the last
/// path component against the bundle id (case-insensitive contains/prefix) or
/// the app name variants (case-sensitive). A matched directory is added as a
/// whole and its contents are not walked again.
public enum AppLeftoversCollector {
    public static func leftovers(for bundle: KBAppBundle,
                                 home: String = NSHomeDirectory()) -> [KBLeftover] {
        let bundleURL = URL(fileURLWithPath: bundle.path)
        let ids = Identifiers(
            bundleId: bundle.bundleIdentifier,
            names: candidateNames(for: bundle),
            groups: KBBundleSigning.applicationGroups(of: bundleURL)
        )
        var found: [String: KBLeftover] = [:]

        func add(_ url: URL, kind: KBLeftoverKind, selected: Bool,
                 reason: String) {
            let path = url.path
            guard path != bundle.path, found[path] == nil else { return }
            found[path] = KBLeftover(
                path: path,
                kind: kind,
                sizeBytes: KBAllocatedSize.allocatedSize(of: url),
                selectedByDefault: selected,
                requiresPrivilege: KBPathPolicy.requiresPrivilege(path, home: home),
                matchReason: reason
            )
        }

        let bundleIdLongEnough = (ids.bundleId?.count ?? 0) > 3
        let bundleIdVeryLong = (ids.bundleId?.count ?? 0) > 7

        for base in [home + "/Library", "/Library"] {
            scan("\(base)/Preferences", maxDepth: 1, ids: ids,
                 allowBundleIdPrefix: true) { url, reason in
                add(url, kind: .preferences, selected: true, reason: reason)
            }
            if bundleIdLongEnough {
                scan("\(base)/Preferences/ByHost", maxDepth: 1, ids: ids,
                     allowBundleIdPrefix: true) { url, reason in
                    add(url, kind: .byHost, selected: true, reason: reason)
                }
                scan("\(base)/SyncedPreferences", maxDepth: 1, ids: ids,
                     allowBundleIdPrefix: true) { url, reason in
                    add(url, kind: .syncedPreferences, selected: true, reason: reason)
                }
            }
            scan("\(base)/Application Support", maxDepth: 0, ids: ids, budget: 150_000) { url, reason in
                add(url, kind: .appSupport, selected: true, reason: reason)
            }
            scan("\(base)/Caches", maxDepth: 1, ids: ids) { url, reason in
                add(url, kind: .cache, selected: true, reason: reason)
            }
            scan("\(base)/Saved Application State", maxDepth: 1, ids: ids) { url, reason in
                add(url, kind: .savedState, selected: true, reason: reason)
            }
            scan("\(base)/LaunchAgents", maxDepth: 1, ids: ids) { url, reason in
                add(url, kind: .launchAgent, selected: true, reason: reason)
            }
            scan("\(base)/LaunchDaemons", maxDepth: 1, ids: ids) { url, reason in
                add(url, kind: .launchDaemon, selected: true, reason: reason)
            }
            scan("\(base)/Logs", maxDepth: 1, ids: ids) { url, reason in
                add(url, kind: .log, selected: true, reason: reason)
            }
            scan("\(base)/Safari/Extensions", maxDepth: 1, ids: ids) { url, reason in
                add(url, kind: .safariExtension, selected: true, reason: reason)
            }
            scan("\(base)/Services", maxDepth: 1, ids: ids) { url, reason in
                add(url, kind: .service, selected: true, reason: reason)
            }
            scan("\(base)/Developer", maxDepth: 0, ids: ids, budget: 100_000) { url, reason in
                add(url, kind: .other, selected: true, reason: reason)
            }
            if bundleIdVeryLong {
                scan("\(base)/Cookies", maxDepth: 1, ids: ids, bundleIdOnly: true) { url, reason in
                    add(url, kind: .cookie, selected: true, reason: reason)
                }
                scan("\(base)/HTTPStorages", maxDepth: 1, ids: ids, bundleIdOnly: true) { url, reason in
                    add(url, kind: .httpStorage, selected: true, reason: reason)
                }
                scan("\(base)/WebKit", maxDepth: 1, ids: ids, bundleIdOnly: true) { url, reason in
                    add(url, kind: .webKit, selected: true, reason: reason)
                }
            }
        }

        // Sandbox containers keep their bundle id (or a team prefix).
        for base in [home + "/Library", "/Library"] {
            scan("\(base)/Containers", maxDepth: 1, ids: ids) { url, reason in
                add(url, kind: .container, selected: true, reason: reason)
            }
            scan("\(base)/Application Scripts", maxDepth: 1, ids: ids,
                 acceptedIds: Set([ids.bundleId].compactMap { $0 } + ids.groups)) { url, reason in
                add(url, kind: .appScripts, selected: true, reason: reason)
            }
            if !ids.groups.isEmpty {
                scan("\(base)/Group Containers", maxDepth: 1, ids: ids,
                     acceptedIds: Set(ids.groups)) { url, reason in
                    add(url, kind: .groupContainer, selected: false, reason: reason)
                }
            }
        }

        scan("/Users/Shared", maxDepth: 1, ids: ids) { url, reason in
            add(url, kind: .shared, selected: true, reason: reason)
        }

        if bundleIdVeryLong, let bundleId = ids.bundleId {
            let recent = "\(home)/Library/Application Support/com.apple.sharedfilelist/"
                + "com.apple.LSSharedFileList.ApplicationRecentDocuments"
            scan(recent, maxDepth: 1, ids: ids,
                 acceptedIds: [normalizedId(bundleId)]) { url, reason in
                add(url, kind: .appSupport, selected: true, reason: reason)
            }
        }


        return found.values.sorted {
            if $0.kind.sortOrder != $1.kind.sortOrder {
                return $0.kind.sortOrder < $1.kind.sortOrder
            }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    // MARK: - Matching

    private struct Identifiers {
        let bundleId: String?
        let names: Set<String>
        let groups: [String]
    }

    private static let genericNames: Set<String> = [
        "helper", "updater", "resources", "framework", "agent",
        "service", "support", "uninstaller"
    ]

    private static func candidateNames(for bundle: KBAppBundle) -> Set<String> {
        var names = Set<String>()
        for raw in [bundle.name, bundle.displayName, bundle.executable].compactMap({ $0 }) {
            for candidate in [normalizedName(raw),
                              normalizedName(strippingTrailingDigits(raw))] {
                guard candidate.count >= 4, !genericNames.contains(candidate.lowercased()) else {
                    continue
                }
                names.insert(candidate)
            }
        }
        return names
    }

    /// Names keep their case: AppCleaner's regexes are case-sensitive, which is
    /// why lowercase helpers under ~/Library/Developer are not listed.
    private static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "")
    }

    private static func normalizedId(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "")
    }

    private static func strippingTrailingDigits(_ value: String) -> String {
        var result = value
        while let last = result.last, last.isNumber {
            result.removeLast()
        }
        return result
    }

    /// The last component without its extension, like AppCleaner's
    /// `stringByDeletingPathExtension`.
    private static func baseName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private static func match(_ url: URL, ids: Identifiers,
                              allowBundleIdPrefix: Bool,
                              bundleIdOnly: Bool,
                              acceptedIds: Set<String>?) -> String? {
        let component = url.lastPathComponent
        let base = baseName(url)

        if let acceptedIds {
            let lowerComponent = normalizedId(component)
            let lowerBase = normalizedId(base)
            for accepted in acceptedIds {
                let id = normalizedId(accepted)
                if !id.isEmpty,
                   lowerComponent == id || lowerBase == id
                       || lowerComponent.hasPrefix(id + ".") {
                    return "application group"
                }
            }
            return nil
        }

        if !bundleIdOnly {
            // AppCleaner builds a case-sensitive prefix regex from the app
            // name, so "Claude" also matches "Claude - send.workflow" and
            // "ClaudeAgentConfig".
            let candidates = [normalizedName(base),
                              normalizedName(strippingTrailingDigits(base))]
            if candidates.contains(where: { candidate in
                ids.names.contains(where: { candidate.hasPrefix($0) })
            }) {
                return "name"
            }
        }

        if let bundleId = ids.bundleId {
            let id = normalizedId(bundleId)
            if !id.isEmpty {
                let lowerComponent = normalizedId(component)
                let lowerBase = normalizedId(base)
                if lowerComponent == id || lowerBase == id
                    || lowerComponent.hasSuffix("." + id) {
                    return "bundle id"
                }
                if allowBundleIdPrefix, lowerComponent.hasPrefix(id + ".") {
                    return "bundle id prefix"
                }
            }
        }
        return nil
    }

    /// AppCleaner's default matcher: for bundle ids of 8+ characters any
    /// component containing the id matches; for 4+ a prefix is enough. Names
    /// are compared without their extension, case-sensitively.
    private static func defaultMatch(_ url: URL, ids: Identifiers) -> String? {
        let component = url.lastPathComponent
        let lower = normalizedId(component)
        if let bundleId = ids.bundleId {
            let id = normalizedId(bundleId)
            if !id.isEmpty {
                if id.count >= 8, lower.contains(id) {
                    return "bundle id"
                }
                if id.count >= 4, lower.hasPrefix(id) {
                    return "bundle id prefix"
                }
            }
        }
        let base = normalizedName(baseName(url))
        let candidates = [base, normalizedName(strippingTrailingDigits(base))]
        if candidates.contains(where: { candidate in
            ids.names.contains(where: { candidate.hasPrefix($0) })
        }) {
            return "name"
        }
        return nil
    }



    // MARK: - Walking

    private static func scan(_ directory: String, maxDepth: Int, ids: Identifiers,
                             allowBundleIdPrefix: Bool = false,
                             bundleIdOnly: Bool = false,
                             acceptedIds: Set<String>? = nil,
                             budget: Int = 250_000,
                             _ onMatch: (URL, String) -> Void) {
        let root = URL(fileURLWithPath: directory)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        var remaining = budget
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            remaining -= 1
            if remaining <= 0 { return }
            if visited % 512 == 0, Task.isCancelled { return }
            if maxDepth > 0, enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard let reason = match(
                url,
                ids: ids,
                allowBundleIdPrefix: allowBundleIdPrefix,
                bundleIdOnly: bundleIdOnly,
                acceptedIds: acceptedIds
            ) else {
                continue
            }
            onMatch(url, reason)
            if (try? url.resourceValues(forKeys: keys))?.isDirectory == true {
                enumerator.skipDescendants()
            }
        }
    }


}
