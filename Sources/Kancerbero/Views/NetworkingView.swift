import SwiftUI
import KancerberoCore

struct NetworkingView: View {
    @Binding var tab: NetworkingTab
    @Environment(AppModel.self) private var model
    @State private var focus: NetworkingFocus?

    init(tab: Binding<NetworkingTab>) {
        _tab = tab
        let arguments = CommandLine.arguments
        let parsed: NetworkingFocus?
        if let flag = arguments.firstIndex(of: "--networking-focus"),
           flag + 1 < arguments.count {
            parsed = NetworkingFocus(rawValue: arguments[flag + 1].lowercased())
        } else {
            parsed = nil
        }
        _focus = State(initialValue: parsed)
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Networking")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Live traffic, sockets and process inventory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Interval", selection: $model.interval) {
                    Text("0.5 s").tag(0.5)
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

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

            LazyVGrid(columns: KBTheme.summaryColumns,
                      spacing: KBTheme.summaryGridSpacing) {
                SummaryCard(
                    title: "Download",
                    value: KBFormat.rate(model.systemRates.rxBytesPerSecond),
                    caption: "system-wide receive",
                    systemImage: "arrow.down.circle.fill",
                    tint: Color(red: 0.16, green: 0.62, blue: 0.94),
                    sparkline: model.rxHistory,
                    action: { toggleFocus(.download) },
                    isSelected: focus == .download,
                    filterHint: "Show rows with receive traffic"
                )
                SummaryCard(
                    title: "Upload",
                    value: KBFormat.rate(model.systemRates.txBytesPerSecond),
                    caption: "system-wide send",
                    systemImage: "arrow.up.circle.fill",
                    tint: Color(red: 0.62, green: 0.42, blue: 0.95),
                    sparkline: model.txHistory,
                    action: { toggleFocus(.upload) },
                    isSelected: focus == .upload,
                    filterHint: "Show rows with send traffic"
                )
                SummaryCard(
                    title: "Connections",
                    value: KBFormat.compactCount(model.sources.count),
                    caption: "active flows",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tint: Color(red: 0.20, green: 0.70, blue: 0.62),
                    action: { toggleFocus(.connections) },
                    isSelected: focus == .connections,
                    filterHint: "Show rows tied to active connections"
                )
                SummaryCard(
                    title: "Processes",
                    value: KBFormat.compactCount(model.processes.count),
                    caption: "visible to the daemon",
                    systemImage: "square.stack.3d.up.fill",
                    tint: Color(red: 0.94, green: 0.56, blue: 0.18),
                    action: { toggleFocus(.processes) },
                    isSelected: focus == .processes,
                    filterHint: "Show rows attributable to processes"
                )
            }

            HStack(spacing: 12) {
                PillTabBar(selection: $tab)
                Spacer()
                Text(contextLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            tableCard
        }
        .padding(.horizontal, KBTheme.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var contextLabel: String {
        switch tab {
        case .interfaces:
            let total = model.interfaces.count
            let shown = model.filteredInterfaces(focus).count
            return focus == nil ? "\(total) interfaces" : "\(shown) of \(total) interfaces"
        case .connections:
            let total = model.sources.count
            let shown = model.filteredSources(focus).count
            return focus == nil ? "\(total) connections" : "\(shown) of \(total) connections"
        case .processes:
            let total = model.processes.count
            let shown = model.filteredProcesses(focus).count
            return focus == nil ? "\(total) processes" : "\(shown) of \(total) processes"
        }
    }

    private func toggleFocus(_ newFocus: NetworkingFocus) {
        withAnimation(.snappy(duration: 0.2)) {
            focus = focus == newFocus ? nil : newFocus
        }
    }

    private var tableCard: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .interfaces:
                    InterfacesView(items: model.filteredInterfaces(focus))
                case .connections:
                    ConnectionsView(rows: model.filteredSources(focus))
                case .processes:
                    ProcessesView(items: model.filteredProcesses(focus))
                }
            }
            .id(tab)
            .transition(.opacity)
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
        .animation(.snappy(duration: 0.25), value: tab)
    }
}
