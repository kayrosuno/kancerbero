import Foundation
import KancerberoCore
import Security

enum ProcessKillAuthorizationError: LocalizedError {
    case canceled
    case denied
    case interactionNotAllowed
    case notPreauthorizable
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .canceled: return "Authorization was canceled."
        case .denied: return "Administrator authorization was denied."
        case .interactionNotAllowed: return "Administrator authorization is not available."
        case .notPreauthorizable: return "The administrator right cannot be preauthorized."
        case .status(let status): return "Authorization failed (status \(status))."
        }
    }
}

/// App-side administrator prompt plus the privileged XPC request. The
/// AuthorizationRef must stay alive until the daemon has internalized the
/// external form, so the prompt and the request run in the same scope.
enum ProcessKillClient {
    private static let rightName = "system.privilege.admin"
    private static let canNotPreAuthorize: UInt32 = 1 << 31

    static func signal(_ request: KBProcessSignalRequest,
                       client: DaemonMetricsSource,
                       processName: String) throws -> KBProcessSignalResult {
        var authRef: AuthorizationRef?
        let create = AuthorizationCreate(nil, nil, [], &authRef)
        guard create == errAuthorizationSuccess, let authRef else {
            throw ProcessKillAuthorizationError.status(create)
        }
        defer { AuthorizationFree(authRef, []) }

        let prompt = "Kancerbero needs administrator authorization to signal "
            + "\(sanitize(processName)) (PID \(request.pid))."
        var promptBytes = Array(prompt.utf8)

        return try promptBytes.withUnsafeMutableBufferPointer { buffer in
            try rightName.withCString { name in
                try "prompt".withCString { promptName in
                    var item = AuthorizationItem(name: name, valueLength: 0,
                                                 value: nil, flags: 0)
                    let promptValue = buffer.baseAddress.map { UnsafeMutableRawPointer($0) }
                    var promptItem = AuthorizationItem(name: promptName,
                                                       valueLength: buffer.count,
                                                       value: promptValue, flags: 0)

                    // Both structs store their item pointers, so the items
                    // must outlive AuthorizationCopyRights, not just init.
                    return try withUnsafeMutablePointer(to: &item) { itemPointer in
                        try withUnsafeMutablePointer(to: &promptItem) { promptPointer in
                            var rights = AuthorizationRights(count: 1,
                                                             items: itemPointer)
                            var environment = AuthorizationEnvironment(count: 1,
                                                                        items: promptPointer)

                            var authorizedPointer: UnsafeMutablePointer<AuthorizationRights>?
                            let flags: AuthorizationFlags = [
                                .interactionAllowed, .extendRights, .preAuthorize
                            ]
                            let status = AuthorizationCopyRights(
                                authRef, &rights, &environment, flags, &authorizedPointer)
                            defer {
                                if let authorizedPointer {
                                    _ = AuthorizationFreeItemSet(authorizedPointer)
                                }
                            }
                            guard status == errAuthorizationSuccess,
                                  let authorizedPointer else {
                                throw map(status)
                            }
                            let authorized = authorizedPointer.pointee
                            if authorized.count > 0, let items = authorized.items,
                               items.pointee.flags & canNotPreAuthorize != 0 {
                                throw ProcessKillAuthorizationError.notPreauthorizable
                            }

                            var form = AuthorizationExternalForm()
                            let formStatus = AuthorizationMakeExternalForm(authRef, &form)
                            guard formStatus == errAuthorizationSuccess else {
                                throw ProcessKillAuthorizationError.status(formStatus)
                            }
                            var data = withUnsafeBytes(of: &form.bytes) { Data($0) }
                            defer {
                                withUnsafeMutableBytes(of: &form.bytes) {
                                    $0.initializeMemory(as: UInt8.self, repeating: 0)
                                }
                                data.resetBytes(in: 0..<data.count)
                            }

                            var outgoing = request
                            outgoing.authorizationExternalForm = data
                            return try client.signalProcess(outgoing)
                        }
                    }
                }
            }
        }
    }

    private static func map(_ status: OSStatus) -> ProcessKillAuthorizationError {
        switch status {
        case -60006: return .canceled
        case -60005: return .denied
        case -60007: return .interactionNotAllowed
        default: return .status(status)
        }
    }

    private static func sanitize(_ name: String) -> String {
        let cleaned = name.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        let text = String(String.UnicodeScalarView(cleaned))
        return String(text.prefix(120))
    }
}
