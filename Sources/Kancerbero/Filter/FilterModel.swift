import AppKit
import Foundation
import Observation
import UserNotifications
import KancerberoCore
import KancerberoFilterContract

/// UI-facing model for the network filter: rules, live flows, pending
/// approvals and the extension lifecycle.
@MainActor
@Observable
final class FilterModel {
    private(set) var rules: [FilterRule] = []
    private(set) var remembered: [RememberedDecision] = []
    private(set) var flows: [FlowRecord] = []
    private(set) var pending: [FilterRequest] = []
    private(set) var history: [FlowRecord] = []
    private(set) var status: FilterStatus?
    private(set) var isConnected = false
    /// True while the XPC `hello` handshake is in flight, so views can disable
    /// Retry and avoid duplicate probes.
    var isConnecting: Bool { connecting }
    private(set) var isBusy = false
    var lastError: String?

    let controller = FilterController()

    private var client: FilterXPCClient?
    /// Requests decided locally whose confirmation from the extension has not
    /// arrived yet. Pushes generated before the decision must not resurrect them.
    private var locallyResolved: Set<UUID> = []
    private var connecting = false
    private var reconnectTask: Task<Void, Never>?
    private var notificationAuthorized = false

    private static let rulesKey = "filterRules.v1"
    private static let rememberedKey = "filterRemembered.v1"

    var recentBlocks: [FlowRecord] {
        history.filter { $0.state == .denied }.prefix(20).map { $0 }
    }

    var watchedCount: Int { rules.count }

