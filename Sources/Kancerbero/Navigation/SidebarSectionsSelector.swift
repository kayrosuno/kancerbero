import SwiftUI

/// Section switcher shown in the title bar while the sidebar is collapsed.
/// The segmented Picker keeps the native control; the surrounding capsule is
/// Liquid Glass on macOS 26+ and a thin-material capsule before that.
struct SidebarSectionsSelector: View {
    let currentSection: AppSection
    let onSelect: (AppSection) -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                picker
                    .padding(2)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
        } else {
            picker
                .padding(2)
                .background(.ultraThinMaterial,
                            in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08),
                                      lineWidth: 0.5)
                }
        }
    }

    private var picker: some View {
        Picker("Section", selection: Binding(
            get: { currentSection },
            set: { onSelect($0) }
        )) {
            ForEach(AppSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(section.title)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 294)
        .accessibilityLabel("Section")
        .help("Switch section")
    }
}
