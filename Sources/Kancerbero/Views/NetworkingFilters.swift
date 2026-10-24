import Foundation
import KancerberoCore

enum NetworkingFocus: String, CaseIterable, Identifiable, Sendable {
    case download
    case upload
    case connections
    case processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: return "Download"
        case .upload: return "Upload"
        case .connections: return "Connections"
        case .processes: return "Processes"
        }
    }
}

@MainActor
extension AppModel {
    func filteredInterfaces(_ focus: NetworkingFocus?) -> [KBInterfaceInfo] {
        guard let focus else { return interfaces }
        let sourcedNames = Set(sources.map(\.interfaceName).filter { !$0.isEmpty })
        switch focus {
        case .download:
            return interfaces.filter {
                !$0.isLoopback && $0.kind != .tunnel
                    && (interfaceRates[$0.id]?.rxBytesPerSecond ?? 0) > 0
            }
        case .upload:
            return interfaces.filter {
                !$0.isLoopback && $0.kind != .tunnel
                    && (interfaceRates[$0.id]?.txBytesPerSecond ?? 0) > 0
            }
        case .connections, .processes:
            return interfaces.filter { sourcedNames.contains($0.name) }
        }
    }

    func filteredSources(_ focus: NetworkingFocus?) -> [KBNStatSource] {
        guard let focus else { return sources }
        switch focus {
        case .download:
            return sources.filter { $0.rates.rxBytesPerSecond > 0 }
        case .upload:
            return sources.filter { $0.rates.txBytesPerSecond > 0 }
        case .connections:
            return sources.filter { ($0.counters.rxBytes &+ $0.counters.txBytes) > 0 }
        case .processes:
            return sources.filter { $0.pid > 0 }
        }
    }

    func filteredProcesses(_ focus: NetworkingFocus?) -> [KBProcessInfo] {
        guard let focus else { return processes }
        switch focus {
        case .download:
            let pids = Set(sources
                .filter { $0.rates.rxBytesPerSecond > 0 }
                .map(\.pid))
            return processes.filter { pids.contains($0.pid) }
        case .upload:
            let pids = Set(sources
                .filter { $0.rates.txBytesPerSecond > 0 }
                .map(\.pid))
            return processes.filter { pids.contains($0.pid) }
        case .connections:
            let pids = Set(sources.map(\.pid))
            return processes.filter { pids.contains($0.pid) }
        case .processes:
            return processes.filter { !$0.path.isEmpty }
        }
    }
}
