import Darwin
import Foundation
import KancerberoCore
import os

private let logger = Logger(subsystem: "com.alejandro.kancerbero", category: "daemon")

/// Sendable wrapper for an XPC reply closure used from a detached task.
private final class ReplyBox: @unchecked Sendable {
    private let reply: (Data?, NSError?) -> Void

    init(_ reply: @escaping (Data?, NSError?) -> Void) {
        self.reply = reply
    }

    func send(_ data: Data?) {
        reply(data, nil)
    }
}

/// Small Sendable wrapper so the subscription task can hold the client proxy.
private final class ClientSink: @unchecked Sendable {
    private let proxy: KancerberoClientXPC

    init(proxy: KancerberoClientXPC) {
        self.proxy = proxy
    }

    func push(_ data: Data) {
        proxy.push(data)
    }
}

final class DaemonService: NSObject, KancerberoDaemonXPC, @unchecked Sendable {
    private let collector = CollectionActor()
    private let lock = NSLock()
    private weak var connection: NSXPCConnection?
    private var task: Task<Void, Never>?
    private var sequence: UInt64 = 0
    private var subscribedAt: Date?

    func configure(connection: NSXPCConnection) {
        lock.lock()
        self.connection = connection
        lock.unlock()
    }

    func connectionInvalidated() {
        lock.lock()
        task?.cancel()
        task = nil
        connection = nil
        lock.unlock()
        logger.notice("client disconnected")
    }

    func handshake(_ message: Data, reply: @escaping (Data) -> Void) {
        let request = (try? KBWireCodec.decode(KBHelloRequest.self, from: message))
            ?? KBHelloRequest()
        let response = KBHelloResponse(capabilities: KBCapabilitiesProbe.current())
        logger.notice("handshake app=\(request.appVersion, privacy: .public) schema=\(request.schemaVersion)")
        guard let data = try? KBWireCodec.encode(response) else {
            reply(Data())
            return
        }
        reply(data)
    }

    func subscribe(_ config: Data, reply: @escaping (Data?, NSError?) -> Void) {
        guard let subscription = try? KBWireCodec.decode(KBSubscription.self, from: config) else {
            reply(nil, NSError(domain: "kancerbero", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "invalid subscription"]))
            return
        }

        lock.lock()
        let connection = self.connection
        task?.cancel()
        task = nil
        lock.unlock()

        guard let connection else {
            reply(nil, NSError(domain: "kancerbero", code: 2,
                               userInfo: [NSLocalizedDescriptionKey: "no connection"]))
            return
        }
        guard let proxy = connection.remoteObjectProxy as? KancerberoClientXPC else {
            reply(nil, NSError(domain: "kancerbero", code: 3,
                               userInfo: [NSLocalizedDescriptionKey: "client does not export the callback interface"]))
            return
        }

        let interval = min(max(subscription.interval, 0.5), 10.0)
        let sink = ClientSink(proxy: proxy)
        let newTask = Task { [weak self, sink] in
            var sequence: UInt64 = 0
            while !Task.isCancelled {
                guard let self else { return }
                var collection = await self.collector.refresh()
                collection.mode = geteuid() == 0 ? .daemonFull : .daemonRestricted
                let capabilities = KBCapabilitiesProbe.current()
                let diagnostics = KBDiagnostics(
                    sourceCount: collection.sources.count,
                    tickDurationMilliseconds: 0,
                    lastError: collection.error
                )
                let payload = KBSnapshotPayload(
                    collection: collection,
                    capabilities: capabilities,
                    diagnostics: diagnostics
                )
                if let payloadData = try? KBWireCodec.encode(payload) {
                    sequence &+= 1
                    let envelope = KBWireEnvelope(
                        kind: .snapshot,
                        sequence: sequence,
                        monotonicNanoseconds: collection.monotonicNanoseconds,
                        payload: payloadData
                    )
                    if let data = try? KBWireCodec.encode(envelope) {
                        sink.push(data)
                    }
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }

        lock.lock()
        task = newTask
        subscribedAt = Date()
        lock.unlock()

        logger.notice("subscribed interval=\(interval) topics=\(subscription.topics.count)")
        reply(Data(), nil)
    }

    func request(_ message: Data, reply: @escaping (Data?, NSError?) -> Void) {
        guard let request = try? KBWireCodec.decode(KBRequestMessage.self, from: message) else {
            reply(nil, NSError(domain: "kancerbero", code: 4,
                               userInfo: [NSLocalizedDescriptionKey: "invalid request"]))
            return
        }

        switch request.kind {
        case .snapshot:
            let box = ReplyBox(reply)
            Task { [collector] in
                var collection = await collector.refresh()
                collection.mode = geteuid() == 0 ? .daemonFull : .daemonRestricted
                let payload = KBSnapshotPayload(
                    collection: collection,
                    capabilities: KBCapabilitiesProbe.current(),
                    diagnostics: KBDiagnostics(sourceCount: collection.sources.count,
                                               lastError: collection.error)
                )
                box.send(try? KBWireCodec.encode(payload))
            }
        case .processDetail:
            guard let pid = request.pid, pid > 0 else {
                reply(nil, NSError(domain: "kancerbero", code: 5,
                                   userInfo: [NSLocalizedDescriptionKey: "missing pid"]))
                return
            }
            let box = ReplyBox(reply)
            Task {
                let detail = await Self.processDetail(pid: pid)
                let payload = KBDetailPayload(detail: detail)
                box.send(try? KBWireCodec.encode(payload))
            }
        }
    }

    func unsubscribe() {
        lock.lock()
        task?.cancel()
        task = nil
        lock.unlock()
        logger.notice("unsubscribed")
    }

    private static func processDetail(pid: Int32) async -> KBProcessDetail {
        var process = KBProcessInfo(pid: pid)
        if let found = try? ProcessCollector.snapshot().first(where: { $0.pid == pid }) {
            process = found
        }
        do {
            let sockets = try SocketCollector.snapshot(pid: pid)
            let files = try OpenFileCollector.snapshot(pid: pid)
            let openFiles = files.map {
                KBOpenFileSample(fd: $0.fd, type: $0.typeName, path: $0.path,
                                 size: Int64(clamping: $0.size))
            }
            return KBProcessDetail(process: process, sockets: sockets, openFiles: openFiles)
        } catch {
            return KBProcessDetail(process: process, restricted: true,
                                   source: "libproc", processGone: true)
        }
    }
}
