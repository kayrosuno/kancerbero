import SwiftUI
import KancerberoCore

struct DaemonStateBadge: View {
    let state: KBDaemonState

    var body: some View {
        Text(state.displayName)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .running: return .green
        case .stopped: return .orange
        case .disabled: return .secondary
        case .unloaded: return .blue
        }
    }
}
