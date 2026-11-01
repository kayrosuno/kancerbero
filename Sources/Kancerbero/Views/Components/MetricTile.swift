import SwiftUI

enum MetricTileLayout {
    case inline
    case stacked
    /// Narrow variant for cards that must fit three metrics side by side:
    /// no icon or checkmark, tighter padding and a smaller value.
    case compact
}

struct MetricTile: View {
    let layout: MetricTileLayout
    let title: String
    let value: String
    let icon: String
    let tint: Color
    var caption: String? = nil
    var hint: String = ""
    var isSelected = false
    var valueSize: CGFloat = 18
    /// Reserved width for the value so it does not resize (and rescale) when
    /// the text length changes.
    var valueMinWidth: CGFloat? = nil
    /// Set to false to keep the value at `valueSize` instead of shrinking it.
    var valueScales = true
    var iconSize: CGFloat = 11
    var verticalPadding: CGFloat = 4
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, layout == .compact ? 5 : 8)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(isSelected ? 0.14 : 0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? tint.opacity(0.9) : tint.opacity(0.18),
                                      lineWidth: isSelected ? 1.5 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(hint)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .inline:
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    valueText
                }
                Spacer(minLength: 0)
            }
        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 2)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                        .opacity(isSelected ? 1 : 0)
                        .frame(width: 12)
                }
                valueText
                if let caption {
                    Text(caption)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
        case .compact:
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .frame(minWidth: valueMinWidth ?? 0, alignment: .leading)
                    .minimumScaleFactor(valueScales ? 0.65 : 1)
                if let caption {
                    Text(caption)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var valueText: some View {
        Text(value)
            .font(.system(size: valueSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .frame(minWidth: valueMinWidth ?? 0, alignment: .leading)
            .minimumScaleFactor(valueScales ? 0.65 : 1)
    }

    private var accessibilityText: String {
        if let caption {
            return "\(title): \(value), \(caption)"
        }
        return "\(title): \(value)"
    }
}
