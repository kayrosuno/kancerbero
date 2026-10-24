import SwiftUI
import KancerberoCore

struct SidebarView: View {
    @Binding var selection: AppSection?
    @Environment(AppModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            navigation
            Spacer(minLength: 0)
            Divider().opacity(0.4)
            footer
        }
        .background(.ultraThinMaterial)
    }

    private var navigation: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monitor")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                ForEach(AppSection.allCases) { section in
                    Button {
                        withAnimation(.snappy(duration: 0.28)) {
                            selection = section
                        }
                    } label: {
                        ZStack(alignment: .leading) {
                            if selection == section {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(section.tint.opacity(0.16))
                                    .matchedGeometryEffect(id: "sidebarSelection", in: namespace)
                            }
                            SidebarRow(section: section, isSelected: selection == section)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(KBTheme.brandGradient)
                    .frame(width: 34, height: 34)
                    .shadow(color: Color.blue.opacity(0.3), radius: 5, y: 2)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("kancerbero")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("System Monitor")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LiveDot(isLive: model.isLive)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.usingDaemon ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(model.usingDaemon ? "Daemon connected" : "Local mode")
                    .font(.system(size: 10, weight: .medium))
            }
            Text("Updated \(KBFormat.time(model.lastUpdate))")
            if model.privcheck >= 0 {
                Text("privcheck \(model.privcheck)")
            }
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(KBTheme.gradient(section.tint))
                        .shadow(color: section.tint.opacity(0.25), radius: 3, y: 1)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                Text(section.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
    }
}
