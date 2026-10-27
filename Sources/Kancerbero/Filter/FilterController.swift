import Foundation
import NetworkExtension
import Observation
import Security
import SystemExtensions
import os
import KancerberoFilterContract

private let filterLog = Logger(subsystem: "uno.kayros.kancerbero.filter", category: "extension")

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
            .appendingPathComponent("KancerberoFilter.systemextension", isDirectory: true)
    }

    /// True when this build carries the restricted entitlements and embeds the
    /// system extension, i.e. it can actually host the filter.
    var isSupported: Bool {
        FileManager.default.fileExists(atPath: extensionURL.path) && hasSystemExtensionEntitlement
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
            manager.localizedDescription = "Kancerbero network filter"
            manager.grade = .firewall
            manager.isEnabled = true
            try await save(manager)
            state = .enabled
            lastError = nil
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

    fileprivate func handleFailure(_ message: String) {
        requests.removeAll()
        activationPending = false
        isActivating = false
        enableAfterActivation = false
        lastError = message
        state = .failed(message)
        filterLog.error("system extension request failed: \(message, privacy: .public)")
    }

    // MARK: - Entitlements

    private var hasSystemExtensionEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.system-extension.install" as CFString,
            nil
        )
        return (value as? Bool) == true
    }

    // MARK: - Async wrappers

    private func load(_ manager: NEFilterManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func save(_ manager: NEFilterManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func remove(_ manager: NEFilterManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
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
        let message = Self.message(for: error)
        Task { @MainActor in
            controller?.handleFailure(message)
        }
    }

    /// Maps `OSSystemExtensionError.Code` to an actionable message. Runs
    /// nonisolated; only the resulting String crosses to the main actor.
    private static func message(for error: Error) -> String {
        guard let extensionError = error as? OSSystemExtensionError else {
            return error.localizedDescription
        }
        switch extensionError.code {
        case .missingEntitlement:
            return "Kancerbero is missing the system-extension entitlement. Rebuild it with a signed Apple Development or Developer ID build."
        case .unsupportedParentBundleLocation:
            return "Move Kancerbero.app to /Applications and try again; macOS only activates system extensions from an application in /Applications."
        case .extensionNotFound:
            return "macOS could not find KancerberoFilter.systemextension inside the app bundle. Reinstall a complete signed build."
        case .codeSignatureInvalid:
            return "The filter extension signature is invalid. Rebuild and sign the app and the extension with the same team."
        case .validationFailed:
            return "macOS rejected the filter extension during validation. Check its entitlements and provisioning profile."
        case .forbiddenBySystemPolicy:
            return "A system policy is blocking the filter extension."
        case .authorizationRequired:
            return "Approve Kancerbero in System Settings → General → Login Items & Extensions → Network Extensions, then try again."
        case .requestCanceled:
            return "The system-extension request was canceled. Try again."
        case .requestSuperseded:
            return "Another system-extension request replaced this one. Try again."
        case .extensionMissingIdentifier, .duplicateExtensionIdentifer, .unknownExtensionCategory:
            return "The embedded filter extension is invalid: \(error.localizedDescription)"
        case .unknown:
            return error.localizedDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}
