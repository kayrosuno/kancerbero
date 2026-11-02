import SwiftUI

/// Unit/mode option shared by the Traffic and Disk activity selectors.
protocol GraphModeOption: CaseIterable, Identifiable, Hashable {
    var title: String { get }
}

extension TrafficGraphMode: GraphModeOption {}
extension DiskIOGraphMode: GraphModeOption {}

/// Bits/Packets selector for the Traffic header. Uses the system Liquid Glass
/// capsule on macOS 26 and later; older systems keep the native segmented
/// control used by the toolbar interval.
struct TrafficModeSelector: View {
    @Binding var mode: TrafficGraphMode

    var body: some View {
        GraphModeSelector(mode: $mode,
                          accessibilityLabel: "Traffic graph units",
                          help: "Show the graph in bits per second or packets per second",
                          legacyWidth: 124)
    }
}

/// Capsule selector shared by the Traffic units and the Disk activity graph
/// type. Liquid Glass on macOS 26 and later; segmented control before that.
struct GraphModeSelector<Mode: GraphModeOption>: View {
    @Binding var mode: Mode
    var accessibilityLabel: String
    var help: String
    var legacyWidth: CGFloat = 124

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassModeSelector(mode: $mode,
                              accessibilityLabel: accessibilityLabel,
                              help: help)
                .fixedSize()
        } else {
            Picker(accessibilityLabel, selection: $mode) {
                ForEach(Array(Mode.allCases)) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: legacyWidth)
            .accessibilityLabel(accessibilityLabel)
            .help(help)
        }
    }
}

@available(macOS 26.0, *)
private struct GlassModeSelector<Mode: GraphModeOption>: View {
    @Binding var mode: Mode
    var accessibilityLabel: String
    var help: String

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(Mode.allCases)) { option in
                    segment(option)
                }
            }
            .padding(2)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }

    private func segment(_ value: Mode) -> some View {
        let selected = mode == value

        return Button {
            withAnimation(.snappy(duration: 0.2)) { mode = value }
        } label: {
            Text(value.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 18)
                .background {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.13))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10),
                                                  lineWidth: 0.5)
                            }
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(help)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
