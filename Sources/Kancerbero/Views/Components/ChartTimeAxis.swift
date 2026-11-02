import SwiftUI

/// Bottom time axis shared by the sparklines and the bespoke history charts:
/// `now` at the left edge and the nominal window on the right (`-30s`, `-2m`,
/// `-12h`), matching the Traffic and Disk activity charts.
struct ChartTimeAxis: View {
    var span: TimeInterval

    static let height: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Text("now")
            Spacer(minLength: 4)
            Text("-" + KBFormat.shortDuration(span))
        }
        .font(.system(size: 8))
        .foregroundStyle(.secondary.opacity(colorScheme == .dark ? 0.7 : 0.6))
        .lineLimit(1)
        .frame(height: Self.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Wraps a chart and reserves a bottom row for its time axis.
struct ChartWithTimeAxis<Content: View>: View {
    var span: TimeInterval
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 1) {
            content
            ChartTimeAxis(span: span)
        }
    }
}
