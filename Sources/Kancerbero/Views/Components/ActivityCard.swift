import SwiftUI

struct ActivityCard: View {
    let connectionsCount: Int
    let processesCount: Int
    let connectionsFiltered: Bool
    let processesFiltered: Bool
    let focus: NetworkingFocus?
    let onToggle: (NetworkingFocus) -> Void

    static let cardHeight: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(KBTheme.gradient(KBTheme.connectionsTint))
                    )
                Text("Activity")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
            }
            .frame(height: 18)

            HStack(spacing: 8) {
                MetricTile(
                    layout: .stacked,
                    title: "Connections",
                    value: KBFormat.compactCount(connectionsCount),
                    icon: "point.3.connected.trianglepath.dotted",
                    tint: KBTheme.connectionsTint,
                    caption: connectionsFiltered ? "matching flows" : "active flows",
                    hint: "Show rows tied to active connections",
                    isSelected: focus == .connections,
                    valueSize: 19,
                    iconSize: 10,
                    verticalPadding: 6
                ) {
                    onToggle(.connections)
                }

                MetricTile(
                    layout: .stacked,
                    title: "Processes",
                    value: KBFormat.compactCount(processesCount),
                    icon: "square.stack.3d.up.fill",
                    tint: KBTheme.processesTint,
                    caption: processesFiltered ? "matching processes" : "with sockets",
                    hint: "Show rows attributable to processes",
                    isSelected: focus == .processes,
                    valueSize: 19,
                    iconSize: 10,
                    verticalPadding: 6
                ) {
                    onToggle(.processes)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.cardHeight)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(borderStyle, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }

    private var borderStyle: AnyShapeStyle {
        if focus == .connections {
            return AnyShapeStyle(KBTheme.connectionsTint.opacity(0.8))
        }
        if focus == .processes {
            return AnyShapeStyle(KBTheme.processesTint.opacity(0.8))
        }
        return AnyShapeStyle(LinearGradient(
            colors: [KBTheme.connectionsTint.opacity(0.32),
                     KBTheme.processesTint.opacity(0.32)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing))
    }
}
