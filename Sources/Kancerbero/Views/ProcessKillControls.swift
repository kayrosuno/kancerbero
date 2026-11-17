import KancerberoCore
import SwiftUI

struct ProcessKillConfirmation: Equatable {
    let process: KBProcessInfo
    let requiresAdministrator: Bool
}

/// One alert per triggering view. The tables and the Process Inspector each own
/// their confirmation state, so a kill started in one window never presents a
/// second alert in another.
private struct ProcessKillConfirmationModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var confirmation: ProcessKillConfirmation?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .alert(confirmation.map { "Kill \(displayName($0.process))?" } ?? "",
                   isPresented: Binding(
                       get: { confirmation != nil },
                       set: { if !$0 { confirmation = nil } }
                   ),
                   presenting: confirmation) { item in
                Button("Cancel", role: .cancel) {
                    confirmation = nil
                }
                Button("Terminate") {
                    perform(item, signal: .terminate)
                }
                Button("Force Kill", role: .destructive) {
                    perform(item, signal: .forceKill)
                }
            } message: { item in
                Text(message(for: item))
            }
            .background {
                Color.clear.alert(
                    "Kill failed",
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    )) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
            }
    }

    private func perform(_ item: ProcessKillConfirmation,
                         signal: KBProcessSignal) {
        confirmation = nil
        Task { @MainActor in
            let result = await model.signalProcess(item.process, signal: signal)
            if !result.ok && result.code != KBProcessSignalCode.canceled {
                errorMessage = result.message
                    ?? "The process could not be signaled."
            }
        }
    }

    private func message(for item: ProcessKillConfirmation) -> String {
        let process = item.process
        var text = "PID \(process.pid) · \(model.userName(for: process.uid))\n\n"
            + "Terminate sends SIGTERM and lets the process quit. "
            + "Force Kill sends SIGKILL immediately and may lose unsaved work."
        if item.requiresAdministrator {
            text += "\n\nKilling another user's or a root process requires "
                + "administrator authorization; macOS will ask for a password."
        }
        if process.state == .stopped {
            text += "\n\nThe process is stopped; SIGTERM may remain pending until it resumes."
        }
        return text
    }

    private func displayName(_ process: KBProcessInfo) -> String {
        process.name.isEmpty ? "Process \(process.pid)" : process.name
    }
}

extension View {
    func processKillConfirmation(
        _ confirmation: Binding<ProcessKillConfirmation?>
    ) -> some View {
        modifier(ProcessKillConfirmationModifier(confirmation: confirmation))
    }
}

@MainActor @ViewBuilder
func processKillMenuButton(
    process: KBProcessInfo?,
    model: AppModel,
    confirmation: Binding<ProcessKillConfirmation?>
) -> some View {
    let availability = process.map { model.killAvailability(for: $0) }
        ?? ProcessKillAvailability(status: .disabled,
                                   reason: "Process identity is unavailable.")
    Button("Kill Process…", role: .destructive) {
        guard let process else { return }
        confirmation.wrappedValue = ProcessKillConfirmation(
            process: process,
            requiresAdministrator: availability.status == .needsAdministrator)
    }
    .disabled(!availability.isEnabled)
    .help(availability.reason ?? "Terminate or force kill this process")
}
