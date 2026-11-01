import SwiftUI

struct ActivityCard: View {
    let processesCount: Int
    let connectionsCount: Int
    let activeCount: Int
    let activeWindowSeconds: Int
    let focus: NetworkingFocus?
    let onToggle: (NetworkingFocus) -> Void

    static let cardHeight: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            HStack(spacing: 6) {
                MetricTile(
                    layout: .compact,
                    title: "Processes",
                    value: KBFormat.compactCount(processesCount),
                    icon: "square.stack.3d.up.fill",
                    tint: KBTheme.processesTint,
                    caption: "with sockets",
                    hint: "Show processes with sockets",
                    isSelected: focus == .processes,
                    valueSize: 20,
                    iconSize: 9,
                    verticalPadding: 4
                ) {
                    onToggle(.processes)
                }

                MetricTile(
                    layout: .compact,
                    title: "Connections",
                    value: KBFormat.compactCount(connectionsCount),
                    icon: "point.3.connected.trianglepath.dotted",
                    tint: KBTheme.connectionsTint,
                    caption: "total",
                    hint: "Show all connections",
                    isSelected: focus == .connections,
                    valueSize: 20,
                    iconSize: 9,
                    verticalPadding: 4
                ) {
                    onToggle(.connections)
                }

                MetricTile(
                    layout: .compact,
                    title: "Active",
                    value: KBFormat.compactCount(activeCount),
                    icon: "bolt.fill",
                    tint: KBTheme.activeTint,
                    caption: "last \(activeWindowSeconds) s",
                    hint: "Show connections that moved data in the last "
                        + "\(activeWindowSeconds) seconds",
                    isSelected: focus == .active,
                    valueSize: 20,
                    iconSize: 9,
                    verticalPadding: 4
                ) {
                    onToggle(.active)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(9)
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
        if focus == .active {
            return AnyShapeStyle(KBTheme.activeTint.opacity(0.8))
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
