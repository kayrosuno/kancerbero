import SwiftUI

struct PillTabBar<Item: PillTabItem>: View {
    @Binding var selection: Item
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Item.allCases)) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .foregroundStyle(selection == tab ? Color.white : Color.secondary)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(KBTheme.gradient(tab.tint))
                                .matchedGeometryEffect(id: "pill", in: namespace)
                                .shadow(color: tab.tint.opacity(0.35), radius: 4, y: 2)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            Capsule().fill(.quaternary.opacity(0.4))
        }
        .overlay {
            Capsule().strokeBorder(.quaternary.opacity(0.55), lineWidth: 1)
        }
    }
}
