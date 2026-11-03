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

    /// Heat ramp for the headline rate values on the statistics cards: cool
    /// at idle through green, amber and orange to red at saturation.
    /// Thresholds are bytes per second, so one ramp serves disk throughput
    /// and network rates. Each appearance gets tones with enough contrast
    /// for the 18 pt semibold value over the card material.
    static func rateHeat(_ bytesPerSecond: Double, scheme: ColorScheme) -> Color {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return .secondary }
        let dark = scheme == .dark
        switch bytesPerSecond {
        case ..<(100 * 1024):
            return dark ? Color(red: 0.35, green: 0.67, blue: 0.98)
                        : Color(red: 0.10, green: 0.40, blue: 0.80)
        case ..<(1024 * 1024):
            return dark ? Color(red: 0.25, green: 0.78, blue: 0.56)
                        : Color(red: 0.05, green: 0.45, blue: 0.30)
        case ..<(10 * 1024 * 1024):
            return dark ? Color(red: 0.98, green: 0.74, blue: 0.25)
                        : Color(red: 0.58, green: 0.36, blue: 0.00)
        case ..<(100 * 1024 * 1024):
            return dark ? Color(red: 1.00, green: 0.58, blue: 0.20)
                        : Color(red: 0.75, green: 0.30, blue: 0.00)
        default:
            return dark ? Color(red: 1.00, green: 0.44, blue: 0.40)
                        : Color(red: 0.74, green: 0.13, blue: 0.11)
        }
    }

    static let summaryCardMinWidth: CGFloat = 170
    static let summaryGridSpacing: CGFloat = 10
    static let summaryColumns = [GridItem(.adaptive(minimum: 170), spacing: 10)]

    static let downloadTint = Color(red: 0.16, green: 0.62, blue: 0.94)
    static let uploadTint = Color(red: 0.62, green: 0.42, blue: 0.95)
    /// Categorical palette used by the Analyzer radial map.
    static let diskChartPalette: [Color] = [
        Color(red: 0.94, green: 0.56, blue: 0.18),
        Color(red: 0.90, green: 0.35, blue: 0.30),
        Color(red: 0.20, green: 0.70, blue: 0.62),
        Color(red: 0.16, green: 0.62, blue: 0.94),
        Color(red: 0.62, green: 0.42, blue: 0.95),
        Color(red: 0.85, green: 0.65, blue: 0.20),
        Color(red: 0.45, green: 0.65, blue: 0.35),
        Color(red: 0.70, green: 0.45, blue: 0.30)
    ]
    /// Networking cards: download uses the TCP4 chip colour and upload the
    /// UDP6 chip colour from the Protocols card, so both stay in sync.
    static let netDownloadTint = Color(red: 0.16, green: 0.55, blue: 0.90)
    static let netUploadTint = Color(red: 0.40, green: 0.80, blue: 0.72)
    static let connectionsTint = Color(red: 0.20, green: 0.70, blue: 0.62)
    static let activeTint = Color(red: 0.16, green: 0.62, blue: 0.94)
    static let processesTint = Color(red: 0.94, green: 0.56, blue: 0.18)
    static let approvalAllowTint = Color(red: 0.20, green: 0.72, blue: 0.52)
    static let approvalDenyTint = Color(red: 0.92, green: 0.30, blue: 0.26)

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
