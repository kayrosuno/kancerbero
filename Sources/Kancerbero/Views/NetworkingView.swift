import SwiftUI
import KancerberoCore
import KancerberoFilterContract

struct NetworkingView: View {
    @Binding var tab: NetworkingTab
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(FilterModel.self) private var filterModel
    @AppStorage(KBPreferences.tabAnimationsKey)
    private var tabAnimations = KBPreferences.tabAnimationsDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pillAnimation: Animation? {
        KBPreferences.tabAnimation(stored: tabAnimations,
                                   reduceMotion: reduceMotion,
                                   duration: 0.28)
    }

    private var tabTransition: AnyTransition {
        KBPreferences.enabled(stored: tabAnimations, reduceMotion: reduceMotion)
            ? .opacity
            : .identity
    }

    var body: some View {
        let rates = model.systemRates
        let protocolFilter = ui.networking.protocolFilter
        let connectionStates = tab == .connections ? ui.networking.connectionStates
                                                   : NetworkingConnectionState.all
        let connectionSearch = tab == .connections ? ui.networking.connectionSearch : ""
        let processSearch = tab == .processes ? ui.networking.processSearch : ""
        let processIPs = tab == .processes ? ui.networking.processIPVersions
                                           : NetworkingIPVersion.all
        let processKinds = tab == .processes ? ui.networking.processProtocolKinds
                                             : ProcessProtocolKind.all
        let processSockets = tab == .processes ? ui.networking.processSocketTypes
                                               : ProcessSocketType.all
        let activityConnections = model.filteredSources(nil, matching: protocolFilter,
                                                        states: connectionStates,
                                                        search: connectionSearch).count
        let activityProcesses = model.filteredProcessRows(nil,
                                                          ipVersions: processIPs,
                                                          protocolKinds: processKinds,
                                                          socketTypes: processSockets,
                                                          search: processSearch).count
        let ipOnly = NetworkingProtocolFilter(ipVersions: ui.networking.ipVersions)
        let protocolCounts = Dictionary(
            grouping: model.sources.filter(ipOnly.matches),
            by: \.protocolBucket
        ).mapValues(\.count)

        let matchingInterfaces = model.filteredInterfaces(ui.networking.focus)
        let matchingSources = model.filteredSources(ui.networking.focus,
                                                    matching: protocolFilter,
                                                    states: connectionStates,
                                                    search: connectionSearch)
        let matchingProcesses = model.filteredProcessRows(ui.networking.focus,
                                                          ipVersions: processIPs,
                                                          protocolKinds: processKinds,
                                                          socketTypes: processSockets,
                                                          search: processSearch)

        VStack(spacing: 14) {
            CollapsibleSectionHeader(
                section: .networking,
                title: "Networking",
                subtitle: "Live traffic, sockets and process inventory"
            )

            if !ui.cardsCollapsed(for: .networking) {
                HStack(alignment: .top, spacing: KBTheme.summaryGridSpacing) {
                    TrafficCard(
                        downloadBytesPerSecond: rates.rxBytesPerSecond,
                        uploadBytesPerSecond: rates.txBytesPerSecond,
                        downloadHistory: model.rxHistory,
                        uploadHistory: model.txHistory,
                        sampleDates: model.sampleDates,
                        focus: ui.networking.focus,
                        sampleInterval: model.interval,
                        onToggle: toggleFocus
                    )
                    .frame(minWidth: 400, maxWidth: .infinity)

                    VStack(spacing: KBTheme.summaryGridSpacing) {
                        ActivityCard(
                            connectionsCount: activityConnections,
                            processesCount: activityProcesses,
                            connectionsFiltered: protocolFilter.isActive
                                || connectionStates != NetworkingConnectionState.all
                                || !connectionSearch
                                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            processesFiltered: tab == .processes
                                && (ui.networking.processFacetsFiltered
                                    || !processSearch
                                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                            focus: ui.networking.focus,
                            onToggle: toggleFocus
                        )

                        ProtocolCard(
                            counts: protocolCounts,
                            ipVersions: ui.networking.ipVersions
                        )
                    }
                    .frame(minWidth: 232, idealWidth: 248, maxWidth: 256)
                }
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                PillTabBar(selection: $tab, selectionAnimation: pillAnimation)
                Spacer(minLength: 8)
                Text(contextLabel(interfaces: matchingInterfaces,
                                  sources: matchingSources,
                                  processes: matchingProcesses))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            if tab == .connections || tab == .processes {
                NetworkingFilterBar(tab: tab)
            }

            tableCard(interfaces: matchingInterfaces,
                      sources: matchingSources,
                      processes: matchingProcesses)
        }
        .padding(.horizontal, KBTheme.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func contextLabel(interfaces: [KBInterfaceInfo],
                              sources: [KBNStatSource],
                              processes: [ProcessInventoryRow]) -> String {
        switch tab {
        case .interfaces:
            let total = model.interfaces.count
            return ui.networking.focus == nil
                ? "\(total) interfaces"
                : "\(interfaces.count) of \(total) interfaces"
        case .connections:
            let total = model.sources.count
            let active = ui.networking.focus != nil
                || ui.networking.protocolFilter.isActive
                || ui.networking.connectionStates != NetworkingConnectionState.all
                || !ui.networking.connectionSearch
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return active
                ? "\(sources.count) of \(total) connections"
                : "\(total) connections"
        case .processes:
            let total = model.processInventory.count
            let active = ui.networking.focus != nil
                || ui.networking.processFacetsFiltered
                || !ui.networking.processSearch
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return active
                ? "\(processes.count) of \(total) networked processes"
                : "\(total) networked processes"
        case .filter:
            return "\(filterModel.flows.count) observed flows · \(filterModel.watchedCount) watched"
        }
    }

    private func toggleFocus(_ newFocus: NetworkingFocus) {
        withAnimation(.snappy(duration: 0.2)) {
            ui.networking.focus = ui.networking.focus == newFocus ? nil : newFocus
        }
    }

    private func tableCard(interfaces: [KBInterfaceInfo],
                           sources: [KBNStatSource],
                           processes: [ProcessInventoryRow]) -> some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .interfaces:
                    InterfacesView(items: interfaces)
                case .connections:
                    ConnectionsView(rows: sources)
                case .processes:
                    ProcessesView(rows: processes)
                case .filter:
                    FilterView()
                }
            }
            .id(tab)
            .transition(tabTransition)
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}
