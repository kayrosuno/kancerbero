import AppKit
import Foundation
import NetworkExtension
import Observation
import Security
import SystemExtensions
import os
import KancerberoFilterContract

private let filterLog = Logger(subsystem: "uno.kayros.kancerbero.filter", category: "extension")

/// One-shot continuation used by the NEFilterManager timeout: the callback and
/// the deadline may both fire, but only the first one resumes the await.
private final class FilterResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Void, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

/// Owns the system-extension lifecycle and the `NEFilterManager` configuration.
/// The extension itself runs as root; the container app only installs,
/// approves, enables and disables it.
@MainActor
@Observable
final class FilterController: NSObject {
    enum State: Equatable {
        case unsupported
        case notInstalled
        case requiresApproval
        case activating
        case disabled
        case enabled
        case failed(String)

        var title: String {
            switch self {
            case .unsupported: return "Unsupported build"
            case .notInstalled: return "Not installed"
            case .requiresApproval: return "Approval required"
            case .activating: return "Activating…"
            case .disabled: return "Disabled"
            case .enabled: return "Enabled"
            case .failed: return "Failed"
            }
        }

        var isEnabled: Bool { self == .enabled }
    }

    private(set) var state: State = .unsupported
    private(set) var lastError: String?
    /// Raw `OSSystemExtensionError` details for the last failure, shown as
    /// technical details and included in the copied diagnostics.
    private(set) var lastErrorDetail: String?
    /// True while an activation request is in flight, including background repair.
    private(set) var isActivating = false

    var isEnabled: Bool { state.isEnabled }
    private let delegate = FilterExtensionDelegate()
    private var requests: [OSSystemExtensionRequest] = []
    private var activationPending = false
    private var enableAfterActivation = false

    override init() {
        super.init()
        delegate.controller = self
    }

