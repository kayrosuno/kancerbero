import SwiftUI
import KancerberoCore

struct ProcessInspectorView: View {
    let process: KBProcessInfo

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var detail: KBProcessDetail?
    @State private var errorMessage: String?
    @State private var section = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.name.isEmpty ? "Process \(process.pid)" : process.name)
                        .font(.title3.weight(.semibold))
                    Text("PID \(process.pid) · UID \(process.uid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !process.path.isEmpty {
                        Text(process.path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("Refresh") { Task { await refresh() } }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            Picker("Section", selection: $section) {
                Text("Sockets").tag(0)
                Text("Open Files").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let detail {
                if section == 0 {
                    socketsTable(detail.sockets)
                } else {
                    filesTable(detail.openFiles)
                }
                if detail.restricted {
                    Text("Permission denied for this process. Install the daemon (root) to inspect other users.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(minWidth: 780, minHeight: 480)
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func socketsTable(_ sockets: [KBSocketInfo]) -> some View {
        Table(sockets) {
            TableColumn("FD") { item in Text("\(item.fd)").monospacedDigit() }
                .width(min: 40, ideal: 55)
            TableColumn("Proto") { item in Text(item.protocolLabel).monospaced() }
                .width(min: 60, ideal: 90)
            TableColumn("Local") { item in Text(item.local.display).monospaced() }
            TableColumn("Remote") { item in Text(item.remote.display).monospaced() }
            TableColumn("State") { item in Text(item.stateName.isEmpty ? "—" : item.stateName) }
                .width(min: 90, ideal: 110)
        }
    }

    private func filesTable(_ files: [KBOpenFileSample]) -> some View {
        Table(files) {
            TableColumn("FD") { item in Text("\(item.fd)").monospacedDigit() }
                .width(min: 40, ideal: 55)
            TableColumn("Type") { item in Text(item.type) }
                .width(min: 100, ideal: 130)
            TableColumn("Size") { item in
                Text(item.size > 0 ? KBFormat.bytes(UInt64(clamping: item.size)) : "—")
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)
            TableColumn("Path") { item in
                Text(item.path.isEmpty ? "—" : item.path)
                    .foregroundStyle(item.path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }
        }
    }

    private func refresh() async {
        let result = await model.detail(for: process)
        detail = result
        errorMessage = nil
    }
}
