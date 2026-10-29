import SwiftUI

/// Full-width filter bar above the Networking table card. Hosts the multiselect
/// checkbox groups for the active sub-tab; Interfaces and Filter have none.
struct NetworkingFilterBar: View {
    let tab: NetworkingTab
    @Environment(UIState.self) private var ui

    var body: some View {
        switch tab {
        case .connections: connectionsFilters
        case .processes: processFilters
        case .interfaces, .filter: EmptyView()
        }
    }

    private var connectionsFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ipGroup
                transportGroup
                stateGroup
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    ipGroup
                    transportGroup
                }
                stateGroup
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var processFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                processIPGroup
                processProtocolGroup
                processSocketGroup
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    processIPGroup
                    processProtocolGroup
                }
                processSocketGroup
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ipGroup: some View {
        CheckboxFilterGroup("IP",
                            selection: ipVersions,
                            optionTitle: { $0.title })
    }

    private var transportGroup: some View {
        CheckboxFilterGroup("Transport",
                            selection: transports,
                            optionTitle: { $0.title })
    }

    private var stateGroup: some View {
        CheckboxFilterGroup("State",
                            selection: connectionStates,
                            options: [.established, .listening, .connecting, .closing, .other],
                            optionTitle: { $0.title },
                            optionHelp: { $0.checkboxHelp })
    }

    private var processIPGroup: some View {
        CheckboxFilterGroup("IP",
                            selection: processIPVersions,
                            optionTitle: { $0.title })
    }

    private var processProtocolGroup: some View {
        CheckboxFilterGroup("Protocols",
                            selection: processProtocolKinds,
                            options: [.tcp, .udp, .raw, .unix, .other],
                            optionTitle: { $0.title })
    }

    private var processSocketGroup: some View {
        CheckboxFilterGroup("Socket type",
                            selection: processSocketTypes,
                            options: [.stream, .dgram, .raw, .seqpacket, .other],
                            optionTitle: { $0.title },
                            optionHelp: { $0.checkboxHelp })
    }

    private var ipVersions: Binding<Set<NetworkingIPVersion>> {
        Binding(
            get: { ui.networking.ipVersions },
            set: { ui.networking.ipVersions = $0 }
        )
    }

    private var transports: Binding<Set<NetworkingTransport>> {
        Binding(
            get: { ui.networking.transports },
            set: { ui.networking.transports = $0 }
        )
    }

    private var connectionStates: Binding<Set<NetworkingConnectionState>> {
        Binding(
            get: { ui.networking.connectionStates },
            set: { ui.networking.connectionStates = $0 }
        )
    }

    private var processIPVersions: Binding<Set<NetworkingIPVersion>> {
        Binding(
            get: { ui.networking.processIPVersions },
            set: { ui.networking.processIPVersions = $0 }
        )
    }

    private var processProtocolKinds: Binding<Set<ProcessProtocolKind>> {
        Binding(
            get: { ui.networking.processProtocolKinds },
            set: { ui.networking.processProtocolKinds = $0 }
        )
    }

    private var processSocketTypes: Binding<Set<ProcessSocketType>> {
        Binding(
            get: { ui.networking.processSocketTypes },
            set: { ui.networking.processSocketTypes = $0 }
        )
    }
}