    private var extensionURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions", isDirectory: true)
            .appendingPathComponent("\(FilterXPCNames.extensionBundleIdentifier).systemextension",
                                    isDirectory: true)
    }

    /// True when this build carries the restricted entitlements and embeds the
    /// system extension, i.e. it can actually host the filter.
    var isSupported: Bool {
        FileManager.default.fileExists(atPath: extensionURL.path) && hasSystemExtensionEntitlement
    }

    /// True for Apple Development/ad-hoc builds. macOS refuses to activate a
    /// system extension from those unless developer mode is on, and on current
    /// macOS `systemextensionsctl developer on` requires SIP to be disabled.
    var isDevelopmentSigned: Bool {
        (copyEntitlement("com.apple.security.get-task-allow") as? Bool) == true
    }

    /// Extra explanation rendered next to a failed activation.
    var failureGuidance: String? {
        guard case .failed = state, isDevelopmentSigned else { return nil }
        return Self.developmentBuildGuidance
    }

    private static let developmentBuildGuidance = """
        This is a development-signed build (get-task-allow). With SIP enabled macOS only \
        activates network system extensions from a Developer ID-signed, notarized app in \
        /Applications. Build with scripts/build-release.sh, notarize with scripts/notarize.sh \
        and install with scripts/install-app.sh. `systemextensionsctl developer on` requires \
        SIP to be disabled.
        """

    var diagnostics: String {
        [
            "app: \(Bundle.main.bundleURL.path)",
            "extension: \(extensionURL.path) (exists: \(FileManager.default.fileExists(atPath: extensionURL.path)))",
            "identifier: \(FilterXPCNames.extensionBundleIdentifier)",
            "state: \(state.title)",
            "supported: \(isSupported)",
            "developmentSigned: \(isDevelopmentSigned)",
            "systemExtensionEntitlement: \(hasSystemExtensionEntitlement)",
            "lastError: \(lastError ?? "—")",
            "lastErrorDetail: \(lastErrorDetail ?? "—")",
            #"hint: log show --last 5m --predicate 'process == "sysextd"' --info --debug"#
        ].joined(separator: "\n")
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }

    func refresh() async {
        guard isSupported else {
            state = .unsupported
            return
        }
        do {
            let manager = NEFilterManager.shared()
            try await load(manager)
            state = manager.isEnabled ? .enabled : .disabled
            lastError = nil
            lastErrorDetail = nil
        } catch {
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }

    /// Submits the activation request. macOS may ask the user for approval in
    /// System Settings; `enable()` runs automatically once it completes.
    func installAndEnable() {
        submitActivation(enableWhenDone: true)
    }

    /// Re-submits activation without enabling the filter. Used at launch when
    /// `NEFilterManager.isEnabled` is true but the extension was never installed
    /// (orphan configuration) or was disabled in Settings.
    func ensureInstalled() {
        submitActivation(enableWhenDone: false)
    }

    private func submitActivation(enableWhenDone: Bool) {
        guard isSupported else {
            state = .unsupported
            return
        }
        // A request may already be awaiting approval. Keep it and upgrade its
        // intent instead of dropping the user's Enable action.
        if activationPending {
            enableAfterActivation = enableAfterActivation || enableWhenDone
            return
        }
        enableAfterActivation = enableWhenDone
        activationPending = true
        isActivating = true
        // Repairing an already-enabled configuration must keep `.enabled` so
        // FilterModel's reconnect loop keeps running.
        if !state.isEnabled {
            state = .activating
        }
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: FilterXPCNames.extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = delegate
        requests.append(request)
        OSSystemExtensionManager.shared.submitRequest(request)
        filterLog.notice("submitted activation request, enableWhenDone=\(enableWhenDone, privacy: .public)")
    }

    func enable() async {
        guard isSupported else {
            state = .unsupported
            return
        }
        do {
            let manager = NEFilterManager.shared()
            try await load(manager)
            if manager.providerConfiguration == nil {
                let configuration = NEFilterProviderConfiguration()
                configuration.filterSockets = true
                manager.providerConfiguration = configuration
            }
            manager.localizedDescription = "Kancerbero Network Filter"
            manager.grade = .firewall
            manager.isEnabled = true
            try await save(manager)
            state = .enabled
            lastError = nil
            lastErrorDetail = nil
        } catch {
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }

    func disable() async {
        enableAfterActivation = false
        do {
            let manager = NEFilterManager.shared()
            try await load(manager)
            manager.isEnabled = false
            try await save(manager)
            try? await remove(manager)
            state = .disabled
            lastError = nil
            lastErrorDetail = nil
        } catch {
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }

    /// Removes both the filter configuration and the system extension.
    func uninstall() async {
        await disable()
        guard isSupported else { return }
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: FilterXPCNames.extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = delegate
        requests.append(request)
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: - Delegate callbacks

    fileprivate func handleNeedsApproval() {
        isActivating = false
        state = .requiresApproval
        filterLog.notice("system extension requires user approval")
    }

    fileprivate func handleFinished(_ result: OSSystemExtensionRequest.Result) {
        requests.removeAll()
        activationPending = false
        isActivating = false
        switch result {
        case .completed:
            if enableAfterActivation {
                enableAfterActivation = false
                Task { await enable() }
            } else {
                Task { await refresh() }
            }
        case .willCompleteAfterReboot:
            enableAfterActivation = false
            state = .requiresApproval
            lastError = "The filter extension will be active after the next reboot."
        @unknown default:
            state = .failed("Unknown system extension result")
        }
    }

    fileprivate func handleFailure(_ failure: FilterFailure) {
        requests.removeAll()
        activationPending = false
        isActivating = false
        enableAfterActivation = false
        let message = failure.userMessage()
        lastError = message
        lastErrorDetail = failure.rawDescription
        state = .failed(message)
        filterLog.error("system extension request failed: \(failure.rawDescription, privacy: .public)")
    }

    // MARK: - Entitlements

    private func copyEntitlement(_ name: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, name as CFString, nil)
    }

    private var hasSystemExtensionEntitlement: Bool {
        (copyEntitlement("com.apple.developer.system-extension.install") as? Bool) == true
    }

    // MARK: - Async wrappers

    /// The NetworkExtension daemon may stop answering (extension wedged,
    /// system dialog pending…). Without a deadline the awaiting UI would stay
    /// disabled forever, as happened with the approval sheet's Disable filter.
    private func withFilterTimeout(
        timeout: TimeInterval = 5,
        _ operation: @escaping (@escaping (Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = FilterResumeOnce(continuation)
            operation { error in
                if let error {
                    once.resume(.failure(error))
                } else {
                    once.resume(.success(()))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(.failure(NSError(
                    domain: "uno.kayros.kancerbero.filter",
                    code: 15,
                    userInfo: [NSLocalizedDescriptionKey:
                                "The network filter did not respond in time."])))
            }
        }
    }

    private func load(_ manager: NEFilterManager) async throws {
        try await withFilterTimeout { completion in
            manager.loadFromPreferences(completionHandler: completion)
        }
    }

    private func save(_ manager: NEFilterManager) async throws {
        try await withFilterTimeout { completion in
            manager.saveToPreferences(completionHandler: completion)
        }
    }

    private func remove(_ manager: NEFilterManager) async throws {
        try await withFilterTimeout { completion in
            manager.removeFromPreferences(completionHandler: completion)
        }
    }
}

/// `OSSystemExtensionRequestDelegate` is a nonisolated Objective-C protocol;
/// keeping it in its own object avoids crossing the main actor boundary.
private final class FilterExtensionDelegate: NSObject,
                                           OSSystemExtensionRequestDelegate,
                                           @unchecked Sendable {
    weak var controller: FilterController?

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension extensionProperties: OSSystemExtensionProperties)
        -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            controller?.handleNeedsApproval()
        }
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            controller?.handleFinished(result)
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let failure = FilterFailure(error)
        Task { @MainActor in
            controller?.handleFailure(failure)
        }
    }
}

/// Snapshot of an `OSSystemExtensionRequest` failure. `Error`/`NSError` are not
/// `Sendable`, so the delegate captures the fields it needs before hopping to
/// the main actor, and logs the raw values for `log show`.
private struct FilterFailure: Sendable {
    let domain: String
    let code: Int
    let systemExtensionCode: Int?
    let localizedDescription: String
    let failureReason: String?
    let underlyingDescription: String?

    init(_ error: Error) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        systemExtensionCode = (error as? OSSystemExtensionError)?.code.rawValue
        localizedDescription = nsError.localizedDescription
        failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
        underlyingDescription = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?
            .localizedDescription
    }

    var rawDescription: String {
        var parts = ["domain=\(domain)", "code=\(code)"]
        if let systemExtensionCode {
            parts.append("sysextCode=\(systemExtensionCode)")
        }
        parts.append("description=\(localizedDescription)")
        if let failureReason {
            parts.append("reason=\(failureReason)")
        }
        if let underlyingDescription {
            parts.append("underlying=\(underlyingDescription)")
        }
        return parts.joined(separator: " ")
    }

    /// Maps `OSSystemExtensionError.Code` to an actionable message. Runs
    /// nonisolated; only the resulting String crosses to the main actor.
    func userMessage() -> String {
        guard let systemExtensionCode,
              let code = OSSystemExtensionError.Code(rawValue: systemExtensionCode) else {
            return localizedDescription
        }

        let message: String
        switch code {
        case .missingEntitlement:
            message = "Kancerbero is missing the system-extension entitlement. Sign it with a Developer ID provisioning profile that grants com.apple.developer.system-extension.install."
        case .unsupportedParentBundleLocation:
            message = "macOS only activates system extensions from an application in /Applications. Move Kancerbero.app there and try again."
        case .extensionNotFound:
            message = "macOS could not realize the filter system extension. The bundle is embedded, so check that it is named <bundle identifier>.systemextension, signed with Developer ID and notarized; sysextd logs the precise reason (`log show --last 5m --predicate 'process == \"sysextd\"'`)."
        case .codeSignatureInvalid:
            message = "The filter extension signature is invalid. Sign the app and the extension with the same Developer ID certificate and provisioning profiles."
        case .validationFailed:
            message = "macOS rejected the filter extension during validation. Check that the Developer ID profile grants content-filter-provider-systemextension, and that NEMachServiceName starts with an App Group listed in com.apple.security.application-groups."
        case .forbiddenBySystemPolicy:
            message = "A system policy is blocking the filter extension. Developer ID builds must also be notarized."
        case .authorizationRequired:
            message = "Open System Settings → General → Login Items & Extensions → Network Extensions and turn on Kancerbero Filter, then try again."
        case .requestCanceled:
            message = "The system-extension request was canceled. Try again."
        case .requestSuperseded:
            message = "Another system-extension request replaced this one. Try again."
        case .extensionMissingIdentifier, .duplicateExtensionIdentifer, .unknownExtensionCategory:
            message = "The embedded filter extension is invalid: \(localizedDescription)"
        case .unknown:
            message = localizedDescription
        @unknown default:
            message = localizedDescription
        }
        return message
    }
}
