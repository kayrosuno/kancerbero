import SwiftUI

/// Expand/restore control shared by the Disk → Volumes detail cards.
struct DiskExpandButton: View {
    let isMaximized: Bool
    let subject: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isMaximized
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isMaximized ? "Restore \(subject)" : "Maximize \(subject)")
        .accessibilityLabel(isMaximized ? "Restore \(subject)" : "Maximize \(subject)")
    }
}
