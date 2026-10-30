import AppKit
import SwiftUI
import KancerberoCore

struct ApplicationsView: View {
    @Environment(ApplicationsModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var confirming = false
    @State private var resultMessage: String?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            SectionHeader(title: "Applications",
                          subtitle: "Apps, widgets & plugins")

            summary

            controls

            HStack(spacing: 12) {
                ApplicationsTable(selection: $model.selectedPath)
                if model.selectedBundle != nil {
                    LeftoversPanel(onClose: { model.clearSelection() },
                                   onTrash: { confirming = true })
                        .frame(minWidth: 380, idealWidth: 520, maxWidth: 600)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, KBTheme.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            if model.bundles.isEmpty {
                await model.refresh()
            }
        }
        .sheet(isPresented: $confirming) { confirmation }
        .alert("Removal finished", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    // MARK: - Summary

    private var summary: some View {
        LazyVGrid(columns: KBTheme.summaryColumns, spacing: KBTheme.summaryGridSpacing) {
            SummaryCard(title: "Applications",
                        value: "\(model.applicationCount)",
                        caption: "installed bundles",
                        systemImage: "app.dashed",
                        tint: Color(red: 0.20, green: 0.70, blue: 0.62))
            SummaryCard(title: "Widgets & plugins",
                        value: "\(model.extensionCount)",
                        caption: "extensions and panels",
                        systemImage: "puzzlepiece.extension",
                        tint: Color(red: 0.62, green: 0.42, blue: 0.95))
            SummaryCard(title: "Selection",
                        value: KBFormat.bytes(model.selectedBytes),
                        caption: "\(model.selectedLeftovers.count) related files",
                        systemImage: "trash",
                        tint: Color(red: 0.94, green: 0.56, blue: 0.18))
        }
    }

    // MARK: - Controls

    private var controls: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            kindChip(.application, "Applications")
            kindChip(.widget, "Widgets")
            kindChip(.plugin, "Plugins")

            Divider().frame(height: 14).opacity(0.4)

            scopeChip(.system, "System")
            scopeChip(.user, "User")

            Spacer()

            if model.isScanning || model.isTrashing {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.refresh(force: true) }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning || model.isTrashing)
        }
    }

    private func scopeChip(_ scope: KBAppScope, _ title: String) -> some View {
        let selected = model.scopeFilter.contains(scope)
        return Button {
            if selected, model.scopeFilter.count > 1 {
                model.scopeFilter.remove(scope)
            } else {
                model.scopeFilter.insert(scope)
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(selected
                        ? Color.secondary.opacity(0.20)
                        : Color.secondary.opacity(0.08))
                }
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func kindChip(_ kind: KBAppKind, _ title: String) -> some View {
        let selected = model.kindFilter.contains(kind)
        return Button {
            if selected, model.kindFilter.count > 1 {
                model.kindFilter.remove(kind)
            } else {
                model.kindFilter.insert(kind)
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(selected
                        ? Color.accentColor.opacity(0.18)
                        : Color.secondary.opacity(0.10))
                }
                .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirmation

    private var confirmation: some View {
        let bundle = model.selectedBundle
        let running = bundle.map { runningApplication(at: $0.path) } ?? false
        let privileged = model.selectedLeftovers.contains(where: \.requiresPrivilege)
        let appNeedsDaemon = bundle.map {
            !FileManager.default.isWritableFile(atPath: $0.path)
        } ?? false
        let needsDaemon = (privileged || appNeedsDaemon)
            && appModel.daemonTrashClient == nil
        return VStack(alignment: .leading, spacing: 14) {
            Text("Remove \(bundle?.name ?? "item")?")
                .font(.system(size: 16, weight: .semibold))
            Text("\(model.selectedLeftovers.count + 1) items · \(KBFormat.bytes(model.selectedBytes))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if running {
                Label("The application is running. Its process keeps running until you quit it; "
                      + "some containers may be recreated.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if privileged {
                Label("Some items live in a system location; the root daemon is required.",
                      systemImage: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if needsDaemon {
                Label("The root daemon is not connected. Install or start it from "
                      + "System status before removing system items.",
                      systemImage: "xmark.octagon")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if let bundle, !bundle.isProtected {
                        Text(bundle.path)
                    }
                    ForEach(model.selectedLeftovers) { item in
                        Text(item.path)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)

            HStack {
                Spacer()
                Button("Cancel") { confirming = false }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    confirming = false
                    Task { await performTrash() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isTrashing || needsDaemon)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func runningApplication(at path: String) -> Bool {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL.path == target
        }
    }

    private func performTrash() async {
        let client = appModel.daemonTrashClient
        let results = await model.trashSelected { items in
            guard let client else {
                throw NSError(domain: "kancerbero.apps", code: 1,
                              userInfo: [NSLocalizedDescriptionKey:
                                         "the root daemon is not connected"])
            }
            return try client.trashItems(items)
        }
        let failed = results.filter { !$0.ok }
        if failed.isEmpty {
            resultMessage = "Moved \(results.count) items to the Trash."
        } else {
            let details = failed.prefix(4).map {
                "\($0.path): \($0.message ?? "error")"
            }.joined(separator: "\n")
            resultMessage = "\(results.count - failed.count) moved, "
                + "\(failed.count) failed.\n\(details)"
        }
    }
}
