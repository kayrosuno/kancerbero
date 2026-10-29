import Foundation
import Observation
import KancerberoCore
import KancerberoFilterContract

/// Session-only UI state shared by the section views. Views are destroyed when
/// the selected section or sub-tab changes, so anything that must look the same
/// when the user comes back lives here instead of in a local `@State`.
@MainActor
@Observable
final class UIState {
    var networking = NetworkingUIState()
    var daemons = DaemonsUIState()
    var disk = DiskUIState()
    var cpu = CPUUIState()
    var filter = FilterUIState()

    init(arguments: [String] = CommandLine.arguments) {
        if let focus = Self.value(for: "--networking-focus", in: arguments)
            .flatMap({ NetworkingFocus(rawValue: $0.lowercased()) }) {
            networking.focus = focus
        }
        if let raw = Self.value(for: "--networking-transport", in: arguments) {
            networking.transport = NetworkingTransport(cliValue: raw)
        }
        if let raw = Self.value(for: "--networking-ip", in: arguments) {
            networking.ipVersion = NetworkingIPVersion(cliValue: raw)
        }
        networking.connectionState = Self.value(for: "--networking-state", in: arguments)
            .flatMap { NetworkingConnectionState(cliValue: $0) }
        networking.processSearch = Self.value(for: "--networking-search", in: arguments) ?? ""

        if let raw = Self.value(for: "--daemon-type", in: arguments) {
            var selected = Set<DaemonServiceType>()
            var includesAll = false
            for token in raw.lowercased().split(separator: ",") {
                switch String(token).trimmingCharacters(in: .whitespacesAndNewlines) {
                case "all": includesAll = true
                case "agent", "agents": selected.insert(.agent)
                case "daemon", "daemons": selected.insert(.daemon)
                default: break
                }
            }
            if includesAll {
                daemons.types = DaemonFilter.allTypes
            } else if !selected.isEmpty {
                daemons.types = selected
            }
        } else if let raw = Self.value(for: "--daemon-domain", in: arguments),
                  let domain = KBDaemonDomain(rawValue: raw.lowercased()) {
            daemons.types = domain == .system ? [.daemon] : [.agent]
        }

        if let scopes = Self.valueSet(for: "--daemon-scope", in: arguments,
                                      as: DaemonScope.self) {
            daemons.scopes = scopes
        }
        if let origins = Self.valueSet(for: "--daemon-origin", in: arguments,
                                       as: DaemonOrigin.self) {
            daemons.origins = origins
        }
        if let states = Self.valueSet(for: "--daemon-state", in: arguments,
                                      as: KBDaemonState.self) {
            daemons.states = states
        }
        daemons.pendingSelectionLabel = Self.value(for: "--daemon-selected",
                                                   in: arguments)

        disk.volumesFocus = Self.value(for: "--volumes-focus", in: arguments)
            .flatMap { DiskVolumesFocus(rawValue: $0.lowercased()) }
        disk.analyzerFocus = Self.value(for: "--analyzer-focus", in: arguments)
            .flatMap { DiskAnalyzerFocus(rawValue: $0.lowercased()) } ?? .scanned

        cpu.search = Self.value(for: "--cpu-search", in: arguments) ?? ""
        cpu.pendingSelectionPID = Self.value(for: "--cpu-selected", in: arguments)
            .flatMap(Int32.init)
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Parses a comma-separated list of raw values (e.g. `system,user`).
    /// Unknown values are ignored; an entirely invalid list means "no override".
    private static func valueSet<T: RawRepresentable & Hashable>(
        for flag: String, in arguments: [String], as type: T.Type
    ) -> Set<T>? where T.RawValue == String {
        guard let raw = value(for: flag, in: arguments) else { return nil }
        let parsed = raw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .compactMap { T(rawValue: $0) }
        return parsed.isEmpty ? nil : Set(parsed)
    }
}

struct NetworkingUIState: Equatable {
    var focus: NetworkingFocus?
    var transport: NetworkingTransport?
    var ipVersion: NetworkingIPVersion?
    var connectionState: NetworkingConnectionState?
    var processSearch = ""
    var selectedConnection: String?
    var selectedProcess: KBProcessKey?
    var connectionSortOrder: [KeyPathComparator<KBNStatSource>] = []
    var processSortOrder: [KeyPathComparator<ProcessInventoryRow>] = []
}

struct DaemonsUIState: Equatable {
    var search = ""
    var types: Set<DaemonServiceType> = DaemonFilter.allTypes
    var scopes: Set<DaemonScope> = DaemonFilter.allScopes
    var origins: Set<DaemonOrigin> = DaemonFilter.allOrigins
    var states: Set<KBDaemonState> = DaemonFilter.allStates
    /// Empty keeps the deduplicator order; header clicks fill this in.
    var sortOrder: [KeyPathComparator<DaemonListEntry>] = []
    var selection: String?
    /// `--daemon-selected`, applied once on the first refresh with entries.
    var pendingSelectionLabel: String?
}

struct DiskUIState: Equatable {
    var volumesFocus: DiskVolumesFocus?
    var expanded: Set<String> = []
    var didExpandVolumesOnce = false
    var analyzerFocus: DiskAnalyzerFocus = .scanned
    /// nil means "use DiskModel.scanRootPath".
    var analyzerPathDraft: String?
}

struct CPUUIState: Equatable {
    var search = ""
    var selectedProcess: KBProcessKey?
    var processSortOrder: [KeyPathComparator<CPUProcessRow>] = [
        KeyPathComparator(\CPUProcessRow.cpuSortValue, order: .reverse)
    ]
    /// `--cpu-selected`, applied once when the row appears.
    var pendingSelectionPID: Int32?
}

struct FilterUIState {
    var search = ""
    var selectedFlow: String?
    var sortOrder: [KeyPathComparator<FlowRecord>] = [
        KeyPathComparator(\.startedAt, order: .reverse)
    ]
}
