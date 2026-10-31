import SwiftUI

/// Temperature text with the shared thermal colour band. Used by the Cores
/// card rows and the package badge so both stay consistent.
struct TemperatureLabel: View {
    let celsius: Double?
    var fontSize: CGFloat = 9
    var compact = true
    var width: CGFloat? = nil
    var weight: Font.Weight = .medium

    static func tint(for celsius: Double?) -> Color {
        KBTheme.temperatureTint(celsius)
    }

    var body: some View {
        Text(KBFormat.temperature(celsius, compact: compact))
            .font(.system(size: fontSize, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Self.tint(for: celsius))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: width, alignment: .trailing)
            .help(celsius.map { KBFormat.temperature($0) }
                  ?? "Temperature unavailable on this Mac")
    }
}
