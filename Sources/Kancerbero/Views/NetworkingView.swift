import SwiftUI
import KancerberoCore

struct NetworkingView: View {
    @Binding var tab: NetworkingTab
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
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
        @Bindable var model = model
        let rates = model.systemRates
        let protocolFilter = ui.networking.protocolFilter
        let activityConnections = model.filteredSources(nil, matching: protocolFilter).count
        let activityProcesses = model.filteredProcessRows(nil, matching: protocolFilter).count
        let ipOnly = NetworkingProtocolFilter(ipVersion: ui.networking.ipVersion)
        let protocolCounts = Dictionary(
            grouping: model.sources.filter(ipOnly.matches),
            by: \.protocolBucket
        ).mapValues(\.count)

        let matchingInterfaces = model.filteredInterfaces(ui.networking.focus)
        let matchingSources = model.filteredSources(ui.networking.focus,
                                                    matching: protocolFilter)
        let matchingProcesses = model.filteredProcessRows(ui.networking.focus,
                                                          matching: protocolFilter)

        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Networking")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Live traffic, sockets and process inventory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("Interval")
                        .font(.body)
                        .lineLimit(1)
                        .fixedSize()

                    Picker("Interval", selection: $model.interval) {
                        Text("0.5 s").tag(0.5)
                        Text("1 s").tag(1.0)
                        Text("2 s").tag(2.0)
                        Text("5 s").tag(5.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                    .accessibilityLabel("Interval")
                }
                .fixedSize(horizontal: true, vertical: false)

                Toggle(isOn: $model.isPaused) {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .help(model.isPaused ? "Resume" : "Pause")

                Button {
                    model.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh now")
            }

            HStack(alignment: .top, spacing: KBTheme.summaryGridSpacing) {
                TrafficCard(
                    downloadBytesPerSecond: rates.rxBytesPerSecond,
                    uploadBytesPerSecond: rates.txBytesPerSecond,
                    downloadHistory: model.rxHistory,
                    uploadHistory: model.txHistory,
                    focus: ui.networking.focus,
                    sampleInterval: model.interval,
                    onToggle: toggleFocus
                )
                .frame(minWidth: 400, maxWidth: .infinity)

                VStack(spacing: KBTheme.summaryGridSpacing) {
                    ActivityCard(
                        connectionsCount: activityConnections,
                        processesCount: activityProcesses,
                        isFiltered: protocolFilter.isActive,
                        focus: ui.networking.focus,
                        onToggle: toggleFocus
                    )

                    ProtocolCard(
                        counts: protocolCounts,
                        ipVersion: ui.networking.ipVersion
                    )
                }
                .frame(minWidth: 232, idealWidth: 248, maxWidth: 256)
            }

            HStack(spacing: 12) {
                PillTabBar(selection: $tab, selectionAnimation: pillAnimation)
                if tab != .interfaces {
                    OptionFilterPicker("Transport",
                                       selection: transportBinding,
                                       optionTitle: { $0.title })
                    OptionFilterPicker("IP",
                                       selection: ipVersionBinding,
                                       optionTitle: { $0.title })
                }
                Spacer(minLength: 8)
                Text(contextLabel(interfaces: matchingInterfaces,
                                  sources: matchingSources,
                                  processes: matchingProcesses))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
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

    private var transportBinding: Binding<NetworkingTransport?> {
        Binding(
            get: { ui.networking.transport },
            set: { ui.networking.transport = $0 }
        )
    }

    private var ipVersionBinding: Binding<NetworkingIPVersion?> {
        Binding(
            get: { ui.networking.ipVersion },
            set: { ui.networking.ipVersion = $0 }
        )
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
            let active = ui.networking.focus != nil || ui.networking.protocolFilter.isActive
            return active
                ? "\(sources.count) of \(total) connections"
                : "\(total) connections"
        case .processes:
            let total = model.processInventory.count
            let active = ui.networking.focus != nil || ui.networking.protocolFilter.isActive
            return active
                ? "\(processes.count) of \(total) networked processes"
                : "\(total) networked processes"
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
