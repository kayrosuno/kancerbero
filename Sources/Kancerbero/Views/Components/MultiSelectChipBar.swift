import SwiftUI

/// Multi-select facet chips: every pressed value is included in the filter,
/// and a group with no pressed value matches nothing.
struct MultiSelectChipBar<Option: CaseIterable & Identifiable & Hashable>: View {
    @Binding var selection: Set<Option>
    var label: String? = nil
    /// Overrides `allCases` order when callers need a specific visual order.
    var options: [Option]? = nil
    let title: (Option) -> String
    var systemImage: ((Option) -> String)? = nil
    var tint: (Option) -> Color = { _ in AppSection.daemons.tint }

    private var items: [Option] { options ?? Array(Option.allCases) }

    var body: some View {
        HStack(spacing: 6) {
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }

            HStack(spacing: 3) {
                ForEach(items) { option in
                    chip(option)
                }
            }
            .padding(3)
            .background {
                Capsule().fill(.quaternary.opacity(0.4))
            }
            .overlay {
                Capsule().strokeBorder(.quaternary.opacity(0.55), lineWidth: 1)
            }
        }
        .fixedSize()
    }

    private func chip(_ option: Option) -> some View {
        let isOn = selection.contains(option)
        let color = tint(option)

        return Button {
            var next = selection
            if isOn {
                next.remove(option)
            } else {
                next.insert(option)
            }
            withAnimation(.snappy(duration: 0.2)) {
                selection = next
            }
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage(option))
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title(option))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? color : Color.secondary)
            .background {
                if isOn {
                    Capsule().fill(color.opacity(0.18))
                }
            }
            .overlay {
                Capsule().strokeBorder(
                    isOn ? color.opacity(0.85) : Color.secondary.opacity(0.18),
                    lineWidth: 1
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(option))
        .accessibilityHint(isOn ? "Remove from filter" : "Add to filter")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
