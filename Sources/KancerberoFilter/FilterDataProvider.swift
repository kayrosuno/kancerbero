import Foundation
import NetworkExtension

/// macOS content-filter data provider. The system instantiates it from the
/// `NetworkExtension → NEProviderClasses` entry in the extension's Info.plist.
final class FilterDataProvider: NEFilterDataProvider {
    private let core = FilterCore()

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        core.start(provider: self)
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        core.stop()
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        core.handleNewFlow(flow)
    }

    override func handle(_ report: NEFilterReport) {
        guard let flow = report.flow else { return }
        core.handleReport(flowID: flow.identifier,
                          inbound: UInt64(report.bytesInboundCount),
                          outbound: UInt64(report.bytesOutboundCount),
                          closed: report.event == .flowClosed)
    }
}
