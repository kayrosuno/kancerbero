import Foundation
import NetworkExtension
import os
import KancerberoFilterContract

/// All provider state lives behind this serial queue. `NEFilterDataProvider`
/// callbacks arrive on framework queues, so every mutation is funnelled here.
final class FilterCore: NSObject, @unchecked Sendable, KancerberoFilterXPC {
    private let queue = DispatchQueue(label: "uno.kayros.kancerbero.filter.core")
    private let log = Logger(subsystem: "uno.kayros.kancerbero.filter", category: "core")

    private weak var provider: FilterDataProvider?
    private var rules: [FilterRule] = []
    private var remembered: [RememberedDecision] = []
    private var blockAllNewConnections = false
    private var flows: [UUID: FlowRecord] = [:]
    private var lastReport: [UUID: (inbound: UInt64, outbound: UInt64)] = [:]
    private var paused: [UUID: NEFilterFlow] = [:]
    private var pending: [UUID: FilterRequest] = [:]
    private var clients: [ObjectIdentifier: NSXPCConnection] = [:]
    private var history: [FlowRecord] = []
    private var dirtyFlows: Set<UUID> = []
    private var removedFlows: Set<UUID> = []
    private var newHistory: [FlowRecord] = []
    private var startedAt: Date?
    private var lastError: String?

    private var listener: NSXPCListener?
    private var listenerDelegate: FilterListenerDelegate?
    private var flushTimer: DispatchSourceTimer?

    private let maxFlows = 2_000
    private let maxHistory = 200
    private let maxPaused = 32
    private let tcpApprovalTimeout: TimeInterval = 60
    private let udpApprovalTimeout: TimeInterval = 8

    // MARK: - Lifecycle

    func start(provider: FilterDataProvider) {
        queue.sync {
            self.provider = provider
            self.startedAt = Date()
            self.loadCacheLocked()
            self.startListenerLocked()
            self.startFlushTimerLocked()
            self.log.info("filter started with \(self.rules.count, privacy: .public) rules")
        }
    }

    func stop() {
        queue.sync {
            self.dropAllPausedLocked(reason: "filter stopped")
            self.flushTimer?.cancel()
            self.flushTimer = nil
            self.listener?.invalidate()
            self.listener = nil
            self.listenerDelegate = nil
            self.clients.removeAll()
            self.startedAt = nil
            self.log.info("filter stopped")
        }
    }

    // MARK: - Provider callbacks

