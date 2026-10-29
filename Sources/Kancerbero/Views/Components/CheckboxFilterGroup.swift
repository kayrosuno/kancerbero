import SwiftUI

/// Native multi-select facet checkboxes. Every checked value is included in
/// the filter; a group with nothing checked is handled by the caller's matcher.
struct CheckboxFilterGroup<Option: CaseIterable & Identifiable & Hashable>: View {
    let label: String
    @Binding var selection: Set<Option>
    /// Overrides `allCases` order when callers need a specific visual order.
    var options: [Option]? = nil
    let optionTitle: (Option) -> String
    /// Optional per-checkbox tooltip; falls back to the title.
    var optionHelp: ((Option) -> String?)? = nil

    init(_ label: String,
         selection: Binding<Set<Option>>,
         options: [Option]? = nil,
         optionTitle: @escaping (Option) -> String,
         optionHelp: ((Option) -> String?)? = nil) {
        self.label = label
        _selection = selection
        self.options = options
        self.optionTitle = optionTitle
        self.optionHelp = optionHelp
    }

    private var items: [Option] { options ?? Array(Option.allCases) }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            ForEach(items) { option in
                Toggle(optionTitle(option), isOn: binding(for: option))
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .help(optionHelp?(option) ?? optionTitle(option))
                    .fixedSize()
            }
        }
        .fixedSize()
    }

    private func binding(for option: Option) -> Binding<Bool> {
        Binding(
            get: { selection.contains(option) },
            set: { isOn in
                var next = selection
                if isOn {
                    next.insert(option)
                } else {
                    next.remove(option)
                }
                withAnimation(.snappy(duration: 0.2)) {
                    selection = next
                }
            }
        )
    }
}
