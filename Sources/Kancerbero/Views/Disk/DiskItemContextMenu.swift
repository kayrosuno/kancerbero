import AppKit
import SwiftUI
import KancerberoCore

/// Context menu shared by every disk surface: tables, the detail card, the
/// vertical bar and the treemap. The actions always apply to the item the
/// menu was opened on, not to the current selection.
struct DiskItemContextMenu: View {
    let item: KBDiskItem
    var onAnalyze: ((String) -> Void)? = nil

    @Environment(\.openWindow) private var openWindow

    private var mountPoint: String? { item.mountPoint }

    var body: some View {
        DiskOperationMenu(target: .disk(item.id, identity: .init(item)), name: item.name)
        Divider()

        Button("Reveal") {
            reveal()
        }
        .disabled(mountPoint == nil)

        Button("Copy ID") {
            copyIdentifier()
        }

        Button("Analyze") {
            if let mountPoint {
                onAnalyze?(mountPoint)
            }
        }
        .disabled(mountPoint == nil || onAnalyze == nil)

        Divider()

        Button("Get Info") {
            openWindow(id: DiskItemInfoWindow.id,
                       value: item.deviceIdentifier)
        }
    }

    private func reveal() {
        guard let mountPoint else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: mountPoint)
        ])
    }

    private func copyIdentifier() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.deviceIdentifier,
                                       forType: .string)
    }
}

struct DiskOperationMenu: View {
    @Environment(DiskModel.self) private var disk
    let target: KBDiskOperationTarget?
    let name: String

    var body: some View {
        ForEach(KBDiskAction.allCases, id: \.self) { action in
            Button(action.rawValue) {
                if let target {
                    Task { await disk.perform(action, on: target, name: name) }
                }
            }
            .disabled(target.map { !disk.canPerform(action, on: $0) } ?? true)
        }
    }
}
