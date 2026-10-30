import Foundation

/// Finds the files an installed bundle leaves behind, following the groups
/// AppCleaner searches: preferences, application support, caches, containers,
/// saved state, launch items and logs. Matching is exact on the normalized
/// last path component (or the bundle id); a matched directory is added as a
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
            scan("\(base)/Application Support", maxDepth: 2, ids: ids,
                 allowNamePrefix: true) { url, reason in
                add(url, kind: .appSupport, selected: true, reason: reason)
            }
            scan("\(base)/Caches", maxDepth: 1, ids: ids,
                 allowNamePrefix: true) { url, reason in
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
                 acceptedIds: [normalized(bundleId)]) { url, reason in
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
            for candidate in [normalized(raw), normalized(strippingTrailingDigits(raw))] {
                guard candidate.count >= 4, !genericNames.contains(candidate) else {
                    continue
                }
                names.insert(candidate)
            }
        }
        return names
    }

    private static func normalized(_ value: String) -> String {
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

    private static let knownExtensions: Set<String> = [
        "plist", "savedstate", "wdgt", "appex", "bundle", "prefpane",
        "qlgenerator", "mdimporter", "saver", "plugin"
    ]

    private static func baseName(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if knownExtensions.contains(ext) {
            return url.deletingPathExtension().lastPathComponent
        }
        return url.lastPathComponent
    }

    private static let helperSuffixes = ["helper", "updater", "shipit", "agent", "loginhelper"]

    private static func match(_ url: URL, ids: Identifiers,
                              allowNamePrefix: Bool,
                              allowBundleIdPrefix: Bool,
                              bundleIdOnly: Bool,
                              acceptedIds: Set<String>?) -> String? {
        let component = normalized(url.lastPathComponent)
        let base = normalized(baseName(url))

        if let acceptedIds {
            for accepted in acceptedIds {
                let id = normalized(accepted)
                if !id.isEmpty,
                   component == id || base == id || component.hasPrefix(id + ".") {
                    return "application group"
                }
            }
            return nil
        }

        if !bundleIdOnly {
            let candidates = [component, base, normalized(strippingTrailingDigits(base))]
            for name in ids.names where candidates.contains(name) {
                return "name"
            }
            if allowNamePrefix {
                for name in ids.names {
                    guard component.hasPrefix(name) else { continue }
                    let rest = component.dropFirst(name.count)
                    let tail = rest.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
                    let lower = tail.lowercased()
                    if helperSuffixes.contains(where: { lower.hasPrefix($0) }) {
                        return "name helper"
                    }
                }
            }
        }

        if let bundleId = ids.bundleId {
            let id = normalized(bundleId)
            if !id.isEmpty {
                if component == id || base == id || component.hasSuffix("." + id) {
                    return "bundle id"
                }
                if allowBundleIdPrefix, component.hasPrefix(id + ".") {
                    return "bundle id prefix"
                }
            }
        }
        return nil
    }

    // MARK: - Walking

    private static func scan(_ directory: String, maxDepth: Int, ids: Identifiers,
                             allowNamePrefix: Bool = false,
                             allowBundleIdPrefix: Bool = false,
                             bundleIdOnly: Bool = false,
                             acceptedIds: Set<String>? = nil,
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

        for case let url as URL in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard let reason = match(
                url,
                ids: ids,
                allowNamePrefix: allowNamePrefix,
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
