import AppKit
import SwiftUI
import KancerberoCore

struct ApplicationsTable: View {
    @Environment(ApplicationsModel.self) private var model
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            if model.isScanning, model.bundles.isEmpty {
                ProgressView("Scanning applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleBundles.isEmpty {
                Text("No applications match the filter.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.visibleBundles) { bundle in
                            row(bundle)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBTheme.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Kind")
                .frame(width: 90, alignment: .leading)
            Text("Size")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func row(_ bundle: KBAppBundle) -> some View {
        Button {
            Task { await model.select(bundle.path) }
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: Self.icon(for: bundle.path))
                    .resizable()
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(bundle.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if bundle.isProtected {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .help("Protected by macOS")
                        }
                    }
                    Text(bundle.bundleIdentifier ?? bundle.path)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(bundle.kind.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)

                Text(bundle.sizeBytes.map { KBFormat.bytes($0) } ?? "—")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selection == bundle.path
                        ? Color.accentColor.opacity(0.16)
                        : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let icons = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = icons.object(forKey: key) {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 20, height: 20)
        icons.setObject(image, forKey: key)
        return image
    }
}
