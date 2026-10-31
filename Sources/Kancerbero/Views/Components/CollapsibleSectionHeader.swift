import SwiftUI

/// Section title plus the per-section control that hides or shows the
/// dashboard cards below it. The toolbar has an equivalent global control.
struct CollapsibleSectionHeader: View {
    let section: AppSection
    let title: String
    let subtitle: String

    @Environment(UIState.self) private var ui
    @AppStorage(KBPreferences.tabAnimationsKey)
    private var tabAnimations = KBPreferences.tabAnimationsDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var collapsed: Bool {
        ui.cardsCollapsed(for: section)
    }

    private var animation: Animation? {
        KBPreferences.collapseAnimation(stored: tabAnimations,
                                        reduceMotion: reduceMotion)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle)
                .layoutPriority(1)

            Button {
                withAnimation(animation) {
                    ui.toggleCards(for: section)
                }
            } label: {
                HStack(spacing: 5) {
                    Text(collapsed ? "Show cards" : "Hide cards")
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(collapsed ? Color.accentColor : Color.secondary)
                .background {
                    Capsule().fill(collapsed
                        ? Color.accentColor.opacity(0.14)
                        : Color.secondary.opacity(0.10))
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(collapsed ? "Show \(title) dashboard cards"
                            : "Hide \(title) dashboard cards")
            .accessibilityLabel(collapsed ? "Show \(title) cards"
                                          : "Hide \(title) cards")
            .accessibilityIdentifier("section.cards.\(section.rawValue)")
        }
    }
}
