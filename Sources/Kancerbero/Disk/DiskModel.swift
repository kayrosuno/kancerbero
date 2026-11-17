import AppKit
import Foundation
import Darwin
import Observation
import KancerberoCore

@MainActor
@Observable
final class DiskModel {
    enum ScanState: Equatable {
        case idle
        case scanning
        case finished
        case failed(String)
    }

    var inventory: KBDiskInventorySnapshot?
    var inventoryError: String?
    var isLoadingInventory = false
    var selectedItemID: String?

    var filesystemSnapshot: KBFilesystemSnapshot?
    var filesystemError: String?
    var isLoadingFilesystems = false

    var operationProgress: String?
    var operationError: String?
    private var ejectDisks: [String: String] = [:]
    private let operationService = DiskOperationService()

    private static var homeFilesystemPath: String? {
        let path = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        // statfs crosses APFS firmlinks; resolvingSymlinks alone does not.
        return withUnsafePointer(to: &info.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    private var operationPolicy: KBDiskOperationPolicy? {
        guard let inventory, inventory.error == nil,
              let filesystemSnapshot, filesystemSnapshot.error == nil,
              filesystemSnapshot.filesystems.contains(where: { $0.mountPoint == "/" }),
              let homePath = Self.homeFilesystemPath else { return nil }
        return KBDiskOperationPolicy(inventory: inventory,
            filesystems: filesystemSnapshot.filesystems,
            homePath: homePath,
            ejectDisks: ejectDisks)
    }

    func canPerform(_ action: KBDiskAction, on target: KBDiskOperationTarget) -> Bool {
        operationProgress == nil && operationPolicy?.steps(for: action, target: target) != nil
    }

    func perform(_ action: KBDiskAction, on target: KBDiskOperationTarget, name: String) async {
        guard operationProgress == nil else { return }
        let originalInventory = inventory
        operationProgress = "\(action.rawValue) · \(name)…"
        operationError = nil
        defer { operationProgress = nil }
        // Collect independent fresh snapshots even if a UI refresh is already
        // in flight. Never authorize an operation from cached menu state.
        let collector = inventoryCollector
        let fresh = await Task.detached(priority: .utility) {
            let inventory = collector.snapshot()
            return (inventory, FilesystemCollector.snapshot(), DiskOperationService.ejectDisks(in: inventory))
        }.value
        inventory = fresh.0; filesystemSnapshot = fresh.1; ejectDisks = fresh.2
        do {
            guard let originalInventory,
                  let steps = operationPolicy?.steps(for: action, target: target),
                  Self.sameDevices(steps, before: originalInventory, after: fresh.0) else {
                throw KBDiskOperationError(message: "The target changed, is protected, or no longer supports this action.")
            }
            // A Filesystems row disappears after unmount. Preserve the local
            // inventory identity so eject can continue after that refresh.
            let executionTarget: KBDiskOperationTarget
            if case .filesystem(let row) = target,
               let local = fresh.0.allItems.first(where: { $0.mountPoint == row.mountPoint }),
               row.filesystem == "/dev/" + local.id {
                executionTarget = .disk(local.id, identity: .init(local))
            } else {
                executionTarget = target
            }
            // Each step is checked against current inventory/protections. Eject
            // is still conditional on successful completion of every unmount.
            for (index, step) in steps.enumerated() {
                let latest = await Task.detached(priority: .utility) {
                    let inventory = collector.snapshot()
                    return (inventory, FilesystemCollector.snapshot(), DiskOperationService.ejectDisks(in: inventory))
                }.value
                inventory = latest.0; filesystemSnapshot = latest.1; ejectDisks = latest.2
                let validationAction = action == .eject ? .eject : step.action
                guard let valid = operationPolicy?.steps(for: validationAction, target: executionTarget),
                      valid.contains(step),
                      Self.sameDevices(Array(steps[index...]), before: fresh.0, after: latest.0) else {
                    throw KBDiskOperationError(message: "The device state or its protections changed during the operation.")
                }
                operationProgress = "\(step.action.rawValue) · \(name) (\(step.device))…"
                try await operationService.execute(step)
            }
        } catch {
            operationError = "\(action.rawValue) · \(name): \(error.localizedDescription)"
            if action == .mount {
                operationError! += " If the volume is locked, unlock it in Disk Utility and try again."
            }
        }
        // Wait out a UI refresh so the final refresh cannot be skipped.
        while isLoadingInventory || isLoadingFilesystems {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await refreshInventory(force: true)
        await refreshFilesystems()
    }

    private static func sameDevices(_ steps: [KBDiskOperationStep],
                                    before: KBDiskInventorySnapshot,
                                    after: KBDiskInventorySnapshot) -> Bool {
        steps.filter { !$0.network }.allSatisfy { step in
            guard let old = before.allItems.first(where: { $0.id == step.device }),
                  let new = after.allItems.first(where: { $0.id == step.device }) else { return false }
            return old.kind == new.kind && old.volumeUUID == new.volumeUUID
                && old.mediaUUID == new.mediaUUID && old.parentID == new.parentID
                && old.sizeBytes == new.sizeBytes
        }
    }

    var scanRootPath: String
    var scanOptions = KBDiskScanOptions()
    var scanState: ScanState = .idle
    var scanProgress: KBDiskScanProgress?
    var scanSnapshot: KBDiskScanSnapshot?
    var liveSnapshot: KBDiskScanSnapshot?
    var currentNodeID: String?
    /// Shared Analyzer selection (map, contents and largest files tables).
    /// Stored as a path: either a tree node or a `largestFiles` row.
    var selectedNodeID: String?
    var deniedPaths: [String] = []

    var showHidden = true
    var showPackageContents = false
    var autoScan = false

    private let inventoryCollector = DiskInventoryCollector()
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    /// Retained so the mount/unmount observers stay registered for the app lifetime.
    private var mountObservers: [NSObjectProtocol] = []

    init() {
        scanRootPath = FileManager.default.homeDirectoryForCurrentUser.path
        if let path = Self.argumentValue("--disk-path") {
            scanRootPath = path
        }
        if let identifier = Self.argumentValue("--disk-item") {
            selectedItemID = identifier
        }
        autoScan = CommandLine.arguments.contains("--disk-scan")

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            mountObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.refreshInventory(force: true)
                    if self.filesystemSnapshot != nil {
                        await self.refreshFilesystems()
                    }
                }
            })
        }
    }

    var selectedItem: KBDiskItem? {
        guard let selectedItemID, let inventory else { return nil }
        return inventory.allItems.first { $0.deviceIdentifier == selectedItemID }
    }

    var activeSnapshot: KBDiskScanSnapshot? {
        scanSnapshot ?? liveSnapshot
    }

    var currentNode: KBDiskNode? {
        guard let snapshot = activeSnapshot else { return nil }
        if let currentNodeID,
           let node = Self.nearestNode(to: currentNodeID, in: snapshot.root) {
            return node
        }
        return snapshot.root
    }

    var lineToCurrentNode: [KBDiskNode] {
        guard let snapshot = activeSnapshot, let node = currentNode else { return [] }
        return snapshot.root.lineage(to: node.path)
    }

    private static func nearestNode(to path: String, in root: KBDiskNode) -> KBDiskNode? {
        var candidate = path
        while candidate.count >= root.path.count {
            if let node = root.node(at: candidate) { return node }
            let parent = (candidate as NSString).deletingLastPathComponent
            if parent == candidate || parent.isEmpty { break }
            candidate = parent
        }
        return nil
    }

    var isScanning: Bool { scanState == .scanning }

    func refreshInventory(force: Bool = false) async {
        if isLoadingInventory { return }
        if !force, let inventory,
           Date().timeIntervalSince(inventory.generatedAt) < 30 {
            return
        }

        let isInitialInventory = inventory == nil
        isLoadingInventory = true
        inventoryError = nil
        let collector = inventoryCollector
        let snapshot = await Task.detached(priority: .utility) {
            collector.snapshot()
        }.value

        ejectDisks = DiskOperationService.ejectDisks(in: snapshot)
        inventory = snapshot
        inventoryError = snapshot.error
        isLoadingInventory = false

        if let selectedItemID,
           snapshot.allItems.contains(where: { $0.deviceIdentifier == selectedItemID }) {
            return
        }
        selectedItemID = isInitialInventory ? snapshot.mountedVolumes.first?.deviceIdentifier : nil
    }

    func refreshFilesystems() async {
        guard !isLoadingFilesystems else { return }
        isLoadingFilesystems = true
        let snapshot = await Task.detached(priority: .utility) {
            FilesystemCollector.snapshot()
        }.value
        // Retain the last successful rows if enumerating the mount table fails.
        if snapshot.error == nil {
            filesystemSnapshot = snapshot
        }
        filesystemError = snapshot.error
        isLoadingFilesystems = false
    }

    func select(_ identifier: String?) {
        selectedItemID = identifier
    }

    func startScan(path: String? = nil) async {
        let requested = path ?? scanRootPath
        let target = (requested as NSString).expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }

        if isScanning {
            cancelScan()
        }

        scanRootPath = target
        scanGeneration &+= 1
        let generation = scanGeneration
        scanState = .scanning
        scanProgress = nil
        scanSnapshot = nil
        liveSnapshot = nil
        currentNodeID = nil
        selectedNodeID = nil
        deniedPaths = []

        var options = scanOptions
        options.includeHiddenInLargestFiles = showHidden

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let snapshot = DiskScanner.scan(
                rootPath: target,
                options: options,
                partial: { partial in
                    Task { @MainActor in
                        guard self.scanGeneration == generation,
                              self.scanState == .scanning else { return }
                        self.liveSnapshot = partial
                    }
                },
                progress: { progress in
                    Task { @MainActor in
                        guard self.scanGeneration == generation,
                              self.scanState == .scanning else { return }
                        self.scanProgress = progress
                    }
                }
            )

            await MainActor.run {
                guard self.scanGeneration == generation else { return }
                let resolvedID: String
                if let current = self.currentNodeID,
                   let node = Self.nearestNode(to: current, in: snapshot.root) {
                    resolvedID = node.path
                } else {
                    resolvedID = snapshot.root.path
                }
                self.scanSnapshot = snapshot
                self.liveSnapshot = nil
                self.scanProgress = nil
                self.currentNodeID = resolvedID
                if let selected = self.selectedNodeID,
                   snapshot.root.node(at: selected) == nil,
                   snapshot.file(at: selected) == nil,
                   !snapshot.largestFiles.contains(where: { $0.path == selected }) {
                    self.selectedNodeID = nil
                }
                self.deniedPaths = snapshot.deniedPaths
                if let error = snapshot.error {
                    self.scanState = .failed(error)
                } else {
                    self.scanState = .finished
                }
                self.scanTask = nil
            }
        }

        scanTask = task
        await task.value
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func consumeAutoScan() -> Bool {
        guard autoScan else { return false }
        autoScan = false
        return true
    }

    func drillDown(to node: KBDiskNode) {
        guard node.isDirectory, !node.isAggregate else { return }
        if node.isPackage && !showPackageContents { return }
        guard let snapshot = activeSnapshot,
              snapshot.root.node(at: node.path) != nil else { return }
        focus(on: node)
    }

    func drillUp() {
        guard let snapshot = activeSnapshot, let node = currentNode else { return }
        let lineage = snapshot.root.lineage(to: node.path)
        if lineage.count >= 2 {
            focus(on: lineage[lineage.count - 2])
        } else {
            focus(on: snapshot.root)
        }
    }

    /// Single navigation entry point so the shared selection always clears
    /// when the focus changes.
    func focus(on node: KBDiskNode) {
        guard let snapshot = activeSnapshot,
              snapshot.root.node(at: node.path) != nil else { return }
        if currentNodeID != node.path {
            selectedNodeID = nil
        }
        currentNodeID = node.path
    }

    /// Shared Analyzer selection. `nil` clears it. Directory paths replace the
    /// selection normally. A retained Contents file or a `largestFiles` row is
    /// not a tree node: if its direct parent is already the focus, only the
    /// selection changes (so the map draws the synthetic wedge); otherwise
    /// navigate to the nearest visible ancestor and keep the file path. The
    /// current focus (the center) clears it.
    func selectNode(_ path: String?) {
        guard let path, let snapshot = activeSnapshot else {
            selectedNodeID = nil
            return
        }

        if let node = snapshot.root.node(at: path) {
            selectedNodeID = node.path == currentNode?.path ? nil : path
            return
        }

        let parentPath = (path as NSString).deletingLastPathComponent
        let focusPath = currentNodeID ?? snapshot.root.path
        if parentPath == focusPath, snapshot.file(at: path) != nil {
            // No navigation: Contents only lists direct children of the focus.
            selectedNodeID = path
            return
        }

        guard snapshot.file(at: path) != nil
                || snapshot.largestFiles.contains(where: { $0.path == path }),
              let directory = Self.nearestNode(to: path, in: snapshot.root) else {
            selectedNodeID = nil
            return
        }

        // `focus(on:)` clears the selection when it actually moves the focus,
        // so navigate first and restore the file path afterwards. Keeping the
        // clear inside `focus(on:)` preserves normal navigation semantics.
        focus(on: directory)
        selectedNodeID = path
    }

    func volume(for path: String) -> KBDiskItem? {
        guard let inventory else { return nil }
        let standardized = (path as NSString).standardizingPath
        let matches = inventory.mountedVolumes.filter { volume in
            guard let mount = volume.mountPoint else { return false }
            return standardized == mount
                || standardized.hasPrefix(mount == "/" ? "/" : mount + "/")
        }
        return matches.max {
            ($0.mountPoint?.count ?? 0) < ($1.mountPoint?.count ?? 0)
        }
    }

    private static func argumentValue(_ name: String) -> String? {
        let arguments = CommandLine.arguments
        let prefix = name + "="
        if let inline = arguments.first(where: { $0.hasPrefix(prefix) }) {
            return String(inline.dropFirst(prefix.count))
        }
        guard let index = arguments.firstIndex(of: name),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
