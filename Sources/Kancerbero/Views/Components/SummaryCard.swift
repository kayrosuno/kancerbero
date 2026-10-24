import SwiftUI

struct SummaryCard: View {
    let title: String
    let value: String
    let caption: String
    let systemImage: String
    let tint: Color
    var sparkline: [Double] = []

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(KBTheme.gradient(tint))
                    )
                Spacer(minLength: 4)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if !sparkline.isEmpty {
                Sparkline(values: sparkline, tint: tint)
                    .frame(height: 30)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [tint.opacity(0.28), Color.white.opacity(0.04)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.05),
                radius: hovering ? 12 : 6,
                y: hovering ? 5 : 2)
        .scaleEffect(hovering ? 1.012 : 1)
        .onHover { value in
            withAnimation(.snappy(duration: 0.2)) { hovering = value }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value), \(caption)")
    }
}
