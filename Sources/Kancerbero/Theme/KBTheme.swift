import SwiftUI

enum KBTheme {
    static let sidebarWidth: CGFloat = 252
    static let contentPadding: CGFloat = 18
    static let cardRadius: CGFloat = 16
    static let smallRadius: CGFloat = 12

    static let summaryCardMinWidth: CGFloat = 170
    static let summaryGridSpacing: CGFloat = 10
    static let summaryColumns = [GridItem(.adaptive(minimum: 170), spacing: 10)]

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
