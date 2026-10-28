import SwiftUI
import KancerberoFilterContract

struct FilterApprovalSheet: View {
    let request: FilterRequest
    @Environment(FilterModel.self) private var filter
    @Environment(\.dismiss) private var dismiss
    @State private var deciding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            details
            countdown
            Divider()
            actions
        }
        .padding(18)
        .frame(width: 440)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.orange)
            Text("Network connection waiting")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Process", "\(request.processName) (PID \(request.pid))")
            row("Executable", request.executablePath.isEmpty ? "—" : request.executablePath)
            row("Remote", request.remote?.display ?? "—")
            row("Local", request.local?.display ?? "—")
            row("Transport", request.transport.uppercased())
            if request.delegated {
                Text("This connection was created by a system process on behalf of the app.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(request.deadline.timeIntervalSince(context.date).rounded(.up)))
            Text(remaining > 0
                 ? "Denied automatically in \(remaining) s"
                 : "Expired — denying")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(remaining <= 3 ? .red : .secondary)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Allow once") {
                    decide(allow: true, remember: .none)
                }
                .buttonStyle(.borderedProminent)

                Button("Deny once") {
                    decide(allow: false, remember: .none)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("Always allow this app") {
                    decide(allow: true, remember: .app)
                }
                .buttonStyle(.bordered)

                Button("Always allow app + destination") {
                    decide(allow: true, remember: .destination)
                }
                .buttonStyle(.bordered)
                .disabled(request.remote == nil)
            }

            HStack(spacing: 8) {
                Button("Always deny this app") {
                    decide(allow: false, remember: .app)
                }
                .buttonStyle(.bordered)

                Button("Always deny app + destination") {
                    decide(allow: false, remember: .destination)
                }
                .buttonStyle(.bordered)
                .disabled(request.remote == nil)
            }

            Text("While Kancerbero is closed, watched processes are denied unless a remembered decision allows them.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button("Disable filter") {
                disableFilter()
            }
            .buttonStyle(.bordered)
            .help("Turns off the network filter and stops asking for approvals.")
        }
        .disabled(deciding)
    }

    private func disableFilter() {
        deciding = true
        Task {
            await filter.disableFilter()
            dismiss()
        }
    }

    private func decide(allow: Bool, remember: FilterRemember) {
        deciding = true
        Task {
            await filter.decide(request, allow: allow, remember: remember)
            dismiss()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}
