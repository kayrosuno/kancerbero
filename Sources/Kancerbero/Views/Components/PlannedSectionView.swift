import SwiftUI

struct PlannedFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

struct PlannedSectionView: View {
    let section: AppSection
    let features: [PlannedFeature]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var glowing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                icon
                heading
                featureList
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 32)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(
                colors: [section.tint.opacity(0.11), .clear, section.tint.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            if !reduceMotion { glowing = true }
        }
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(KBTheme.gradient(section.tint))
                .frame(width: 96, height: 96)
                .shadow(color: section.tint.opacity(glowing ? 0.45 : 0.22),
                        radius: glowing ? 30 : 14)
            Image(systemName: section.systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white)
        }
        .scaleEffect(glowing && !reduceMotion ? 1.035 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                   value: glowing)
        .padding(.top, 10)
    }

    private var heading: some View {
        VStack(spacing: 9) {
            Text(section.title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(section.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("In development")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(section.tint.opacity(0.16)))
                .foregroundStyle(section.tint)
                .padding(.top, 2)
        }
    }

    private var featureList: some View {
        VStack(spacing: 10) {
            ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(section.tint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline.weight(.medium))
                        Text(feature.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                        .fill(.thinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                        .strokeBorder(.quaternary.opacity(0.45), lineWidth: 1)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.07), value: appeared)
            }
        }
    }
}
