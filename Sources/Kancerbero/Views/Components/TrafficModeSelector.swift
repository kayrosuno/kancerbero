import SwiftUI

/// Bits/Packets selector for the Traffic header. Uses the system Liquid Glass
/// capsule on macOS 26 and later; older systems keep the native segmented
/// control used by the toolbar interval.
struct TrafficModeSelector: View {
    @Binding var mode: TrafficGraphMode

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassTrafficModeSelector(mode: $mode)
        } else {
            Picker("Traffic graph units", selection: $mode) {
                ForEach(TrafficGraphMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 124)
            .accessibilityLabel("Traffic graph units")
            .help("Show the graph in bits per second or packets per second")
        }
    }
}

@available(macOS 26.0, *)
private struct GlassTrafficModeSelector: View {
    @Binding var mode: TrafficGraphMode

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                segment(.bits)
                segment(.packets)
            }
            .padding(2)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Traffic graph units")
        .help("Show the graph in bits per second or packets per second")
    }

    private func segment(_ value: TrafficGraphMode) -> some View {
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
        .accessibilityHint("Show the graph in "
                           + (value == .bits ? "bits" : "packets") + " per second")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
