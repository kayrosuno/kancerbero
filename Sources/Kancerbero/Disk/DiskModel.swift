import AppKit
import Foundation
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

    var scanRootPath: String
    var scanOptions = KBDiskScanOptions()
    var scanState: ScanState = .idle
    var scanProgress: KBDiskScanProgress?
    var scanSnapshot: KBDiskScanSnapshot?
    var currentNodeID: String?
    var deniedPaths: [String] = []

    var showHidden = false
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
                }
            })
        }
    }

    var selectedItem: KBDiskItem? {
        guard let selectedItemID, let inventory else { return nil }
        return inventory.allItems.first { $0.deviceIdentifier == selectedItemID }
    }

    var currentNode: KBDiskNode? {
        guard let snapshot = scanSnapshot else { return nil }
        if let currentNodeID, let node = snapshot.root.node(at: currentNodeID) {
            return node
        }
        return snapshot.root
    }

    var lineToCurrentNode: [KBDiskNode] {
        guard let snapshot = scanSnapshot, let node = currentNode else { return [] }
        return snapshot.root.lineage(to: node.path)
    }

    var isScanning: Bool { scanState == .scanning }

    func refreshInventory(force: Bool = false) async {
        if isLoadingInventory { return }
        if !force, let inventory,
           Date().timeIntervalSince(inventory.generatedAt) < 30 {
            return
        }

        isLoadingInventory = true
        inventoryError = nil
        let collector = inventoryCollector
        let snapshot = await Task.detached(priority: .utility) {
            collector.snapshot()
        }.value

        inventory = snapshot
        inventoryError = snapshot.error
        isLoadingInventory = false

        if let selectedItemID,
           snapshot.allItems.contains(where: { $0.deviceIdentifier == selectedItemID }) {
            return
        }
        selectedItemID = snapshot.mountedVolumes.first?.deviceIdentifier
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
        currentNodeID = nil
        deniedPaths = []

        var options = scanOptions
        options.includeHiddenInLargestFiles = showHidden

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let snapshot = DiskScanner.scan(rootPath: target, options: options) { progress in
                Task { @MainActor in
                    guard self.scanGeneration == generation,
                          self.scanState == .scanning else { return }
                    self.scanProgress = progress
                }
            }

            await MainActor.run {
                guard self.scanGeneration == generation else { return }
                self.scanSnapshot = snapshot
                self.scanProgress = nil
                self.currentNodeID = snapshot.root.path
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
        currentNodeID = node.path
    }

    func drillUp() {
        guard let snapshot = scanSnapshot, let node = currentNode else { return }
        let lineage = snapshot.root.lineage(to: node.path)
        if lineage.count >= 2 {
            currentNodeID = lineage[lineage.count - 2].path
        } else {
            currentNodeID = snapshot.root.path
        }
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
