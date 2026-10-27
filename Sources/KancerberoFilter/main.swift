import Foundation
import NetworkExtension

// System extensions that host Network Extension providers must enter this mode
// before the provider is instantiated by the system.
//
// Top-level code is implicitly @MainActor, so an autoreleasepool closure written
// here gets a dynamic MainActor assertion. A plain global function is
// nonisolated and still runs synchronously on the main thread.
func startExtension() {
    autoreleasepool {
        NEProvider.startSystemExtensionMode()
    }
}

startExtension()

dispatchMain()
