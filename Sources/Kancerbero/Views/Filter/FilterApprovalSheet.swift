import AppKit
import SwiftUI
import KancerberoFilterContract

struct FilterApprovalSheet: View {
    let request: FilterRequest
    @Environment(FilterModel.self) private var filter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deciding = false
    @State private var remember: FilterRemember = .none
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            destinationCard
            countdown
            rememberRow
            actions
            footer
        }
        .padding(24)
        .frame(width: 640)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                KBTheme.brandGradient.opacity(0.10)
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            if request.remote == nil, remember == .destination {
                remember = .none
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            processIcon

            VStack(alignment: .leading, spacing: 4) {
                Text("CONNECTION REQUEST")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Text(displayProcessName)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 8) {
                    Text("wants to connect to the network")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    pidBadge
                    if request.delegated {
                        delegatedBadge
                    }
                    if deciding {
                        ProgressView().controlSize(.small)
                    }
                }

                if !request.executablePath.isEmpty {
                    Text(request.executablePath)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var processIcon: some View {
        if let icon = processIconImage {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .accessibilityLabel("Application icon")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(KBTheme.brandGradient)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .accessibilityLabel("Network filter")
        }
    }

    /// The executable inside an app bundle yields its app icon; the raw binary
    /// often resolves to the generic executable icon.
    private var processIconImage: NSImage? {
        let path = request.executablePath
        guard !path.isEmpty else { return nil }
        if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.upperBound].dropLast())
            if FileManager.default.fileExists(atPath: bundlePath) {
                return NSWorkspace.shared.icon(forFile: bundlePath)
            }
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private var displayProcessName: String {
        request.processName.isEmpty ? "Unknown process" : request.processName
    }

    private var pidBadge: some View {
        Text("PID \(request.pid)")
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(Color.gray.opacity(0.20))
            }
            .foregroundStyle(.secondary)
    }

    private var delegatedBadge: some View {
        Text("Delegated")
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(KBTheme.uploadTint.opacity(0.16))
            }
            .foregroundStyle(KBTheme.uploadTint)
            .help("A system process created this connection on behalf of the app.")
    }

    // MARK: - Destination

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("DESTINATION")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                transportBadge
            }

            if let remote = request.remote {
                Text(remote.hostname ?? remote.address)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    if let hostname = remote.hostname,
                       !hostname.isEmpty,
                       hostname != remote.address {
                        Text(remote.address)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if remote.port > 0 {
                        Text("port \(String(remote.port))")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Unknown destination")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("From")
                Text(request.local?.display ?? "—")
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Text("Started \(request.startedAt.formatted(date: .omitted, time: .standard))")
                    .monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.gray.opacity(0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.20), lineWidth: 1)
        }
    }

    private var transportBadge: some View {
        Text(request.transport.uppercased())
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(transportTint.opacity(0.16))
            }
            .foregroundStyle(transportTint)
    }

    private var transportTint: Color {
        request.transport.lowercased().contains("udp")
            ? KBTheme.connectionsTint
            : KBTheme.downloadTint
    }

    // MARK: - Countdown

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(1, request.deadline.timeIntervalSince(request.startedAt))
            let remaining = max(0, request.deadline.timeIntervalSince(context.date))
            let fraction = min(1, max(0, remaining / total))
            let seconds = Int(remaining.rounded(.up))
            let tint = countdownTint(fraction: fraction, seconds: seconds)

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.20), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(seconds)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(width: 58, height: 58)
                .opacity(seconds <= 3 ? (pulse ? 1 : 0.45) : 1)
                .accessibilityLabel("\(seconds) seconds remaining")

                VStack(alignment: .leading, spacing: 3) {
                    Text(seconds > 0
                         ? "Auto-deny in \(seconds) s"
                         : "Expired — denying")
                        .font(.system(size: 15, weight: .medium))
                        .contentTransition(.numericText())
                        .foregroundStyle(seconds <= 3 ? KBTheme.approvalDenyTint : .primary)
                    Text("No decision denies the connection (fail-closed).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func countdownTint(fraction: Double, seconds: Int) -> Color {
        if seconds <= 3 { return KBTheme.approvalDenyTint }
        if fraction <= 0.25 { return KBTheme.processesTint }
        return KBTheme.approvalAllowTint
    }

    // MARK: - Remember

    private var rememberRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REMEMBER THIS DECISION")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            Picker("Remember", selection: $remember) {
                Text("Once").tag(FilterRemember.none)
                Text("This app").tag(FilterRemember.app)
                if request.remote != nil {
                    Text("App + destination").tag(FilterRemember.destination)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(deciding)

            Text(rememberDetail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rememberDetail: String {
        switch remember {
        case .none:
            return "Only this connection is decided; the next one asks again."
        case .app:
            return "Every connection from this app uses this decision."
        case .destination:
            return "This app uses the decision only for this destination."
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                decide(allow: false, remember: remember)
            } label: {
                Label("Deny", systemImage: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(KBTheme.approvalDenyTint)
            .keyboardShortcut(.cancelAction)
            .accessibilityHint("Blocks this connection; Remember makes it permanent.")
            .disabled(deciding)

            Button {
                decide(allow: true, remember: remember)
            } label: {
                Label("Allow", systemImage: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(KBTheme.approvalAllowTint)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Allows this connection; Remember makes it permanent.")
            .disabled(deciding)
        }
        .controlSize(.large)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().opacity(0.4)

            Text("While Kancerbero is closed, watched processes are denied unless a remembered decision allows them.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Disable filter") {
                disableFilter()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(KBTheme.approvalDenyTint)
            .help("Turns off the network filter and stops asking for approvals.")
            .disabled(deciding)
        }
    }

    // MARK: - Actions

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
}