    func start() {
        loadPersistence()
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.controller.refresh()
            if self.controller.state.isEnabled {
                // Repair installs where the filter configuration survived but
                // the system extension was never activated.
                self.controller.ensureInstalled()
                await self.connect()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if self.controller.state.isEnabled && !self.isConnected && !self.connecting {
                    await self.connect()
                }
            }
        }
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        client?.disconnect()
        client = nil
        isConnected = false
    }

    // MARK: - Filter lifecycle

    func enableFilter() async {
        guard controller.isSupported else { return }
        isBusy = true
        defer { isBusy = false }
        requestNotificationAuthorization()

        switch controller.state {
        case .enabled:
            await connect()
        case .unsupported:
            return
        case .disabled, .failed, .notInstalled, .requiresApproval, .activating:
            // Never enable NEFilterManager before macOS has activated the
            // extension. While `.activating`, this upgrades the pending
            // request's intent instead of submitting a duplicate.
            controller.installAndEnable()
        }
    }

    func disableFilter() async {
        isBusy = true
        defer { isBusy = false }
        await controller.disable()
        client?.disconnect()
        client = nil
        isConnected = false
        flows.removeAll()
        pending.removeAll()
    }

    func uninstallFilter() async {
        isBusy = true
        defer { isBusy = false }
        await controller.uninstall()
        client?.disconnect()
        client = nil
        isConnected = false
        flows.removeAll()
        pending.removeAll()
    }

    // MARK: - Rules

    func isWatched(_ process: KBProcessInfo) -> Bool {
        guard !process.path.isEmpty else { return false }
        return rules.contains { $0.executablePath == process.path }
    }

    func policy(for process: KBProcessInfo) -> FilterPolicy? {
        guard !process.path.isEmpty else { return nil }
        return rules.first { $0.executablePath == process.path }?.policy
    }

    func watch(_ process: KBProcessInfo) {
        guard !process.path.isEmpty else { return }
        if let index = rules.firstIndex(where: { $0.executablePath == process.path }) {
            if rules[index].policy != .ask {
                rules[index].policy = .ask
            }
        } else {
            rules.append(FilterRule(executablePath: process.path,
                                    bundleID: Bundle(path: process.path)?.bundleIdentifier,
                                    displayName: process.name,
                                    policy: .ask))
        }
        persistRules()
        Task { await pushRules() }
    }

    func unwatch(_ process: KBProcessInfo) {
        guard !process.path.isEmpty else { return }
        removeRule(atPath: process.path)
    }

    func setPolicy(_ policy: FilterPolicy, for process: KBProcessInfo) {
        guard !process.path.isEmpty else { return }
        if let index = rules.firstIndex(where: { $0.executablePath == process.path }) {
            rules[index].policy = policy
        } else {
            rules.append(FilterRule(executablePath: process.path,
                                    bundleID: Bundle(path: process.path)?.bundleIdentifier,
                                    displayName: process.name,
                                    policy: policy))
        }
        persistRules()
        Task { await pushRules() }
    }

    /// Changes the policy of an existing rule addressed by `FilterRule.id`.
    /// FilterRulesView has neither `KBProcessInfo` nor `AppModel`, so it
    /// cannot use the process-based overload.
    func setPolicy(_ policy: FilterPolicy, forRuleID id: FilterRule.ID) {
        guard let index = rules.firstIndex(where: { $0.id == id }),
              rules[index].policy != policy else { return }
        rules[index].policy = policy
        persistRules()
        Task { await pushRules() }
    }

    func isWatched(path: String) -> Bool {
        rules.contains { $0.executablePath == path }
    }

    func removeRule(id: UUID) {
        guard let rule = rules.first(where: { $0.id == id }) else { return }
        removeRule(atPath: rule.executablePath)
    }

    func removeRemembered(id: UUID) {
        guard remembered.contains(where: { $0.id == id }) else { return }
        remembered.removeAll { $0.id == id }
        persistRemembered()
        Task { await pushRules() }
    }

    private func removeRule(atPath path: String) {
        rules.removeAll { $0.executablePath == path }
        remembered.removeAll { $0.executablePath == path }
        persistRules()
        persistRemembered()
        Task { await pushRules() }
    }

    // MARK: - Approvals

    func decide(_ request: FilterRequest,
                allow: Bool,
                remember: FilterRemember) async {
        pending.removeAll { $0.id == request.id }
        locallyResolved.insert(request.id)

        if remember != .none, !request.executablePath.isEmpty {
            // Remember an "app + destination" decision under every key the
            // endpoint can be reported with (`host:port` and `address:port`),
            // otherwise the next flow may not match and asks again.
            let keys: [String?]
            if remember == .destination {
                let destinations = request.remote?.destinationKeys ?? []
                keys = destinations.isEmpty ? [nil] : destinations.map { Optional($0) }
            } else {
                keys = [nil]
            }
            for key in keys {
                remembered.removeAll {
                    $0.executablePath == request.executablePath && $0.destination == key
                }
                remembered.append(RememberedDecision(executablePath: request.executablePath,
                                                     destination: key,
                                                     allow: allow))
            }
            persistRemembered()
        }

        let message = FilterDecisionMessage(flowID: request.id,
                                            allow: allow,
                                            remember: remember,
                                            destinationKey: request.remote?.destinationKey,
                                            destinationKeys: request.remote?.destinationKeys,
                                            executablePath: request.executablePath)
        _ = await client?.request(FilterCodec.envelope(.decide, value: message))
        if remember != .none {
            await pushRules()
        }
    }

    // MARK: - Connection

    func connect() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }

        client?.disconnect()
        let client = FilterXPCClient()
        client.configure(
            onPush: { [weak self] push in
                self?.apply(push)
            },
            onConnectionChange: { [weak self] connected in
                self?.isConnected = connected
            }
        )
        self.client = client

        guard await client.connect() else {
            isConnected = false
            return
        }
        isConnected = true
        await pushRules()

        if let reply = await client.request(FilterCodec.envelope(.snapshotRequest)),
           let envelope = try? FilterCodec.decodeEnvelope(reply),
           let snapshot = try? FilterCodec.decodePayload(FilterSnapshot.self, from: envelope) {
            apply(snapshot)
        }
    }

    private func pushRules() async {
        guard let client, client.isConnected else { return }
        let snapshot = FilterRuleSnapshot(rules: rules, remembered: remembered)
        _ = await client.request(FilterCodec.envelope(.setRules, value: snapshot))
    }

    // MARK: - Applying extension state

    private func apply(_ snapshot: FilterSnapshot) {
        status = snapshot.status
        if rules.isEmpty {
            rules = snapshot.rules
            remembered = snapshot.remembered
            persistRules()
            persistRemembered()
        }
        flows = snapshot.flows
        // The snapshot is authoritative: if the extension still lists a request,
        // the decision never reached it and it must be shown again.
        locallyResolved.removeAll()
        pending = snapshot.pending
        history = snapshot.history
        announcePendingIfNeeded()
    }

    private func apply(_ push: FilterPush) {
        if let status = push.status {
            self.status = status
        }

        for request in push.pending {
            // Ignore stale pushes that still list requests already decided here;
            // the extension confirms them through `resolved`.
            guard !locallyResolved.contains(request.id) else { continue }
            if let index = pending.firstIndex(where: { $0.id == request.id }) {
                pending[index] = request
            } else {
                pending.append(request)
            }
        }
        let resolved = Set(push.resolved)
        if !resolved.isEmpty {
            pending.removeAll { resolved.contains($0.id) }
            locallyResolved.subtract(resolved)
        }

        for flow in push.flows {
            if let index = flows.firstIndex(where: { $0.id == flow.id }) {
                flows[index] = flow
            } else {
                flows.append(flow)
            }
        }
        let removed = Set(push.removedFlows)
        if !removed.isEmpty {
            flows.removeAll { removed.contains($0.id) }
        }

        if !push.history.isEmpty {
            history.insert(contentsOf: push.history, at: 0)
            if history.count > 200 {
                history.removeLast(history.count - 200)
            }
        }

        if !push.pending.isEmpty {
            announcePendingIfNeeded()
        }
    }

    private func announcePendingIfNeeded() {
        guard !pending.isEmpty, !NSApp.isActive else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.requestUserAttention(.criticalRequest)
        postNotification()
    }

    private func requestNotificationAuthorization() {
        guard !notificationAuthorized else { return }
        notificationAuthorized = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification() {
        guard !pending.isEmpty else { return }
        let content = UNMutableNotificationContent()
        if let request = pending.first {
            content.title = "Network connection waiting"
            content.body = "\(request.processName) wants to connect to "
                + (request.remote?.display ?? "the network")
        } else {
            content.title = "Network connection waiting"
        }
        content.sound = .default
        let notification = UNNotificationRequest(identifier: "kancerbero-filter-pending-\(UUID().uuidString)",
                                                 content: content,
                                                 trigger: nil)
        UNUserNotificationCenter.current().add(notification)
    }

    // MARK: - Persistence

    private func loadPersistence() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.rulesKey),
           let value = try? JSONDecoder().decode([FilterRule].self, from: data) {
            rules = value
        }
        if let data = defaults.data(forKey: Self.rememberedKey),
           let value = try? JSONDecoder().decode([RememberedDecision].self, from: data) {
            remembered = value
        }
    }

    private func persistRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: Self.rulesKey)
    }

    private func persistRemembered() {
        guard let data = try? JSONEncoder().encode(remembered) else { return }
        UserDefaults.standard.set(data, forKey: Self.rememberedKey)
    }
}
