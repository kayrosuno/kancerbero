import SwiftUI

/// Units for the traffic graph. `bits` consumes byte-rate histories and
/// `packets` consumes packet-rate histories; only the chart changes.
enum TrafficGraphMode: String, CaseIterable, Identifiable, Equatable {
    case bits
    case packets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bits: return "Bits"
        case .packets: return "Packets"
        }
    }

    /// Formats a value in the mode's stored unit (bytes/s for bits,
    /// packets/s for packets).
    func format(_ value: Double) -> String {
        switch self {
        case .bits: return KBFormat.bitRate(value)
        case .packets: return KBFormat.packetsRate(value)
        }
    }
}

/// Traffic history as a mirrored bar equalizer: upload bars above the centre
/// line and download bars below it, on a shared scale.
struct TrafficChart: View {
    let download: [Double]
    let upload: [Double]
    let focus: NetworkingFocus?
    var sampleInterval: TimeInterval = 1
    var mode: TrafficGraphMode = .bits
    var downloadTint: Color = KBTheme.downloadTint
    var uploadTint: Color = KBTheme.uploadTint

    var body: some View {
        MirroredBarChart(
            top: upload,
            bottom: download,
            format: mode.format,
            topTint: uploadTint,
            bottomTint: downloadTint,
            topLabel: "Upload",
            bottomLabel: "Download",
            topOpacity: focus == .download ? 0.25 : 1,
            bottomOpacity: focus == .upload ? 0.25 : 1,
            fallbackCeiling: mode == .bits ? 125 : 10,
            sampleInterval: sampleInterval,
            accessibilityLabel: "Traffic history, \(mode.title.lowercased())",
            accessibilityValue: accessibilityValue
        )
    }

    private var accessibilityValue: String {
        let peak = max(max(download.max() ?? 0, upload.max() ?? 0), 0)
        let windowText = KBFormat.shortDuration(nominalSpan)
        return "Peak \(mode.format(peak)) over the last \(windowText). " +
            "Upload \(mode.format(upload.last ?? 0)), " +
            "download \(mode.format(download.last ?? 0))"
    }

    /// Nominal duration represented by the fixed 60-slot window.
    private var nominalSpan: TimeInterval {
        max(sampleInterval, 0.1) * Double(MirroredBarChart.window)
    }
}
