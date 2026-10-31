import AppKit
import SwiftUI
import KancerberoCore

struct ApplicationsView: View {
    @Environment(ApplicationsModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var confirming = false
    @State private var resultMessage: String?
    @State private var permissionHint = false
    @State private var isPreparingTrash = false

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
            set: { if !$0 { resultMessage = nil; permissionHint = false } }
        )) {
            if permissionHint {
                Button("Open Full Disk Access") {
                    resultMessage = nil
                    permissionHint = false
                    if let url = URL(string: "x-apple.systempreferences:"
                                     + "com.apple.settings.PrivacySecurity.extension"
                                     + "?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Button("OK") { resultMessage = nil; permissionHint = false }
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

    private var daemonReady: Bool {
        appModel.daemonTrashClient != nil
            && appModel.daemonSupportsTrash
            && appModel.daemonIsRoot
    }

    // MARK: - Confirmation

    private var confirmation: some View {
        let bundle = model.selectedBundle
        let running = bundle.map { runningApplication(at: $0.path) } ?? false
        let privileged = model.selectedLeftovers.contains(where: \.requiresPrivilege)
        let appNeedsDaemon = bundle.map {
            !$0.isProtected && !FileManager.default.isWritableFile(atPath: $0.path)
        } ?? false
        let protectedAppData = model.selectedLeftovers.contains {
            $0.kind == .container || $0.kind == .groupContainer
                || $0.kind == .appScripts
        }
        let needsDaemon = privileged || appNeedsDaemon || protectedAppData
        let helperOutdated = needsDaemon && !daemonReady
        return VStack(alignment: .leading, spacing: 16) {
            Text("Remove \(bundle?.name ?? "item")?")
                .font(.system(size: 20, weight: .semibold))
            Text("\(model.selectedLeftovers.count + 1) items · \(KBFormat.bytes(model.selectedBytes))")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            if running {
                Label("The application is running. Its process keeps running until you quit it; "
                      + "some containers may be recreated.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if privileged {
                Label("Some items live in a system location; the root daemon is required.",
                      systemImage: "lock.shield")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if bundle?.isApple == true, bundle?.isProtected == false {
                Label("Apple application: removing it may affect your Mac and "
                      + "requires administrator rights.",
                      systemImage: "exclamationmark.shield")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if helperOutdated {
                Label("The background helper is outdated or not connected; it will "
                      + "restart automatically before removing these items.",
                      systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let bundle, !bundle.isProtected {
                        Text(bundle.path)
                    }
                    ForEach(model.selectedLeftovers) { item in
                        Text(item.path)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)

            HStack {
                Spacer()
                Button("Cancel") { confirming = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isPreparingTrash)
                Button {
                    guard !isPreparingTrash else { return }
                    Task { await performTrash() }
                } label: {
                    Label(isPreparingTrash ? "Restarting helper…" : "Move to Trash",
                          systemImage: isPreparingTrash ? "arrow.clockwise" : "trash")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.isTrashing || isPreparingTrash)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func runningApplication(at path: String) -> Bool {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL.path == target
        }
    }

    private func performTrash() async {
        permissionHint = false
        let bundle = model.selectedBundle
        let appNeedsDaemon = bundle.map {
            !$0.isProtected && !FileManager.default.isWritableFile(atPath: $0.path)
        } ?? false
        let privileged = model.selectedLeftovers.contains(where: \.requiresPrivilege)
        // Containers and app scripts are protected by macOS (TCC App Data) even
        // when the user owns them, so keep a daemon client ready for the retry.
        let protectedAppData = model.selectedLeftovers.contains {
            $0.kind == .container || $0.kind == .groupContainer
                || $0.kind == .appScripts
        }

        if appNeedsDaemon || privileged || protectedAppData,
           !daemonReady {
            isPreparingTrash = true
            await appModel.restartDaemonService()
            isPreparingTrash = false
            guard daemonReady else {
                resultMessage = "The background helper could not be restarted. "
                    + "Start it from System status and try again."
                return
            }
        }

        confirming = false
        // Re-read after the restart: the previous connection was replaced.
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
        permissionHint = failed.contains {
            $0.code == KBTrashError.permissionCode
                && isProtectedAppDataPath($0.path)
        }
        if failed.isEmpty {
            resultMessage = "Moved \(results.count) items to the Trash."
        } else {
            let details = failed.prefix(4).map {
                "\($0.path): \($0.message ?? "error")"
            }.joined(separator: "\n")
            var message = "\(results.count - failed.count) moved, "
                + "\(failed.count) failed.\n\(details)"
            if permissionHint {
                message += "\n\nmacOS protects other apps' data. Allow Kancerbero "
                    + "in System Settings → Privacy & Security → Full Disk Access "
                    + "and try again."
            }
            resultMessage = message
        }
    }

    private func isProtectedAppDataPath(_ path: String) -> Bool {
        let item = KBPathPolicy.normalized(path)
        let home = KBPathPolicy.normalized(NSHomeDirectory())
        return item.hasPrefix(home + "/Library/Containers/")
            || item.hasPrefix(home + "/Library/Group Containers/")
            || item.hasPrefix(home + "/Library/Application Scripts/")
            || item.hasPrefix("/Library/Containers/")
    }
}
