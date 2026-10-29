import Foundation
import KancerberoCore

enum DaemonServiceType: String, CaseIterable, Identifiable, Sendable {
    case daemon
    case agent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daemon: return "Daemons"
        case .agent: return "Agents"
        }
    }

    var singularTitle: String {
        switch self {
        case .daemon: return "Daemon"
        case .agent: return "Agent"
        }
    }

    var systemImage: String {
        switch self {
        case .daemon: return "gearshape.2.fill"
        case .agent: return "person.crop.circle.fill"
        }
    }

    /// Daemons before agents, matching the deduplicator's default grouping.
    var sortRank: Int { self == .daemon ? 0 : 1 }
}

enum DaemonScope: String, CaseIterable, Identifiable, Sendable {
    case system
    case global
    case user
    case runtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .global: return "Global"
        case .user: return "User"
        case .runtime: return "Runtime"
        }
    }

    /// Declaration order, matching the chip order in the filter bar.
    var sortRank: Int {
        switch self {
        case .system: return 0
        case .global: return 1
        case .user: return 2
        case .runtime: return 3
        }
    }
}

enum DaemonOrigin: String, CaseIterable, Identifiable, Sendable {
    case apple
    case custom
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .custom: return "Custom"
        case .unknown: return "Unknown"
        }
    }
}

extension KBDaemonState {
    /// Card/chip order: Running, Stopped, Disabled, Not loaded.
    var sortRank: Int {
        switch self {
        case .running: return 0
        case .stopped: return 1
        case .disabled: return 2
        case .unloaded: return 3
        }
    }
}

extension KBDaemonService {
    private static let userAgentPrefix =
        (("~/Library/LaunchAgents") as NSString).expandingTildeInPath + "/"

    /// Directory-normalized plist path, so prefix checks work for both
    /// "/Library/LaunchDaemons" and full file paths inside it.
    private var normalizedPlistPath: String {
        guard !plistPath.isEmpty else { return "" }
        let expanded = (plistPath as NSString).expandingTildeInPath
        return expanded.hasSuffix("/") ? expanded : expanded + "/"
    }

    var serviceType: DaemonServiceType {
        domain == .system ? .daemon : .agent
    }

    var scope: DaemonScope {
        let path = normalizedPlistPath
        guard !path.isEmpty else { return .runtime }
        if path.hasPrefix("/System/Library/LaunchDaemons/")
            || path.hasPrefix("/System/Library/LaunchAgents/") {
            return .system
        }
        if path.hasPrefix("/Library/LaunchDaemons/")
            || path.hasPrefix("/Library/LaunchAgents/") {
            return .global
        }
        if path.hasPrefix(Self.userAgentPrefix) {
            return .user
        }
        return .runtime
    }

    var origin: DaemonOrigin {
        let path = normalizedPlistPath
        guard !path.isEmpty else { return .unknown }
        if path.hasPrefix("/System/Library/") || label.hasPrefix("com.apple.") {
            return .apple
        }
        return .custom
    }

    func matchesSearch(_ term: String) -> Bool {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return label.localizedCaseInsensitiveContains(needle)
            || program.localizedCaseInsensitiveContains(needle)
            || arguments.localizedCaseInsensitiveContains(needle)
            || plistPath.localizedCaseInsensitiveContains(needle)
    }
}

struct DaemonListEntry: Identifiable, Hashable {
    let service: KBDaemonService
    let domains: [KBDaemonDomain]

    /// Stable across refreshes: the canonical domain may change after a
    /// start/stop, but the label (and therefore this id) does not.
    var id: String {
        service.domain == .system ? "system:\(service.label)" : "local:\(service.label)"
    }
}

extension DaemonListEntry {
    /// Non-optional sort keys keep rows without a value at the end instead of
    /// producing nil comparators (same approach as `CPUProcessRow`).
    private static let missingSortValue = "\u{10FFFF}"

    var labelSortValue: String { service.label.lowercased() }
    var typeSortRank: Int { service.serviceType.sortRank }
    var scopeSortRank: Int { service.scope.sortRank }
    var pidSortValue: Int32 { service.pid ?? .max }
    var stateSortRank: Int { service.state.sortRank }
    var programSortValue: String {
        service.program.isEmpty ? Self.missingSortValue : service.program.lowercased()
    }
    var plistSortValue: String {
        service.plistPath.isEmpty
            ? Self.missingSortValue
            : (service.plistPath as NSString).lastPathComponent.lowercased()
    }
}

enum DaemonDeduplicator {
    static func entries(system: [KBDaemonService],
                        local: [KBDaemonService]) -> [DaemonListEntry] {
        var entries: [DaemonListEntry] = system.map {
            DaemonListEntry(service: $0, domains: [.system])
        }

        let grouped = Dictionary(grouping: local, by: \.label)
        for candidates in grouped.values {
            guard let canonical = canonical(candidates) else { continue }
            let domains = KBDaemonDomain.allCases.filter { domain in
                candidates.contains { $0.domain == domain }
            }
            entries.append(DaemonListEntry(service: canonical, domains: domains))
        }

        return entries.sorted { lhs, rhs in
            if lhs.service.serviceType != rhs.service.serviceType {
                return lhs.service.serviceType == .daemon
            }
            let byLabel = lhs.service.label
                .localizedCaseInsensitiveCompare(rhs.service.label)
            if byLabel != .orderedSame {
                return byLabel == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    private static func canonical(_ candidates: [KBDaemonService]) -> KBDaemonService? {
        let gui = candidates.first { $0.domain == .gui }
        let user = candidates.first { $0.domain == .user }
        if let gui, gui.isLoaded { return gui }
        if let user, user.isLoaded { return user }
        return gui ?? user ?? candidates.first
    }
}

struct DaemonFilter: Equatable {
    static let allTypes = Set(DaemonServiceType.allCases)
    static let allScopes = Set(DaemonScope.allCases)
    static let allOrigins = Set(DaemonOrigin.allCases)
    static let allStates = Set(KBDaemonState.allCases)

    var search = ""
    var types: Set<DaemonServiceType> = Set(DaemonServiceType.allCases)
    var scopes: Set<DaemonScope> = Set(DaemonScope.allCases)
    var origins: Set<DaemonOrigin> = Set(DaemonOrigin.allCases)
    var states: Set<KBDaemonState> = Set(KBDaemonState.allCases)

    /// Every group is a set of pressed values: a service matches only the
    /// facets that are on, and an empty group matches nothing.
    var hasFacets: Bool {
        types != Self.allTypes
            || scopes != Self.allScopes
            || origins != Self.allOrigins
            || states != Self.allStates
    }

    var hasSearch: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matches(_ service: KBDaemonService) -> Bool {
        guard types.contains(service.serviceType),
              scopes.contains(service.scope),
              origins.contains(service.origin),
              states.contains(service.state) else { return false }
        return service.matchesSearch(search)
    }

    /// Cards count over every state, so each number matches the rows shown
    /// after pressing it, even when the state group is partly or fully off.
    func clearingState() -> DaemonFilter {
        var copy = self
        copy.states = Self.allStates
        return copy
    }
}
