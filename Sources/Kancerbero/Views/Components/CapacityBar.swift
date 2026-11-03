import SwiftUI

struct CapacityBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 6
    /// Optional hairline around the track for very light tints.
    var outline: Color? = nil
    var accessibilityLabel = "Capacity used"

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.35))
                Capsule()
                    .fill(KBTheme.gradient(tint))
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .frame(height: height)
        .overlay {
            if let outline {
                Capsule().strokeBorder(outline, lineWidth: 0.5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(KBFormat.percent(fraction))
    }
}
