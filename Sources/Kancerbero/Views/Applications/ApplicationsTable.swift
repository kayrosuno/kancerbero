import AppKit
import SwiftUI
import KancerberoCore

struct ApplicationsTable: View {
    @Environment(ApplicationsModel.self) private var model
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.4)
            columnHeader
            Divider().opacity(0.4)

            if model.isScanning, model.bundles.isEmpty {
                ProgressView("Scanning applications…")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleBundles.isEmpty {
                Text("No applications match the filter.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(model.visibleBundles.enumerated()),
                                id: \.element.id) { index, bundle in
                            row(bundle, shaded: index.isMultiple(of: 2))
                        }
                    }
                    .padding(8)
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

    private var searchBar: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            TextField("Filter applications", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .help("Filter by name, bundle identifier or path")
            Spacer(minLength: 8)
            Text("\(model.visibleBundles.count) of \(model.bundles.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Kind")
                .frame(width: 100, alignment: .leading)
            Text("Source")
                .frame(width: 90, alignment: .leading)
            Text("Size")
                .frame(width: 100, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func row(_ bundle: KBAppBundle, shaded: Bool) -> some View {
        Button {
            Task { await model.select(bundle.path) }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: Self.icon(for: bundle.path))
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bundle.name)
                            .font(.system(size: 16, weight: .medium))
                            .lineLimit(1)
                        if bundle.isProtected {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .help("Protected by macOS")
                        }
                    }
                    Text(bundle.bundleIdentifier ?? bundle.path)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(bundle.kind.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)

                Text(bundle.scope.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(bundle.scope == .system
                        ? Color.secondary
                        : Color.accentColor)
                    .frame(width: 90, alignment: .leading)

                Text(bundle.sizeBytes.map { KBFormat.bytes($0) } ?? "—")
                    .font(.system(size: 13, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selection == bundle.path
                        ? Color.accentColor.opacity(0.16)
                        : shaded ? Color.primary.opacity(0.04) : Color.clear)
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
        image.size = NSSize(width: 32, height: 32)
        icons.setObject(image, forKey: key)
        return image
    }
}
