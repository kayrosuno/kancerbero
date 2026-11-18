#if APP_STORE

import Foundation
import Observation

/// App Store builds receive updates through the Mac App Store. The stub keeps
/// the same API as the Sparkle-backed model.
@MainActor
@Observable
final class UpdaterModel {
    private(set) var canCheckForUpdates = false
    private(set) var statusText = "Updates are delivered by the Mac App Store."
    private(set) var lastError: String?
    private(set) var updateAvailable: String?
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
    private(set) var updateCheckInterval: TimeInterval = 86_400
    private(set) var isEnabled = false

    var allowsAutomaticUpdates: Bool { false }

    init() {}

    func checkForUpdates() {}
    func setAutomaticallyChecksForUpdates(_ value: Bool) {}
    func setAutomaticallyDownloadsUpdates(_ value: Bool) {}
    func setUpdateCheckInterval(_ value: TimeInterval) {}
    func noteUpdateFound(_ version: String) {}
    func noteUpToDate() {}
    func noteFailure(_ error: Error?) {}
}

#else

import Combine
import Foundation
import Sparkle
import SwiftUI

/// Owns Sparkle for the lifetime of the app. Sparkle replaces the whole bundle
/// and relaunches the app; the daemon and system extension are reconciled by
/// `AppModel` and `FilterModel` on the next launch.
@MainActor
@Observable
final class UpdaterModel {
    private(set) var canCheckForUpdates = false
    private(set) var statusText = "Idle"
    private(set) var lastError: String?
    private(set) var updateAvailable: String?
    private(set) var automaticallyChecksForUpdates = true
    private(set) var automaticallyDownloadsUpdates = false
    private(set) var updateCheckInterval: TimeInterval = 86400
    private(set) var isEnabled = true

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let delegate: UpdaterDelegate
    @ObservationIgnored private var observation: AnyCancellable?

    var allowsAutomaticUpdates: Bool { controller.updater.allowsAutomaticUpdates }

    init() {
        let delegate = UpdaterDelegate()
        self.delegate = delegate

        // Screenshot automation must never trigger network activity. Debug
        // builds only start the updater when a test feed is explicitly given.
        let testFeed = ProcessInfo.processInfo.environment["KANCERBERO_UPDATE_FEED"]
        let isScreenshot = CommandLine.arguments.contains("--screenshot")
        let shouldStart = !isScreenshot && (!Self.isDebugBuild || testFeed != nil)
        self.isEnabled = shouldStart
        self.controller = SPUStandardUpdaterController(
            startingUpdater: shouldStart,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        delegate.model = self

        let updater = controller.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        updateCheckInterval = updater.updateCheckInterval
        canCheckForUpdates = updater.canCheckForUpdates
        observation = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    func checkForUpdates() {
        guard isEnabled, canCheckForUpdates else { return }
        statusText = "Checking for updates…"
        lastError = nil
        controller.updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        controller.updater.automaticallyChecksForUpdates = value
        automaticallyChecksForUpdates = value
    }

    func setAutomaticallyDownloadsUpdates(_ value: Bool) {
        guard controller.updater.allowsAutomaticUpdates else { return }
        controller.updater.automaticallyDownloadsUpdates = value
        automaticallyDownloadsUpdates = value
    }

    func setUpdateCheckInterval(_ value: TimeInterval) {
        let clamped = max(3600, value)
        controller.updater.updateCheckInterval = clamped
        updateCheckInterval = clamped
    }

    func noteUpdateFound(_ version: String) {
        updateAvailable = version
        statusText = "Update available: \(version)"
        lastError = nil
    }

    func noteUpToDate() {
        updateAvailable = nil
        statusText = "You're up to date."
        lastError = nil
    }

    func noteFailure(_ error: Error?) {
        lastError = error?.localizedDescription
        statusText = error == nil ? "Unable to check for updates." : "Unable to check for updates."
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

@MainActor
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    weak var model: UpdaterModel?

    /// Debug-only override so the update flow can be tested against a local or
    /// prerelease feed without touching the production Info.plist.
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["KANCERBERO_UPDATE_FEED"]
        #else
        return nil
        #endif
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        model?.noteUpdateFound(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        model?.noteUpToDate()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: Error?) {
        guard let error else { return }
        model?.noteFailure(error)
    }
}

#endif
