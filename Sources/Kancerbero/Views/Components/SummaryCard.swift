import SwiftUI

struct SummaryCard: View {
    let title: String
    let value: String
    let caption: String
    let systemImage: String
    let tint: Color
    var sparkline: [Double]? = nil
    var action: (() -> Void)? = nil
    var isSelected = false
    var filterHint: String? = nil
    var fillsHeight = false

    @State private var hovering = false

    private let sparklineHeight: CGFloat = 20

    private var isInteractive: Bool { action != nil }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { card }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title): \(value), \(caption)")
                    .accessibilityHint(filterHint ?? "Toggle filter")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                card
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(title): \(value), \(caption)")
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(KBTheme.gradient(tint))
                    )
                Spacer(minLength: 2)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }

            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let sparkline {
                if sparkline.isEmpty {
                    // Reserve the chart's height before the first sample arrives
                    // so the grid row (and everything below it) does not jump.
                    Color.clear
                        .frame(height: sparklineHeight)
                } else {
                    Sparkline(values: sparkline, tint: tint)
                        .frame(height: sparklineHeight)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity,
               maxHeight: fillsHeight ? .infinity : nil,
               alignment: fillsHeight ? .topLeading : .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.10))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? AnyShapeStyle(tint.opacity(0.9))
                        : AnyShapeStyle(LinearGradient(
                            colors: [tint.opacity(0.28), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing)),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.05),
                radius: hovering ? 12 : 6,
                y: hovering ? 5 : 2)
        .scaleEffect(hovering ? 1.012 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { value in
            guard isInteractive else { return }
            withAnimation(.snappy(duration: 0.2)) { hovering = value }
        }
    }
}
