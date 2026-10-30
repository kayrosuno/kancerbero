import Foundation
import Observation
import KancerberoCore

@MainActor
@Observable
final class ApplicationsModel {
    var bundles: [KBAppBundle] = []
    var isScanning = false
    var scanError: String?
    var generatedAt: Date?
    var searchText = ""
    var kindFilter = Set(KBAppKind.allCases)
    var selectedPath: String?

    var leftovers: [KBLeftover] = []
    var isScanningLeftovers = false
    var checkedLeftovers: Set<String> = []

    var isTrashing = false
    var lastTrashResults: [KBTrashResult] = []

    private var scanGeneration = 0
    private var leftoversCache: [String: [KBLeftover]] = [:]
    private var pendingSelection: String?

    init(arguments: [String] = CommandLine.arguments) {
        if let index = arguments.firstIndex(of: "--applications-search"),
           index + 1 < arguments.count {
            searchText = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--applications-selected"),
           index + 1 < arguments.count {
            pendingSelection = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--applications-kind"),
           index + 1 < arguments.count {
            let kinds = arguments[index + 1]
                .split(separator: ",")
                .compactMap { KBAppKind(rawValue: $0.lowercased()) }
            if !kinds.isEmpty {
                kindFilter = Set(kinds)
            }
        }
    }

    var visibleBundles: [KBAppBundle] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return bundles.filter { bundle in
            guard kindFilter.contains(bundle.kind) else { return false }
            guard !query.isEmpty else { return true }
            return bundle.name.lowercased().contains(query)
                || (bundle.displayName?.lowercased().contains(query) ?? false)
                || (bundle.bundleIdentifier?.lowercased().contains(query) ?? false)
        }
    }

    var selectedBundle: KBAppBundle? {
        bundles.first { $0.path == selectedPath }
    }

    var selectedLeftovers: [KBLeftover] {
        leftovers.filter { checkedLeftovers.contains($0.path) }
    }

    var selectedBytes: Int64 {
        (selectedBundle?.sizeBytes ?? 0)
            + selectedLeftovers.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    var applicationCount: Int {
        bundles.filter { $0.kind == .application }.count
    }

    var extensionCount: Int {
        bundles.count - applicationCount
    }

    func refresh(force: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        scanError = nil
        scanGeneration += 1
        let generation = scanGeneration

        let snapshot = await Task.detached(priority: .utility) {
            AppInventoryCollector.snapshot()
        }.value

        guard generation == scanGeneration else { return }
        bundles = snapshot.bundles
        generatedAt = snapshot.generatedAt
        isScanning = false

        if let selectedPath, !bundles.contains(where: { $0.path == selectedPath }) {
            self.selectedPath = nil
            leftovers = []
            checkedLeftovers = []
        }
        if let pendingSelection,
           let match = bundles.first(where: {
               $0.path == pendingSelection
                   || $0.bundleIdentifier == pendingSelection
                   || $0.name.caseInsensitiveCompare(pendingSelection) == .orderedSame
           }) {
            self.pendingSelection = nil
            await select(match.path)
        } else if selectedPath == nil {
            selectedPath = visibleBundles.first?.path
            await loadLeftovers()
        } else if !leftovers.isEmpty {
            await loadLeftovers()
        }
    }

    func select(_ path: String?) async {
        selectedPath = path
        leftovers = []
        checkedLeftovers = []
        await loadLeftovers()
    }

    func loadLeftovers() async {
        guard let bundle = selectedBundle else { return }
        if let cached = leftoversCache[bundle.path] {
            leftovers = cached
            checkedLeftovers = Set(cached.filter(\.selectedByDefault).map(\.path))
            return
        }

        isScanningLeftovers = true
        let home = NSHomeDirectory()
        async let foundTask = Task.detached(priority: .utility) {
            AppLeftoversCollector.leftovers(for: bundle, home: home)
        }.value
        async let sizeTask = Task.detached(priority: .utility) {
            KBAllocatedSize.allocatedSize(of: URL(fileURLWithPath: bundle.path))
        }.value

        let found = await foundTask
        let size = await sizeTask
        guard selectedPath == bundle.path else { return }

        if let index = bundles.firstIndex(where: { $0.path == bundle.path }) {
            bundles[index].sizeBytes = size
        }
        leftoversCache[bundle.path] = found
        leftovers = found
        checkedLeftovers = Set(found.filter(\.selectedByDefault).map(\.path))
        isScanningLeftovers = false
    }

    func toggleLeftover(_ path: String) {
        if checkedLeftovers.contains(path) {
            checkedLeftovers.remove(path)
        } else {
            checkedLeftovers.insert(path)
        }
    }

    func trashSelected(daemon: (@Sendable ([KBTrashItem]) throws -> [KBTrashResult])?) async
        -> [KBTrashResult] {
        guard let bundle = selectedBundle, !isTrashing else { return [] }
        isTrashing = true
        let items = TrashCoordinator.items(bundle: bundle, leftovers: selectedLeftovers)
        let results = await TrashCoordinator.trash(items: items, daemon: daemon)
        lastTrashResults = results
        isTrashing = false

        let appRemoved = results.contains { $0.path == bundle.path && $0.ok }
        if appRemoved {
            leftoversCache.removeValue(forKey: bundle.path)
            selectedPath = nil
            leftovers = []
            checkedLeftovers = []
            await refresh(force: true)
        } else {
            let remaining = leftovers.filter { item in
                results.contains { $0.path == item.path && !$0.ok }
            }
            leftoversCache[bundle.path] = remaining
            await loadLeftovers()
        }
        return results
    }
}
