import Foundation
import Observation
import KancerberoCore

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

        if let raw = Self.value(for: "--daemon-type", in: arguments) {
            switch raw.lowercased() {
            case "all": daemons.type = .all
            case "agent", "agents": daemons.type = .agents
            case "daemon", "daemons": daemons.type = .daemons
            default: break
            }
        } else if let raw = Self.value(for: "--daemon-domain", in: arguments),
                  let domain = KBDaemonDomain(rawValue: raw.lowercased()) {
            daemons.type = domain == .system ? .daemons : .agents
        }

        daemons.scope = Self.value(for: "--daemon-scope", in: arguments)
            .flatMap { DaemonScope(rawValue: $0.lowercased()) }
        daemons.origin = Self.value(for: "--daemon-origin", in: arguments)
            .flatMap { DaemonOrigin(rawValue: $0.lowercased()) }
        daemons.state = Self.value(for: "--daemon-state", in: arguments)
            .flatMap { KBDaemonState(rawValue: $0.lowercased()) }
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
}

struct NetworkingUIState: Equatable {
    var focus: NetworkingFocus?
    var transport: NetworkingTransport?
    var ipVersion: NetworkingIPVersion?
    var selectedConnection: String?
    var selectedProcess: KBProcessKey?
    var connectionSortOrder: [KeyPathComparator<KBNStatSource>] = []
    var processSortOrder: [KeyPathComparator<ProcessInventoryRow>] = []
}

struct DaemonsUIState: Equatable {
    var search = ""
    var type: DaemonTypeFilter = .all
    var scope: DaemonScope?
    var origin: DaemonOrigin?
    var state: KBDaemonState?
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
