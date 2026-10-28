import Foundation

/// The extension publishes exactly one Mach service (declared through
/// `NEMachServiceName` in its Info.plist). The app is the client, so the
/// extension is the server: this inverts the usual app-daemon XPC direction.
@objc public protocol KancerberoFilterXPC {
    /// Sends an encoded `FilterEnvelope`; the reply is another encoded envelope.
    func send(_ envelope: Data, reply: @escaping (Data) -> Void)
}

/// Callback interface implemented by the app. The extension pushes pending
/// approvals, flow statistics and status through it.
@objc public protocol KancerberoFilterClientXPC {
    func receive(_ envelope: Data)
}

public enum FilterXPCNames {
    /// `NEMachServiceName` of a sandboxed network system extension must be
    /// prefixed with one of its App Groups, or the Network Extension category
    /// validation rejects the extension. Must match `NEMachServiceName` in the
    /// extension's Info.plist and `KBFilterMachService` in the app's Info.plist.
    public static let appGroup = "group.uno.kayros.kancerbero"
    public static let machService = "group.uno.kayros.kancerbero.filter"
    public static let extensionBundleIdentifier = "uno.kayros.kancerbero.filter"
    public static let teamIdentifier = "AK37TK8X2Y"

    /// Code-signing requirement used by the extension to reject peers that are
    /// not the Kancerbero app signed by this team.
    public static let clientRequirement =
        "identifier \"uno.kayros.kancerbero\" and anchor apple generic"
        + " and certificate leaf[subject.OU] = \"AK37TK8X2Y\""
}