    func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        queue.sync {
            let flowID = flow.identifier
            let identity = FilterProcessIdentity.resolve(flow)
            let endpoints = FilterFlowEndpoints.describe(flow)
            let rule = identity.path.isEmpty
                ? nil
                : rules.first(where: { $0.executablePath == identity.path })

            var state: FilterFlowState = .observing
            var reason: String?
            var verdict: NEFilterNewFlowVerdict

            func remember(_ record: inout FlowRecord) {
                if flows.count < maxFlows || flows[flowID] != nil {
                    record.state = state
                    record.deniedReason = reason
                    record.ruleID = blockAllNewConnections ? nil : rule?.id
                    flows[flowID] = record
                    dirtyFlows.insert(flowID)
                }
            }

            if blockAllNewConnections {
                // Global override: deny every new flow before rules and
                // remembered decisions get a chance to allow it.
                state = .denied
                reason = "block all"
                verdict = .drop()
            } else if let rule {
                switch rule.policy {
                case .allow:
                    state = .allowed
                    verdict = .allow()
                case .deny:
                    state = .denied
                    reason = "rule"
                    verdict = .drop()
                case .ask:
                    let destinationKeys = endpoints.remote?.destinationKeys ?? []
                    if let decision = rememberedDecisionLocked(path: identity.path,
                                                                keys: destinationKeys) {
                        state = decision.allow ? .allowed : .denied
                        reason = decision.allow ? nil : "remembered"
                        verdict = decision.allow ? .allow() : .drop()
                    } else if clients.isEmpty {
                        state = .denied
                        reason = "no app"
                        verdict = .drop()
                    } else if paused.count >= maxPaused {
                        state = .denied
                        reason = "too many pending"
                        verdict = .drop()
                    } else {
                        state = .pending
                        let deadline = Date().addingTimeInterval(endpoints.isUDP
                                                                ? udpApprovalTimeout
                                                                : tcpApprovalTimeout)
                        let request = FilterRequest(id: flowID,
                                                    pid: identity.pid,
                                                    executablePath: identity.path,
                                                    processName: identity.name,
                                                    local: endpoints.local,
                                                    remote: endpoints.remote,
                                                    transport: endpoints.transport,
                                                    deadline: deadline,
                                                    delegated: identity.delegated)
                        pending[flowID] = request
                        paused[flowID] = flow
                        scheduleExpiryLocked(flowID, after: deadline.timeIntervalSinceNow)
                        verdict = .pause()
                        log.info("paused flow \(flowID.uuidString, privacy: .public) for \(identity.name, privacy: .public)")
                    }
                }
            } else {
                state = .observing
                verdict = .allow()
            }

            verdict.shouldReport = true
            verdict.statisticsReportFrequency = .medium
            var record = FlowRecord(id: flowID,
                                    pid: identity.pid,
                                    executablePath: identity.path,
                                    processName: identity.name,
                                    local: endpoints.local,
                                    remote: endpoints.remote,
                                    transport: endpoints.transport,
                                    state: state,
                                    delegated: identity.delegated)
            remember(&record)

            if state == .pending {
                flushLocked()
            }
            return verdict
        }
    }

    /// Values are extracted before hopping queues because `NEFilterReport`
    /// and `NEFilterFlow` are not `Sendable`.
    func handleReport(flowID: UUID, inbound: UInt64, outbound: UInt64, closed: Bool) {
        queue.async {
            guard var record = self.flows[flowID] else { return }
            self.accumulateLocked(&record, inbound: inbound, outbound: outbound, final: closed)
            if closed {
                record.endedAt = Date()
                self.flows.removeValue(forKey: flowID)
                self.lastReport.removeValue(forKey: flowID)
                self.history.append(record)
                if self.history.count > self.maxHistory {
                    self.history.removeFirst(self.history.count - self.maxHistory)
                }
                self.newHistory.append(record)
                self.removedFlows.insert(flowID)
                self.dirtyFlows.remove(flowID)
            } else {
                self.flows[flowID] = record
                self.dirtyFlows.insert(flowID)
            }
        }
    }

    // MARK: - XPC service

    func send(_ envelope: Data, reply: @escaping (Data) -> Void) {
        let response = queue.sync { self.handleLocked(envelope) }
        reply(response)
    }

    func attach(connection: NSXPCConnection) {
        queue.sync {
            self.clients[ObjectIdentifier(connection)] = connection
            self.log.info("client connected (\(self.clients.count, privacy: .public))")
            self.deliverLocked(FilterPush(status: self.statusLocked(),
                                          pending: Array(self.pending.values)))
        }
    }

    func detach(connectionID: ObjectIdentifier) {
        queue.async {
            self.clients.removeValue(forKey: connectionID)
            self.log.info("client disconnected (\(self.clients.count, privacy: .public))")
            if self.clients.isEmpty {
                self.dropAllPausedLocked(reason: "app disconnected")
            }
        }
    }

    private func handleLocked(_ data: Data) -> Data {
        do {
            let envelope = try FilterCodec.decodeEnvelope(data)
            guard envelope.schemaVersion == FilterVersion.schema else {
                return FilterCodec.envelope(.helloAck,
                                            value: FilterAck(ok: false, message: "schema mismatch"))
            }
            switch envelope.kind {
            case .hello:
                return FilterCodec.envelope(.helloAck,
                                            value: FilterAck(ok: true, message: FilterVersion.current))
            case .setRules:
                let snapshot = try FilterCodec.decodePayload(FilterRuleSnapshot.self, from: envelope)
                rules = snapshot.rules
                remembered = snapshot.remembered
                blockAllNewConnections = snapshot.blockAllNewConnections
                saveCacheLocked()

                // Arming the global block resolves any flow already paused for
                // approval; the resolved IDs let the app close its sheet.
                var dropped: [UUID] = []
                if blockAllNewConnections, !paused.isEmpty {
                    dropped = Array(paused.keys)
                    dropAllPausedLocked(reason: "block all")
                }
                flushLocked(resolved: dropped)
                return FilterCodec.envelope(.setRulesAck, value: FilterAck(ok: true))
            case .decide:
                let message = try FilterCodec.decodePayload(FilterDecisionMessage.self, from: envelope)
                applyDecisionLocked(message)
                return FilterCodec.envelope(.decideAck, value: FilterAck(ok: true))
            case .snapshotRequest:
                return FilterCodec.envelope(.snapshot, value: snapshotLocked())
            default:
                return FilterCodec.envelope(.helloAck,
                                            value: FilterAck(ok: false, message: "unsupported"))
            }
        } catch {
            lastError = String(describing: error)
            log.error("xpc error: \(String(describing: error), privacy: .public)")
            return FilterCodec.envelope(.helloAck,
                                        value: FilterAck(ok: false, message: String(describing: error)))
        }
    }

    private func snapshotLocked() -> FilterSnapshot {
        FilterSnapshot(status: statusLocked(),
                       rules: rules,
                       remembered: remembered,
                       flows: Array(flows.values),
                       pending: pending.values.sorted { $0.startedAt < $1.startedAt },
                       history: history)
    }

    // MARK: - Decisions

    private func applyDecisionLocked(_ message: FilterDecisionMessage) {
        guard let flow = paused.removeValue(forKey: message.flowID) else {
            pending.removeValue(forKey: message.flowID)
            return
        }
        pending.removeValue(forKey: message.flowID)

        // A decision can race the global block; while it is on, nothing is
        // allowed and no remembered allow/deny is stored.
        let allow = message.allow && !blockAllNewConnections
        let verdict: NEFilterNewFlowVerdict = allow ? .allow() : .drop()
        verdict.shouldReport = true
        verdict.statisticsReportFrequency = .medium
        provider?.resumeFlow(flow, with: verdict)

        if var record = flows[message.flowID] {
            record.state = allow ? .allowed : .denied
            record.deniedReason = allow ? nil
                : (blockAllNewConnections ? "block all" : "user")
            flows[message.flowID] = record
            dirtyFlows.insert(message.flowID)
        }

        if !blockAllNewConnections,
           let path = message.executablePath, !path.isEmpty {
            switch message.remember {
            case .none:
                break
            case .app:
                addRememberedLocked(path: path, destination: nil, allow: message.allow)
            case .destination:
                let keys = message.destinationKeys ?? [message.destinationKey].compactMap { $0 }
                for key in keys {
                    addRememberedLocked(path: path, destination: key, allow: message.allow)
                }
            }
        }

        flushLocked(resolved: [message.flowID])
    }

    private func addRememberedLocked(path: String, destination: String?, allow: Bool) {
        let already = remembered.contains {
            $0.executablePath == path && $0.destination == destination && $0.allow == allow
        }
        guard !already else { return }
        remembered.append(RememberedDecision(executablePath: path,
                                             destination: destination,
                                             allow: allow))
        saveCacheLocked()
    }

    private func rememberedDecisionLocked(path: String, keys: [String]) -> RememberedDecision? {
        let candidates = remembered.filter { $0.executablePath == path }
        if let specific = candidates.first(where: { decision in
            guard let destination = decision.destination else { return false }
            return keys.contains(destination)
        }) {
            return specific
        }
        return candidates.first { $0.destination == nil }
    }

    private func scheduleExpiryLocked(_ id: UUID, after seconds: TimeInterval) {
        queue.asyncAfter(deadline: .now() + max(0, seconds)) { [weak self] in
            self?.expireLocked(id)
        }
    }

    private func expireLocked(_ id: UUID) {
        guard let flow = paused.removeValue(forKey: id) else { return }
        pending.removeValue(forKey: id)
        let verdict: NEFilterNewFlowVerdict = .drop()
        verdict.shouldReport = true
        verdict.statisticsReportFrequency = .medium
        provider?.resumeFlow(flow, with: verdict)
        if var record = flows[id] {
            record.state = .denied
            record.deniedReason = "timeout"
            flows[id] = record
            dirtyFlows.insert(id)
        }
        log.info("approval timed out for flow \(id.uuidString, privacy: .public)")
        flushLocked(resolved: [id])
    }

    private func dropAllPausedLocked(reason: String) {
        for (id, flow) in paused {
            let verdict: NEFilterNewFlowVerdict = .drop()
            verdict.shouldReport = true
            verdict.statisticsReportFrequency = .medium
            provider?.resumeFlow(flow, with: verdict)
            if var record = flows[id] {
                record.state = .denied
                record.deniedReason = reason
                flows[id] = record
                dirtyFlows.insert(id)
            }
        }
        paused.removeAll()
        pending.removeAll()
    }

    // MARK: - Flows and statistics

    private func accumulateLocked(_ record: inout FlowRecord,
                                  inbound: UInt64,
                                  outbound: UInt64,
                                  final: Bool) {
        let last = lastReport[record.id] ?? (0, 0)
        if final {
            record.bytesIn = max(record.bytesIn, inbound)
            record.bytesOut = max(record.bytesOut, outbound)
        } else {
            record.bytesIn += inbound >= last.inbound ? inbound - last.inbound : inbound
            record.bytesOut += outbound >= last.outbound ? outbound - last.outbound : outbound
        }
        lastReport[record.id] = (inbound, outbound)
    }

    // MARK: - Push

    private func startFlushTimerLocked() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            self?.flushLocked()
        }
        timer.resume()
        flushTimer = timer
    }

    private func flushLocked(resolved: [UUID] = []) {
        guard !clients.isEmpty else {
            dirtyFlows.removeAll()
            removedFlows.removeAll()
            newHistory.removeAll()
            return
        }
        let push = FilterPush(status: statusLocked(),
                              pending: pending.values.sorted { $0.startedAt < $1.startedAt },
                              resolved: resolved,
                              flows: dirtyFlows.compactMap { flows[$0] },
                              removedFlows: Array(removedFlows),
                              history: newHistory)
        dirtyFlows.removeAll()
        removedFlows.removeAll()
        newHistory.removeAll()
        if push.resolved.isEmpty && push.flows.isEmpty
            && push.removedFlows.isEmpty && push.history.isEmpty
            && push.pending.isEmpty {
            return
        }
        deliverLocked(push)
    }

    private func deliverLocked(_ push: FilterPush) {
        guard let payload = try? FilterCodec.encode(push) else { return }
        let envelope = FilterCodec.envelope(.push, payload: payload)
        for connection in clients.values {
            (connection.remoteObjectProxy as? KancerberoFilterClientXPC)?.receive(envelope)
        }
    }

    // MARK: - Status and rules persistence

    private func statusLocked() -> FilterStatus {
        FilterStatus(version: FilterVersion.current,
                     startedAt: startedAt,
                     ruleCount: rules.count,
                     clientCount: clients.count,
                     pausedFlows: paused.count,
                     observedFlows: flows.count,
                     lastError: lastError)
    }

    private var cacheURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("KancerberoFilter", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return directory.appendingPathComponent("rules.plist")
    }

    private func loadCacheLocked() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return }
        guard let snapshot = try? PropertyListDecoder().decode(FilterRuleSnapshot.self, from: data) else {
            return
        }
        rules = snapshot.rules
        remembered = snapshot.remembered
        blockAllNewConnections = snapshot.blockAllNewConnections
    }

    private func saveCacheLocked() {
        guard let url = cacheURL else { return }
        let snapshot = FilterRuleSnapshot(rules: rules,
                                          remembered: remembered,
                                          blockAllNewConnections: blockAllNewConnections)
        guard let data = try? PropertyListEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Mach service

    private func startListenerLocked() {
        let listener = NSXPCListener(machServiceName: FilterXPCNames.machService)
        let delegate = FilterListenerDelegate(core: self)
        listener.delegate = delegate
        listener.setConnectionCodeSigningRequirement(FilterXPCNames.clientRequirement)
        listener.resume()
        self.listener = listener
        self.listenerDelegate = delegate
    }
}

final class FilterListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let core: FilterCore

    init(core: FilterCore) {
        self.core = core
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: KancerberoFilterXPC.self)
        newConnection.exportedObject = core
        newConnection.remoteObjectInterface = NSXPCInterface(with: KancerberoFilterClientXPC.self)

        let identifier = ObjectIdentifier(newConnection)
        newConnection.invalidationHandler = { [weak core] in
            core?.detach(connectionID: identifier)
        }
        newConnection.resume()
        core.attach(connection: newConnection)
        return true
    }
}
