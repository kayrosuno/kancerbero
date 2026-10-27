import Foundation
import os
import KancerberoFilterContract

private let xpcLogger = Logger(subsystem: "uno.kayros.kancerbero.filter", category: "xpc")

/// Client side of the extension's Mach service. The extension is the server, so
/// the app connects with `.privileged` (global namespace) and registers an
/// exported object to receive pushes.
@MainActor
final class FilterXPCClient {
    private var connection: NSXPCConnection?
    private var proxy: FilterClientProxy?
    private var onPush: (FilterPush) -> Void = { _ in }
    private var onConnectionChange: (Bool) -> Void = { _ in }

    private(set) var isConnected = false

    func configure(onPush: @escaping (FilterPush) -> Void,
                   onConnectionChange: @escaping (Bool) -> Void) {
        self.onPush = onPush
        self.onConnectionChange = onConnectionChange
    }

    func connect() async -> Bool {
        disconnect()

        let connection = NSXPCConnection(machServiceName: FilterXPCNames.machService,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: KancerberoFilterXPC.self)
        connection.exportedInterface = NSXPCInterface(with: KancerberoFilterClientXPC.self)

        let proxy = FilterClientProxy { [weak self] data in
            Task { @MainActor in self?.handlePush(data) }
        }
        connection.exportedObject = proxy
        // These blocks run on the connection's private queue. Annotating them
        // @Sendable keeps them nonisolated; they must not touch actor state
        // directly, only hop through Task { @MainActor in … }.
        let onInvalidate: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.markDisconnected() }
        }
        connection.invalidationHandler = onInvalidate
        connection.interruptionHandler = onInvalidate
        connection.resume()

        self.connection = connection
        self.proxy = proxy

        let hello = FilterCodec.envelope(.hello, value: FilterHello())
        guard let reply = await request(hello),
              let envelope = try? FilterCodec.decodeEnvelope(reply),
              let ack = try? FilterCodec.decodePayload(FilterAck.self, from: envelope),
              ack.ok else {
            disconnect()
            return false
        }

        isConnected = true
        onConnectionChange(true)
        return true
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
        proxy = nil
        if isConnected {
            isConnected = false
            onConnectionChange(false)
        }
    }

    func request(_ envelope: Data, timeout: TimeInterval = 3) async -> Data? {
        guard let connection else { return nil }
        return await withCheckedContinuation { continuation in
            let box = ReplyBox(continuation)
            // NSXPCConnection redeclares this selector without NS_SWIFT_SENDABLE
            // (NSXPCConnection.h), so an inline closure is inferred @MainActor
            // and traps on the connection's private queue when the send fails.
            // A typed @Sendable value stays nonisolated.
            let errorHandler: @Sendable (Error) -> Void = { error in
                xpcLogger.error("XPC request failed: \(error.localizedDescription, privacy: .public)")
                box.resume(nil)
            }
            let replyHandler: @Sendable (Data) -> Void = { reply in
                box.resume(reply)
            }
            guard let remote = connection.remoteObjectProxyWithErrorHandler(errorHandler)
                    as? KancerberoFilterXPC else {
                box.resume(nil)
                return
            }
            remote.send(envelope, reply: replyHandler)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                box.resume(nil)
            }
        }
    }

    // MARK: - Push

    private func handlePush(_ data: Data) {
        guard let envelope = try? FilterCodec.decodeEnvelope(data),
              envelope.kind == .push,
              let push = try? FilterCodec.decodePayload(FilterPush.self, from: envelope) else {
            return
        }
        onPush(push)
    }

    private func markDisconnected() {
        connection = nil
        proxy = nil
        guard isConnected else { return }
        isConnected = false
        onConnectionChange(false)
    }
}

private final class FilterClientProxy: NSObject, KancerberoFilterClientXPC, @unchecked Sendable {
    private let onReceive: @Sendable (Data) -> Void

    init(onReceive: @escaping @Sendable (Data) -> Void) {
        self.onReceive = onReceive
    }

    func receive(_ envelope: Data) {
        onReceive(envelope)
    }
}

private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var finished = false

    init(_ continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
    }

    func resume(_ data: Data?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: data)
    }
}
