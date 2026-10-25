import Foundation
import KancerberoCore
import os

private let logger = Logger(subsystem: "uno.kayros.kancerbero", category: "daemon.client")

private final class Box<T>: @unchecked Sendable {
    var value: T?
}

final class DaemonMetricsSource: NSObject, KancerberoClientXPC, @unchecked Sendable {
    var onCollection: ((KBCollectionSnapshot) -> Void)?
    var onInvalidate: (() -> Void)?

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var remote: KancerberoDaemonXPC?
    private var active = false

    func start(interval: TimeInterval, privileged: Bool = false) throws -> KBHelloResponse {
        let options: NSXPCConnection.Options = privileged ? [.privileged] : []
        let connection = NSXPCConnection(machServiceName: KancerberoXPCNames.machService,
                                         options: options)
        connection.remoteObjectInterface = NSXPCInterface(with: KancerberoDaemonXPC.self)
        connection.exportedInterface = NSXPCInterface(with: KancerberoClientXPC.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in self?.handleInvalidate() }
        connection.interruptionHandler = { [weak self] in self?.handleInvalidate() }
        connection.resume()

        guard let remote = connection.remoteObjectProxy as? KancerberoDaemonXPC else {
            connection.invalidate()
            throw KBCollectionError.unavailable("daemon proxy unavailable")
        }

        let handshakeReply = Box<Data>()
        let handshakeSemaphore = DispatchSemaphore(value: 0)
        let helloRequest = try KBWireCodec.encode(KBHelloRequest())
        remote.handshake(helloRequest) { data in
            handshakeReply.value = data
            handshakeSemaphore.signal()
        }
        guard handshakeSemaphore.wait(timeout: .now() + 2) == .success,
              let helloData = handshakeReply.value,
              let hello = try? KBWireCodec.decode(KBHelloResponse.self, from: helloData) else {
            connection.invalidate()
            throw KBCollectionError.unavailable("daemon handshake failed")
        }
        guard hello.schemaVersion == KBVersion.schema else {
            connection.invalidate()
            throw KBCollectionError.unavailable("daemon schema \(hello.schemaVersion) is incompatible with \(KBVersion.schema)")
        }

        let subscription = try KBWireCodec.encode(KBSubscription(interval: interval))
        remote.subscribe(subscription) { _, error in
            if let error {
                logger.error("subscribe failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        lock.lock()
        self.connection = connection
        self.remote = remote
        self.active = true
        lock.unlock()

        logger.notice("connected to daemon \(hello.daemonVersion, privacy: .public)")
        return hello
    }

    func requestDetail(pid: Int32) throws -> KBProcessDetail {
        lock.lock()
        let remote = self.remote
        lock.unlock()
        guard let remote else {
            throw KBCollectionError.unavailable("daemon is not connected")
        }
        let message = try KBWireCodec.encode(KBRequestMessage(kind: .processDetail, pid: pid))
        let replyData = Box<Data>()
        let replyError = Box<NSError>()
        let semaphore = DispatchSemaphore(value: 0)
        remote.request(message) { data, error in
            replyData.value = data
            replyError.value = error
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 3) == .success,
              let data = replyData.value,
              let payload = try? KBWireCodec.decode(KBDetailPayload.self, from: data) else {
            throw KBCollectionError.unavailable(replyError.value?.localizedDescription
                                                ?? "daemon detail request failed")
        }
        return payload.detail
    }

    func requestDaemonServices() throws -> KBDaemonSnapshot {
        let message = try KBWireCodec.encode(KBRequestMessage(kind: .daemonServices))
        let data = try requestData(message)
        let payload = try KBWireCodec.decode(KBDaemonSnapshotPayload.self, from: data)
        return payload.snapshot
    }

    func performDaemonAction(_ request: KBDaemonActionRequest) throws -> KBDaemonActionResult {
        let message = try KBWireCodec.encode(
            KBRequestMessage(kind: .daemonAction, daemonRequest: request))
        let data = try requestData(message)
        let payload = try KBWireCodec.decode(KBDaemonActionResultPayload.self, from: data)
        return payload.result
    }

    private func requestData(_ message: Data, timeout: TimeInterval = 5) throws -> Data {
        lock.lock()
        let remote = self.remote
        lock.unlock()
        guard let remote else {
            throw KBCollectionError.unavailable("daemon is not connected")
        }
        let replyData = Box<Data>()
        let replyError = Box<NSError>()
        let semaphore = DispatchSemaphore(value: 0)
        remote.request(message) { data, error in
            replyData.value = data
            replyError.value = error
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success,
              let data = replyData.value else {
            throw KBCollectionError.unavailable(replyError.value?.localizedDescription
                                                ?? "daemon request timed out")
        }
        return data
    }

    func requestSnapshot() throws -> KBCollectionSnapshot {
        lock.lock()
        let remote = self.remote
        lock.unlock()
        guard let remote else {
            throw KBCollectionError.unavailable("daemon is not connected")
        }
        let message = try KBWireCodec.encode(KBRequestMessage(kind: .snapshot))
        let replyData = Box<Data>()
        let semaphore = DispatchSemaphore(value: 0)
        remote.request(message) { data, _ in
            replyData.value = data
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 3) == .success,
              let data = replyData.value,
              let payload = try? KBWireCodec.decode(KBSnapshotPayload.self, from: data) else {
            throw KBCollectionError.unavailable("daemon snapshot request failed")
        }
        return payload.collection
    }

    func stop() {
        lock.lock()
        let connection = self.connection
        self.connection = nil
        self.remote = nil
        self.active = false
        lock.unlock()
        connection?.invalidate()
    }

    // MARK: - KancerberoClientXPC

    func push(_ envelope: Data) {
        guard let message = try? KBWireCodec.decode(KBWireEnvelope.self, from: envelope),
              message.kind == .snapshot,
              let payload = try? KBWireCodec.decode(KBSnapshotPayload.self, from: message.payload) else {
            return
        }
        onCollection?(payload.collection)
    }

    // MARK: - Private

    private func handleInvalidate() {
        lock.lock()
        let wasActive = active
        connection = nil
        remote = nil
        active = false
        lock.unlock()
        if wasActive {
            logger.notice("daemon connection invalidated")
            onInvalidate?()
        }
    }
}
