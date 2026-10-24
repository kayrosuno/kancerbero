import Foundation

@objc public protocol KancerberoDaemonXPC {
    func handshake(_ message: Data, reply: @escaping (Data) -> Void)
    func subscribe(_ config: Data, reply: @escaping (Data?, NSError?) -> Void)
    func request(_ message: Data, reply: @escaping (Data?, NSError?) -> Void)
    func unsubscribe()
}

@objc public protocol KancerberoClientXPC {
    func push(_ envelope: Data)
}

public enum KancerberoXPCNames {
    public static let machService = "com.alejandro.kancerbero.daemon"
}
