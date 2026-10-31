import SwiftUI
import KancerberoCore

struct ProtocolCard: View {
    let counts: [KBConnectionProtocol: Int]
    let ipVersions: Set<NetworkingIPVersion>

    /// Only a single selected family is worth labelling; "all" means no filter.
    private var highlightedVersion: NetworkingIPVersion? {
        ipVersions.count == 1 ? ipVersions.first : nil
    }

    static let cardHeight: CGFloat = 80

    private static let order: [KBConnectionProtocol] = [
        .tcp4, .tcp6, .udp4, .udp6, .unix, .other
    ]

    private static let colors: [KBConnectionProtocol: Color] = [
        .tcp4: Color(red: 0.16, green: 0.55, blue: 0.90),
        .tcp6: Color(red: 0.35, green: 0.70, blue: 0.95),
        .udp4: Color(red: 0.15, green: 0.65, blue: 0.58),
        .udp6: Color(red: 0.40, green: 0.80, blue: 0.72),
        .unix: Color(red: 0.60, green: 0.45, blue: 0.90),
        .other: Color(red: 0.55, green: 0.57, blue: 0.63)
    ]

    private var total: Int {
        counts.values.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
                .frame(height: 16)

            ProtocolBar(counts: counts, order: Self.order, colors: Self.colors)
                .frame(height: 6)

            legend
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.cardHeight)
        .background {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.smallRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [KBTheme.downloadTint.opacity(0.28),
                                 KBTheme.uploadTint.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .help("Connection breakdown by protocol from NStat. " +
              "The Processes table also shows UNIX/RAW sockets from libproc.")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(KBTheme.brandGradient)
                )
            Text("Protocols")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            if let highlightedVersion {
                Text(highlightedVersion.title)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            Text(KBFormat.compactCount(total))
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private var legend: some View {
        VStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { column in
                        let proto = Self.order[row * 3 + column]
                        legendItem(proto, count: counts[proto] ?? 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: 11)
            }
        }
    }

    private func legendItem(_ proto: KBConnectionProtocol, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Self.colors[proto] ?? .gray)
                .frame(width: 6, height: 6)
            Text(proto.displayName)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(KBFormat.compactCount(count))
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? .primary : .tertiary)
        }
        .opacity(count > 0 ? 1 : 0.45)
    }

    private var accessibilityText: String {
        "Protocols: " + Self.order.map {
            "\($0.displayName) \(counts[$0] ?? 0)"
        }.joined(separator: ", ")
    }
}

private struct ProtocolBar: View {
    let counts: [KBConnectionProtocol: Int]
    let order: [KBConnectionProtocol]
    let colors: [KBConnectionProtocol: Color]

    var body: some View {
        Canvas { context, size in
            let total = counts.values.reduce(0, +)
            guard total > 0 else { return }

            context.clip(to: Path(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: 4
            ))

            let visible = order.compactMap { proto -> (KBConnectionProtocol, Int)? in
                let count = counts[proto] ?? 0
                return count > 0 ? (proto, count) : nil
            }

            var x: CGFloat = 0
            for (index, item) in visible.enumerated() {
                let isLast = index == visible.count - 1
                let width = max(
                    size.width * CGFloat(item.1) / CGFloat(total) - (isLast ? 0 : 2),
                    1
                )
                context.fill(
                    Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                    with: .color(colors[item.0] ?? .gray)
                )
                x += width + 2
            }
        }
        .background(Capsule().fill(.quaternary.opacity(0.35)))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
