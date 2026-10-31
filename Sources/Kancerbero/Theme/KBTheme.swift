import SwiftUI

enum KBTheme {
    static let sidebarWidth: CGFloat = 252
    static let contentPadding: CGFloat = 18
    static let cardRadius: CGFloat = 16
    static let smallRadius: CGFloat = 12

    /// Fixed height of the dashboard card strip. Keeps the cards the same size
    /// while the window is resized; the process table absorbs the extra space.
    static let cardStripHeight: CGFloat = 190

    /// Thermal bands shared by the core rows and the package badge.
    static func temperatureTint(_ celsius: Double?) -> Color {
        guard let celsius, celsius.isFinite else { return .secondary }
        switch celsius {
        case ..<50:
            return Color(red: 0.20, green: 0.72, blue: 0.52)
        case ..<70:
            return Color(red: 0.92, green: 0.74, blue: 0.24)
        case ..<85:
            return Color(red: 0.95, green: 0.56, blue: 0.18)
        default:
            return Color(red: 0.92, green: 0.30, blue: 0.26)
        }
    }

    /// Load heat ramp for the per-core bar history: cool blue at idle through
    /// green, yellow and orange to red at saturation.
    static func loadHeat(_ percent: Double) -> Color {
        guard percent.isFinite else { return .secondary }
        switch percent {
        case ..<25:
            return Color(red: 0.16, green: 0.62, blue: 0.94)
        case ..<50:
            return Color(red: 0.20, green: 0.72, blue: 0.52)
        case ..<70:
            return Color(red: 0.92, green: 0.74, blue: 0.24)
        case ..<85:
            return Color(red: 0.95, green: 0.56, blue: 0.18)
        default:
            return Color(red: 0.92, green: 0.30, blue: 0.26)
        }
    }

    static let summaryCardMinWidth: CGFloat = 170
    static let summaryGridSpacing: CGFloat = 10
    static let summaryColumns = [GridItem(.adaptive(minimum: 170), spacing: 10)]

    static let downloadTint = Color(red: 0.16, green: 0.62, blue: 0.94)
    static let uploadTint = Color(red: 0.62, green: 0.42, blue: 0.95)
    static let connectionsTint = Color(red: 0.20, green: 0.70, blue: 0.62)
    static let processesTint = Color(red: 0.94, green: 0.56, blue: 0.18)

    static var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.055),
                    Color.clear,
                    Color(nsColor: .windowBackgroundColor).opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.18, green: 0.68, blue: 0.92),
                 Color(red: 0.24, green: 0.42, blue: 0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.62)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
