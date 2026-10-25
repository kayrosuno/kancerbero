import SwiftUI

/// Compact optional-facet picker: "All" plus every case of `Option`.
struct OptionFilterPicker<Option: CaseIterable & Identifiable & Hashable>: View {
    let label: String
    @Binding var selection: Option?
    let optionTitle: (Option) -> String

    init(_ label: String,
         selection: Binding<Option?>,
         optionTitle: @escaping (Option) -> String) {
        self.label = label
        _selection = selection
        self.optionTitle = optionTitle
    }

    var body: some View {
        Picker(label, selection: $selection) {
            Text("All").tag(Optional<Option>.none)
            ForEach(Array(Option.allCases)) { option in
                Text(optionTitle(option)).tag(Optional(option))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }
}
